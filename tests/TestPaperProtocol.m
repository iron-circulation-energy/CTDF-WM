classdef TestPaperProtocol < matlab.unittest.TestCase
    % Small offline fixtures exercise the protocol checks.
    methods (Test)
        function exactPaperBudgetHasNoRuntimePromise(tc)
            tc.assertEqual(exist('params_paper','file'),2);
            p=params_paper();
            tc.verifyEqual([p.ctdf.width p.ctdf.nBlocks p.ctdf.dCond p.ctdf.dT],[256 2 256 64]);
            tc.verifyEqual([p.data.nTransitions p.data.valFrac p.ctdf.stepsPerStage p.ctdf.batch],[300000 .1 5000 256]);
            tc.verifyEqual(p.ctdf.gammaStages,[.8 .9 .95 .99]);
            tc.verifyEqual(p.ctdf.gpiMode,'distributed');
            tc.verifyEqual(p.exp.seeds,1:3); tc.verifyEqual(p.exp.elementSeeds,1);
            tc.verifyEqual(p.exp.e3MethodSeeds.M3,1);
            tc.verifyEqual(p.exp.e3MethodScenarios.M3,{'normal','drought'});
            tc.verifyEqual([p.ctdf.K p.exp.stepwiseK p.exp.stepwiseTcapCtrl p.exp.gtR p.exp.gtTcap],[32 8 60 32 400]);
            tc.verifyFalse(isfield(p,'runtime'));
        end

        function staticCheckCountsActualPlannedModelsAndEpisodes(tc)
            requireAPI(tc); r=paperProtocolPreflight(params_paper(),[],struct('mode','static'));
            tc.verifyTrue(r.passed); tc.verifyTrue(r.protocolConformant); tc.verifyFalse(r.dataReady);
            tc.verifyEqual(r.dataStatus,'not_checked');
            tc.verifyEqual(budget(r,'trained_models'),12);
            tc.verifyEqual(budget(r,'optimizer_steps'),240000);
            tc.verifyEqual(budget(r,'E2_episodes'),450);   % 12 个绝对网格点 + 3 个理论锚点，2 种方法 × 5 年 × 3 种子
            tc.verifyEqual(budget(r,'E2_extra_episodes'),30);   % M4 两个质量点 × 5 年 × 3 种子
            tc.verifyEqual(budget(r,'E3_episodes'),260);         % 4 种方法全种子全工况 240 + M3、M2o 各 1 种子 2 工况 20
            tc.verifyEqual(budget(r,'M3_closed_loop_episodes'),10);
            tc.verifyEqual(budget(r,'E5_episodes'),100);
        end

        function changedScientificBudgetFailsBeforeDataAccess(tc)
            requireAPI(tc); p=params_paper(); p.ctdf.K=128;
            r=paperProtocolPreflight(p,[],struct('mode','static'));
            tc.verifyFalse(r.protocolConformant);
            tc.verifyEqual(checkStatus(r,'contract.ctdf.K'),'fail');
            tc.verifyError(@() paperProtocolPreflight(p,[],struct('mode','static','throwOnError',true)), ...
                'paperProtocolPreflight:failed');
        end

        function calendarAndMatchedSubsetAreContracts(tc)
            requireAPI(tc); p=params_paper(); p.weather.val=20:24; p.exp.e3MethodSeeds.M3=4;
            r=paperProtocolPreflight(p,[],struct('mode','static'));
            tc.verifyFalse(r.passed);
            tc.verifyEqual(checkStatus(r,'split.disjoint'),'fail');
            tc.verifyEqual(checkStatus(r,'coverage.M3Seeds'),'fail');
        end

        function absentDataIsMissingWithoutFilesystemOrNetworkSideEffects(tc)
            requireAPI(tc); p=params_paper(); d=tempname;
            p.weather.era5.dataDir=d; p.weather.csvFile=fullfile(d,'haoji_daily.csv');
            p.weather.provenanceFile=fullfile(d,'provenance.mat');
            r=paperProtocolPreflight(p,[],struct('mode','prepared'));
            tc.verifyTrue(r.protocolConformant); tc.verifyFalse(r.passed); tc.verifyFalse(r.dataReady);
            tc.verifyEqual(r.dataStatus,'missing'); tc.verifyFalse(isfolder(d));
        end

        function csvLabelAloneIsInsufficientForSource(tc)
            requireAPI(tc); d=tempname; mkdir(d); c=onCleanup(@() rmdir(d,'s')); %#ok<NASGU>
            p=params_paper(); p.weather.source='csv'; p.weather.era5.dataDir=d;
            p.weather.provenanceFile=fullfile(d,'provenance.mat');
            p.weather.csvFile=fullfile(d,'haoji_daily.csv');
            year=repelem((1995:2025)',365); day=repmat((1:365)',31,1);
            EW=ones(size(day)); ES=EW; EL=EW; writetable(table(year,day,EW,ES,EL),p.weather.csvFile);
            r=paperProtocolPreflight(p,[],struct('mode','prepared'));
            tc.verifyFalse(r.dataReady); tc.verifyEqual(checkStatus(r,'data.provenance'),'missing');
        end

        function preparedManifestBindsFitCsvRawAndDataTypes(tc)
            requireAPI(tc); [p,c]=preparedFixture(); %#ok<NASGU>
            tc.assertTrue(isfield(p.weather,'provenanceFile'));
            L=load(p.weather.provenanceFile,'manifest'); m=L.manifest;
            tc.verifyEqual(m.fitYears,2019); tc.verifyEqual(m.calibrationYear,2019);
            tc.verifyEqual(m.tailYear,2020); tc.verifyEqual(m.types.load,'scenario_temperature_reconstruction');
            tc.verifyEqual(m.types.renewables,'derived_from_ERA5_reanalysis');
            tc.verifyEqual(m.csv.sha256,fileSHA256(p.weather.csvFile));
            tc.verifyEqual(numel(m.raw),4);
            r=paperProtocolPreflight(p,[],struct('mode','prepared'));
            % This tiny fixture has a valid local data chain, but not the paper split.
            tc.verifyTrue(r.dataReady); tc.verifyFalse(r.protocolConformant); tc.verifyFalse(r.passed);
            tc.verifyEqual(checkStatus(r,'data.fileHashes'),'pass');
        end

        function modifiedCsvCannotReuseManifest(tc)
            requireAPI(tc); [p,c]=preparedFixture(); %#ok<NASGU>
            T=readtable(p.weather.csvFile); T.EW(1)=T.EW(1)+1; writetable(T,p.weather.csvFile);
            r=paperProtocolPreflight(p,[],struct('mode','prepared'));
            tc.verifyFalse(r.dataReady); tc.verifyEqual(checkStatus(r,'data.fileHashes'),'fail');
        end

        function modifiedRawCacheCannotReuseManifest(tc)
            requireAPI(tc); [p,c]=preparedFixture(); %#ok<NASGU>
            f=fullfile(p.weather.era5.dataDir,'raw','wind_fixture_2019.mat');
            L=load(f); L.T.wind_speed_100m(1)=11; save(f,'-struct','L');
            r=paperProtocolPreflight(p,[],struct('mode','prepared'));
            tc.verifyFalse(r.dataReady); tc.verifyEqual(checkStatus(r,'data.fileHashes'),'fail');
        end

        function omittedProcessingSourceCannotPassProvenance(tc)
            requireAPI(tc); [p,c]=preparedFixture(); %#ok<NASGU>
            L=load(p.weather.provenanceFile,'manifest'); manifest=L.manifest;
            manifest.processors=manifest.processors(1:end-1); save(p.weather.provenanceFile,'manifest');
            r=paperProtocolPreflight(p,[],struct('mode','prepared'));
            tc.verifyFalse(r.dataReady); tc.verifyEqual(checkStatus(r,'data.processingSources'),'fail');
        end

        function changedSourceAndMaterialBoundaryCannotPassContract(tc)
            requireAPI(tc); p=params_paper(); p.weather.era5.reSites(1).lat=0;
            p.makeup.reserveFrac=.1;
            r=paperProtocolPreflight(p,[],struct('mode','static'));
            tc.verifyFalse(r.passed);
        end

        function paperPredictionBudgetCannotBeOverridden(tc)
            requireAPI(tc); p=params_paper(); p.exp.predictionSamples=512;
            r=paperProtocolPreflight(p,[],struct('mode','static'));
            tc.verifyFalse(r.passed);
            tc.verifyEqual(checkStatus(r,'contract.exp.predictionSamples'),'fail');
            p.exp.predictionSamples=1024;
            r=paperProtocolPreflight(p,[],struct('mode','static'));
            tc.verifyTrue(r.passed);
        end

        function changedEconomicAndNetworkContractsAreRejected(tc)
            requireAPI(tc); base=params_paper();
            candidates=repmat({base},1,4);
            candidates{1}.cost.piShed=1;
            candidates{2}.net.lines{1,5}=100;
            candidates{3}.init.feSplit=[1 0 0 0];
            candidates{4}.retire.eueTol=.5;
            for k=1:numel(candidates)
                r=paperProtocolPreflight(candidates{k},[],struct('mode','static'));
                tc.verifyFalse(r.passed);
            end
        end

        function duplicateHourlyTimestampIsRejected(tc)
            requireAPI(tc); [p,c]=preparedFixture(); %#ok<NASGU>
            f=fullfile(p.weather.era5.dataDir,'raw','wind_fixture_2019.mat');
            L=load(f); L.T.time(2)=L.T.time(1); save(f,'-struct','L');
            z=load(fullfile(p.weather.era5.dataDir,'fit_report.mat'),'rep');
            tc.verifyError(@() writeWeatherProvenance(p,z.rep),'writeWeatherProvenance:calendar');
        end

        function wrongProvidedWeatherCannotPassPreparedCheck(tc)
            requireAPI(tc); [p,c]=preparedFixture(); %#ok<NASGU>
            W=readWeatherCSV(p.weather.csvFile,p); W(1).EW(1)=W(1).EW(1)+5;
            r=paperProtocolPreflight(p,W,struct('mode','prepared'));
            tc.verifyFalse(r.dataReady); tc.verifyEqual(checkStatus(r,'data.weatherMatchesCSV'),'fail');
        end
    end
end

function requireAPI(tc)
tc.assertEqual(exist('params_paper','file'),2);
tc.assertEqual(exist('paperProtocolPreflight','file'),2);
end
function n=budget(r,id)
n=r.budget.Count(strcmp(r.budget.Component,id));
end
function v=checkStatus(r,id)
row=r.checks(strcmp(r.checks.CheckId,id),:);
if isempty(row), v='absent'; else, v=row.Status{1}; end
end
function [p,c]=preparedFixture()
p=params_paper(); d=tempname; mkdir(d); mkdir(fullfile(d,'raw'));
c=onCleanup(@() rmdir(d,'s'));
p.weather.Y=1; p.weather.train=1; p.weather.val=1; p.weather.test=1;
e=p.weather.era5; e.years=2019; e.tailYear=2020; e.dataDir=d; e.pause=0;
e.rescaleCap=false;
e.reSites=struct('name','wind_fixture','lat',31,'lon',120,'windTarget',2628, ...
    'pvTarget',NaN,'windWeight',1,'pvWeight',1);
e.loadSites=struct('name','load_fixture','lat',32,'lon',121,'weight',1);
for y=[2019 2020]
    time=(datetime(y,1,1):hours(1):datetime(y,12,31,23,0,0))'; n=numel(time);
    temperature_2m=15+2*cos(2*pi*(day(time,'dayofyear')-1)/365);
    wind_speed_100m=10*ones(n,1);
    surface_pressure=1.225*287.05*(temperature_2m+273.15)/100;
    shortwave_radiation=800*max(0,sin(pi*(hour(time)-6)/12));
    direct_radiation=.8*shortwave_radiation; diffuse_radiation=.2*shortwave_radiation;
    T=table(time,wind_speed_100m,temperature_2m,surface_pressure,shortwave_radiation,direct_radiation,diffuse_radiation);
    sites={e.reSites,e.loadSites};
    for k=1:2
        site=sites{k}; cacheMeta=struct('schema',1,'lat',site.lat,'lon',site.lon,'year',y, ...
            'model',e.model,'timezone',e.timezone,'url',e.url,'windSpeedUnit','ms');
        save(fullfile(d,'raw',sprintf('%s_%d.mat',site.name,y)),'T','cacheMeta');
    end
end
p.weather.era5=e; [p,~]=prepareRealData(p);
end
