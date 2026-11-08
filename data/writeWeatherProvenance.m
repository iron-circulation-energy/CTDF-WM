function [manifest, file] = writeWeatherProvenance(p, rep)
%WRITEWEATHERPROVENANCE Bind local weather inputs to their derived products.
% Called only after prepareRealData has saved the daily CSV and fit_report.
% Request metadata records source identity; cache hashes bind raw and derived files.
e=p.weather.era5;
manifest.schemaVersion=1;
manifest.generator='prepareRealData';
manifest.createdUTC=char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
manifest.provider='Open-Meteo historical API';
manifest.model=upper(char(e.model));
manifest.modelYears=e.years(:)'; manifest.tailYear=e.tailYear;
manifest.fitYears=e.years(p.weather.train);
manifest.calibrationYear=e.windCalYear;
manifest.calibrationBoundary='External 2019 structural calibration; not a training-weather observation.';
manifest.types=struct('rawWeather','reanalysis','renewables','derived_from_ERA5_reanalysis', ...
    'load','scenario_temperature_reconstruction','capacity','declared_scenario');
manifest.request=e;
manifest.processing=processingIdentity(p);
manifest.csv=asset(p.weather.csvFile,'derived_daily_weather');
manifest.fit=asset(fullfile(e.dataDir,'fit_report.mat'),'training_weather_fit');
manifest.capacityScale=rep.capScale;
manifest.raw=struct('id',{},'kind',{},'path',{},'sha256',{},'calendarYear',{}, ...
    'request',{},'variables',{},'hourCount',{},'calendarVerified',{},'missingAudit',{});
years=[e.years(:)' e.tailYear];
for k=1:numel(e.reSites)
    for y=years
        manifest.raw(end+1)=rawAsset(e.reSites(k),y,e.vars,e,'renewable_weather'); %#ok<AGROW>
    end
end
if isempty(e.loadFile)
    for k=1:numel(e.loadSites)
        for y=years
            manifest.raw(end+1)=rawAsset(e.loadSites(k),y,{'temperature_2m'},e,'load_temperature'); %#ok<AGROW>
        end
    end
    manifest.externalLoad=[];
else
    manifest.types.load='external_load_source_unverified';
    manifest.externalLoad=asset(e.loadFile,'external_load_source_unverified');
end
root=fileparts(fileparts(mfilename('fullpath')));
names={'data/prepareRealData.m','data/fetchERA5OpenMeteo.m','data/era5ToHourly.m', ...
    'data/calibrateWindAlpha.m','data/windCF.m','data/fitWeatherModel.m', ...
    'data/readWeatherCSV.m','data/classifyRegime.m','data/hourlyProfiles.m', ...
    'data/writeWeatherProvenance.m'};
manifest.processors=repmat(struct('path','','sha256','','kind',''),1,numel(names));
for k=1:numel(names), manifest.processors(k)=asset(fullfile(root,names{k}),'processing_source'); end
manifest.limitations=['Cache hashes and request identity make the local processing chain reproducible; ' ...
    'load is reconstructed from temperature.'];
file=fullfile(e.dataDir,'provenance.mat');
tmp=[file '.tmp']; save(tmp,'manifest','-mat'); movefile(tmp,file,'f');
A=[manifest.csv manifest.fit manifest.processors];
if ~isempty(manifest.externalLoad), A=[A manifest.externalLoad]; end
ids={A.kind}; paths={A.path}; hashes={A.sha256};
for k=1:numel(manifest.raw)
    ids{end+1}=manifest.raw(k).kind; paths{end+1}=manifest.raw(k).path; hashes{end+1}=manifest.raw(k).sha256; %#ok<AGROW>
end
T=table(ids(:),paths(:),hashes(:),'VariableNames',{'Type','Path','SHA256'});
writetable(T,fullfile(e.dataDir,'data_provenance.csv'),'Encoding','UTF-8');
end

function a=asset(file,kind)
if ~isfile(file), error('writeWeatherProvenance:missing','Required local input is missing: %s',file); end
a=struct('path',file,'sha256',fileSHA256(file),'kind',kind);
end

function a=rawAsset(site,y,vars,e,kind)
f=fullfile(e.dataDir,'raw',sprintf('%s_%d.mat',site.name,y));
if ~isfile(f), error('writeWeatherProvenance:missing','Missing raw cache: %s',f); end
L=load(f,'T','cacheMeta');
want=struct('schema',1,'lat',site.lat,'lon',site.lon,'year',y,'model',char(e.model), ...
    'timezone',char(e.timezone),'url',char(e.url),'windSpeedUnit','ms');
if ~isfield(L,'cacheMeta') || ~isequaln(L.cacheMeta,want) || ~isfield(L,'T') || ...
        ~all(ismember([{'time'} vars],L.T.Properties.VariableNames))
    error('writeWeatherProvenance:identity','Raw cache request/variables do not match: %s',f);
end
t=(datetime(y,1,1):hours(1):datetime(y,12,31,23,0,0))';
if ~isequal(L.T.time(:),t)
    error('writeWeatherProvenance:calendar','Raw cache must contain every unique hour in order: %s',f);
end
for j=1:numel(vars)
    v=L.T.(vars{j});
    if ~isnumeric(v) || any(~isfinite(v(:)))
        error('writeWeatherProvenance:values','Raw cache contains nonfinite %s: %s',vars{j},f);
    end
end
a=struct('id',sprintf('%s_%d',site.name,y),'kind',kind,'path',f,'sha256',fileSHA256(f), ...
    'calendarYear',y,'request',want,'variables',{vars},'hourCount',numel(t),'calendarVerified',true, ...
    'missingAudit','pre-interpolation mask and retrieval time unavailable in this cache schema');
end

function id=processingIdentity(p)
w=p.weather;
w=rmfield(w,intersect(fieldnames(w),{'provenanceFile','csvFile'}));
id=struct('weather',w,'re',p.re,'load',p.load);
end
