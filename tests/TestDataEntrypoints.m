classdef TestDataEntrypoints < matlab.unittest.TestCase
    % Offline regressions for weather-cache identity and calendar alignment.
    methods (Test)
        function cachedWeatherCannotChangeItsRequestedIdentity(tc)
            d = tempname; mkdir(d); c = onCleanup(@() rmdir(d,'s')); %#ok<NASGU>
            site = struct('name','fixture','lat',31,'lon',120);
            opt = struct('rawDir',d,'vars',{{'temperature_2m'}}, ...
                'url','unsupported-protocol://offline','pause',0,'maxRetry',1, ...
                'model','era5','timezone','Asia/Shanghai');
            T = hourlyFixture(2019);
            cacheMeta = fixtureMeta(site,2019,opt);
            save(fullfile(d,'fixture_2019.mat'),'T','cacheMeta');
            H = fetchERA5OpenMeteo(site,2019,opt);
            tc.verifyEqual(H{1},T);
            changed = site; changed.lat = 32;
            tc.verifyError(@() fetchERA5OpenMeteo(changed,2019,opt),'fetchERA5OpenMeteo:http');
            changed = site; changed.lon = 121;
            tc.verifyError(@() fetchERA5OpenMeteo(changed,2019,opt),'fetchERA5OpenMeteo:http');
            changedOpt = opt; changedOpt.model = 'era5_land';
            tc.verifyError(@() fetchERA5OpenMeteo(site,2019,changedOpt),'fetchERA5OpenMeteo:http');
            changedOpt = opt; changedOpt.timezone = 'UTC';
            tc.verifyError(@() fetchERA5OpenMeteo(site,2019,changedOpt),'fetchERA5OpenMeteo:http');
        end

        function legacyWeatherCacheMustBeRevalidated(tc)
            d = tempname; mkdir(d); c = onCleanup(@() rmdir(d,'s')); %#ok<NASGU>
            site = struct('name','fixture','lat',31,'lon',120);
            opt = struct('rawDir',d,'vars',{{'temperature_2m'}}, ...
                'url','unsupported-protocol://offline','pause',0,'maxRetry',1);
            T = hourlyFixture(2019);
            save(fullfile(d,'fixture_2019.mat'),'T');
            tc.verifyError(@() fetchERA5OpenMeteo(site,2019,opt),'fetchERA5OpenMeteo:http');
        end

        function windCalibrationFindsReachableRootBeforeCutout(tc)
            p = params_default('haoji');
            d = tempname; mkdir(d); mkdir(fullfile(d,'raw'));
            c = onCleanup(@() rmdir(d,'s')); %#ok<NASGU>
            p.weather.Y = 1; p.weather.train = 1; p.weather.val = 1; p.weather.test = 1;
            e = p.weather.era5;
            e.years = 2019; e.tailYear = 2020; e.dataDir = d; e.pause = 0;
            e.rescaleCap = false;
            e.reSites = struct('name','fixture','lat',31,'lon',120, ...
                'windTarget',2628,'pvTarget',NaN,'windWeight',1,'pvWeight',1);
            site = e.reSites;
            for y = [2019,2020]
                T = hourlyFixture(y);
                cacheMeta = fixtureMeta(site,y,e);
                save(fullfile(d,'raw',sprintf('fixture_%d.mat',y)),'T','cacheMeta');
            end
            year = repelem([2019;2020],365); day = repmat((1:365)',2,1); load = ones(730,1);
            writetable(table(year,day,load),fullfile(d,'load.csv'));
            e.loadFile = fullfile(d,'load.csv'); p.weather.era5 = e;
            [~,rep] = prepareRealData(p);
            % With U=10, target=0.3 and loss=0.1: (10*a)^3=27+1701/3=594.
            tc.verifyEqual(rep.alpha,nthroot(594,3)/10,'AbsTol',1e-10);
            R = readtable(fullfile(d,'era5_report.csv'));
            tc.verifyEqual(R.windHours,[2628;2628],'AbsTol',1e-7);
        end

        function weightedCalibrationChecksAttainability(tc)
            p = params_default('haoji'); e = p.weather.era5;
            [a,matched] = calibrateWindAlpha([10,20],.3,e,[.75,.25]);
            % alpha=.6 gives CF=[.1,.9], hence .75*.1+.25*.9=.3.
            tc.verifyTrue(matched); tc.verifyEqual(a,.6,'AbsTol',1e-10);
            [~,matched] = calibrateWindAlpha(10,.95,e);
            tc.verifyFalse(matched); % loss=10% bounds every attainable CF by .9.
        end

        function nationalCalibrationUsesTheSameCutoutAwareRoot(tc)
            n = params_national();
            d = tempname; mkdir(d); mkdir(fullfile(d,'raw'));
            c = onCleanup(@() rmdir(d,'s')); %#ok<NASGU>
            n.outDir = d; n.era5.rawDir = fullfile(d,'raw');
            n.era5.years = 2019:2021; n.era5.pause = 0;
            site = struct('name','fixture','lat',31,'lon',120);
            N.pts = table(["fixture";"fixture"],[31;31],[120;120],[1;1], ...
                ["wind";"pv"],[1;1],'VariableNames',{'key','lat','lon','provIdx','kind','weight'});
            N.prov = table("fixture",2628,0,'VariableNames',{'name','windHours','windCurt'});
            for y = 2019:2021
                T = hourlyFixture(y); cacheMeta = fixtureMeta(site,y,n.era5);
                save(fullfile(n.era5.rawDir,sprintf('fixture_%d.mat',y)),'T','cacheMeta');
            end
            Cl = natClimate(N,n);
            tc.verifyEqual(Cl.alpha,nthroot(594,3)/10,'AbsTol',1e-10);
            tc.verifyEqual(Cl.windHours,2628,'AbsTol',1e-7);
            tc.verifyTrue(Cl.complete); tc.verifyFalse(Cl.clipped);
        end

        function missingOrDuplicateDaysCannotShiftTheNextYear(tc)
            p = params_default('smoke'); p.weather.csvLastIsTail = true;
            d = tempname; mkdir(d); c = onCleanup(@() rmdir(d,'s')); %#ok<NASGU>
            year = repelem([2019;2020],365); day = repmat((1:365)',2,1);
            EW = 100*day; ES = EW; EL = EW; T = table(year,day,EW,ES,EL);
            f = fullfile(d,'weather.csv');
            writetable(T([1,3:end],:),f);
            tc.verifyError(@() readWeatherCSV(f,p),'readWeatherCSV:calendar');
            duplicate = T; duplicate.day(2) = 1; writetable(duplicate,f);
            tc.verifyError(@() readWeatherCSV(f,p),'readWeatherCSV:calendar');
            writetable(T,f); W = readWeatherCSV(f,p);
            tc.verifyEqual(W.EW(365:366),[36500,100]);
            tc.verifyEqual(W.sourceYearIndex(365:366),[1,2]);
        end

        function leapYearCsvRequiresTheSame365DayCalendarAsEra5(tc)
            p = params_default('smoke');
            d = tempname; mkdir(d); c = onCleanup(@() rmdir(d,'s')); %#ok<NASGU>
            year = 2020*ones(366,1); day = (1:366)'; EW = day; ES = day; EL = day;
            f = fullfile(d,'weather.csv'); writetable(table(year,day,EW,ES,EL),f);
            tc.verifyError(@() readWeatherCSV(f,p),'readWeatherCSV:calendar');
        end

        function nonconsecutiveYearsCannotBeJoinedAsAdjacentWeather(tc)
            p = params_default('smoke'); p.weather.csvLastIsTail = true;
            d = tempname; mkdir(d); c = onCleanup(@() rmdir(d,'s')); %#ok<NASGU>
            year = repelem([2019;2021],365); day = repmat((1:365)',2,1);
            EW = day; ES = day; EL = day;
            f = fullfile(d,'weather.csv'); writetable(table(year,day,EW,ES,EL),f);
            tc.verifyError(@() readWeatherCSV(f,p),'readWeatherCSV:calendar');
        end
    end
end

function T = hourlyFixture(y)
t = (datetime(y,1,1):hours(1):datetime(y,12,31,23,0,0))';
n = numel(t); wind = 10*ones(n,1); temp = 15*ones(n,1);
pressure = (1.225*287.05*(15+273.15)/100)*ones(n,1);
G = 800*max(0,sin(pi*(hour(t)-6)/12));
T = table(t,wind,temp,pressure,G,.8*G,.2*G, ...
    'VariableNames',{'time','wind_speed_100m','temperature_2m','surface_pressure', ...
    'shortwave_radiation','direct_radiation','diffuse_radiation'});
end

function m = fixtureMeta(site,y,opt)
m = struct('schema',1,'lat',site.lat,'lon',site.lon,'year',y, ...
    'model',char(opt.model),'timezone',char(opt.timezone),'url',char(opt.url), ...
    'windSpeedUnit','ms');
end
