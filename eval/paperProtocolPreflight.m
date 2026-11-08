function report = paperProtocolPreflight(p, W, opts)
%PAPERPROTOCOLPREFLIGHT Read-only research contract and prepared-data checks.
% report = paperProtocolPreflight(p, [], struct('mode','static')) checks the
% manuscript budget without reading/downloading weather. mode='prepared'
% also checks the local CSV, fit and provenance chain, and W when supplied.
% Defaults: mode='prepared', throwOnError=false. It never fits, downloads,
% trains, starts workers, or evaluates trajectories. Budget rows are plans.
if nargin<2, W=[]; end
if nargin<3, opts=struct(); end
mode=validatestring(getf(opts,'mode','prepared'),{'static','prepared'});
rows=cell(0,8);
ref=params_paper();
fields={ ...
    'caseName','seed','net','cost','init','retire', ...
    'protocol.version','protocol.requireRealData','protocol.requireProvenance', ...
    'protocol.allowNetwork','protocol.allowSyntheticData','protocol.coveragePolicy', ...
    'weather.Y','weather.train','weather.val','weather.test','weather.daysPerYear', ...
    'weather.era5.years','weather.era5.tailYear','weather.era5.windCalYear', ...
    'weather.era5.model','weather.era5.timezone','weather.era5.loadFile', ...
    'weather.era5.url','weather.era5.vars','weather.era5.reSites','weather.era5.loadSites', ...
    'weather.era5.windBiasCorrect','weather.era5.rescaleCap', ...
    'weather.regLow','weather.regHigh','forecast.mode', ...
    'plant.pmax','plant.etaSt','plant.loss','plant.betaMax','station.pRedMax', ...
    'station.kappa','station.etaEl','station.epsAux','makeup.reserveFrac','aging.enable','grid.useDCPF', ...
    'data.nTransitions','data.valFrac','data.episodeLen','data.cCover','data.socRange', ...
    'policy.nLhs','policy.switchDays','policy.alignedProb','policy.epsExplore', ...
    'policy.perturbSigma','policy.flipProb','policy.addProb','policy.addFrac', ...
    'ctdf.width','ctdf.nBlocks','ctdf.dCond','ctdf.dT','ctdf.batch','ctdf.lr','ctdf.ema', ...
    'ctdf.stepsPerStage','ctdf.gammaStages','ctdf.wd','ctdf.beta1','ctdf.beta2','ctdf.gradClip', ...
    'ctdf.nOde','ctdf.alphaDir','ctdf.useGammaCurriculum','ctdf.useNullSpaceProj', ...
    'ctdf.useTerminalProj','ctdf.sourceType','ctdf.K','ctdf.nRandCand','ctdf.lambdaGrid', ...
    'ctdf.varthetaDays','ctdf.diagEvery','ctdf.nMicro','ctdf.gpiMode', ...
    'mpc.S','mpc.tune','mpc.tuneS','mpc.tuneHorizon','mpc.terminalMode','mpc.tuneIronValue','mpc.oxValueFrac', ...
    'stats.cNominalMode','stats.cNominalFixed','data.cRangeAbs','ctdf.decisionModes','ctdf.holdGrid','ctdf.distTol', ...
    'ctdf.selectCriterion','ctdf.safeZGrid','exp.e2Extra','station.kappa','mpc.tuneTerminalNet', ...
    'policy.ranges', ...
    'exp.seeds','exp.elementSeeds','exp.e1Method','exp.e2Methods','exp.e3Methods', ...
    'exp.e3MethodSeeds','exp.e3MethodScenarios','exp.e5Scenarios','exp.cGridN','exp.cGridAbs','exp.kneeBootB', ...
    'exp.gtStates','exp.gtValStates','exp.gtR','exp.gtTcap','exp.gtSamples','exp.predictionSamples', ...
    'exp.stepwiseK','exp.stepwiseTcapCtrl','exp.stepwiseTcap','exp.exactW1Max','exp.slicedDirs', ...
    'exp.evalDays','exp.warmup','exp.droughtDays','exp.outageDays','exp.stationOutDays', ...
    'exp.extremeStart','exp.scaleList','exp.timingReps','exp.heatN','exp.eueAbsTol', ...
    'exp.sens','exp.sensFactor','exp.heatRoundtrip','exp.heatTransport','exp.initSOC'};
for k=1:numel(fields)
    a=at(p,fields{k}); b=at(ref,fields{k});
    add(['contract.' fields{k}],'protocol',testStatus(isequaln(a,b)),a,b,'Locked manuscript/declared implementation contract.','');
end
dz=getf(p,'design',struct('ready',true));
add('design.ready','protocol',testStatus(isfield(dz,'ready') && dz.ready),getf(dz,'ready',false),true, ...
    'Design point (station power, circulating mass) must come from designScan for the current kappa; run designScan first.','config/design_point.mat');
tr=at(p,'weather.train'); va=at(p,'weather.val'); te=at(p,'weather.test');
add('split.disjoint','protocol',testStatus(isempty(intersect(tr,va)) && isempty(intersect(tr,te)) && isempty(intersect(va,te))), ...
    [tr va te],'disjoint train/validation/test indices','Warm-up may use preceding observed history; fitted windows may not cross split boundaries.','');
seeds=at(p,'exp.seeds'); abl=at(p,'exp.elementSeeds'); m3=at(p,'exp.e3MethodSeeds.M3');
add('coverage.M3Seeds','protocol',testStatus(~isempty(m3) && all(ismember(m3,seeds)) && numel(unique(m3))==numel(m3)), ...
    m3,'nonempty unique subset of training seeds','M3 closed-loop coverage is distinct from its three trained models.','');
add('coverage.elementSeeds','protocol',testStatus(~isempty(abl) && all(ismember(abl,seeds)) && numel(unique(abl))==numel(abl)), ...
    abl,'nonempty unique subset of training seeds','noTerminal reuses M1; only three single-element counterparts are retrained.','');
known=[ref.protocol.requiredExperiments,{'train','figW','fig02','fig03'}];
only=getf(p.exp,'only',known);
add('coverage.requestedExperiments','protocol',testStatus(iscell(only) && all(ismember(only,known)) && numel(unique(only))==numel(only)), ...
    only,known,'A valid subset of experiments is allowed.','');
add('scope.noRuntimePromise','protocol',testStatus(~isfield(p.protocol,'targetHours') && ~isfield(p.protocol,'core24')), ...
    'research protocol','no runtime promise','Runtime tuning is a separate stage.','');
if strcmp(mode,'prepared'), checkPrepared(); end
report.checks=cell2table(rows,'VariableNames',{'CheckId','Scope','Severity','Status','Observed','Expected','Message','Path'});
protocol=strcmp(report.checks.Scope,'protocol'); data=strcmp(report.checks.Scope,'data');
report.protocolConformant=all(strcmp(report.checks.Status(protocol),'pass'));
report.dataReady=any(data) && all(strcmp(report.checks.Status(data),'pass'));
if ~any(data)
    report.dataStatus='not_checked';
elseif any(strcmp(report.checks.Status(data),'missing'))
    report.dataStatus='missing';
elseif report.dataReady
    report.dataStatus='ready';
else
    report.dataStatus='invalid';
end
report.passed=report.protocolConformant && (strcmp(mode,'static') || report.dataReady);
report.mode=mode; report.protocolVersion=getf(p.protocol,'version','unknown');
report.budget=plannedBudget(p);
report.calibrationBoundary=ref.protocol.calibrationBoundary;
report.resultStatus='not_assessed';
report.note='Budget rows list the planned work.';
if getf(opts,'throwOnError',false) && ~report.passed
    bad=report.checks(~strcmp(report.checks.Status,'pass'),:);
    error('paperProtocolPreflight:failed','Paper preflight failed (%s): %s',report.dataStatus,strjoin(bad.CheckId,', '));
end

    function add(id,scope,status,observed,expected,msg,path)
        rows(end+1,:)={id,scope,'error',status,show(observed),show(expected),msg,path};
    end

    function checkPrepared()
        e=p.weather.era5;
        csv=getf(p.weather,'csvFile','');
        prov=getf(p.weather,'provenanceFile',fullfile(e.dataDir,'provenance.mat'));
        fit=fullfile(e.dataDir,'fit_report.mat');
        present=isfile(csv) && isfile(fit);
        st='missing'; if present, st=testStatus(strcmpi(p.weather.source,'csv')); end
        add('data.preparedFiles','data',st,{csv,fit},'CSV weather and fit_report.mat', ...
            'Missing prepared data is never replaced with synthetic data or a download.',e.dataDir);
        if ~isfile(prov)
            add('data.provenance','data','missing',prov,'provenance.mat','The source chain record is required.',prov);
            return;
        end
        try
            L=load(prov,'manifest'); m=L.manifest;
            req={'schemaVersion','generator','provider','model','request','processing','types','modelYears','tailYear', ...
                'fitYears','calibrationYear','csv','fit','raw','processors','externalLoad'};
            schema=all(isfield(m,req)) && m.schemaVersion==1 && strcmp(m.generator,'prepareRealData');
        catch err
            schema=false; m=struct(); msg=err.message;
        end
        if schema, msg='Local source chain is declared and content-bound.'; end
        if ~schema && ~exist('msg','var'), msg='Unsupported or incomplete provenance schema.'; end
        add('data.provenance','data',testStatus(schema),prov,'schema 1 from prepareRealData',msg,prov);
        if ~schema, return; end
        boundary=isequaln(m.modelYears,e.years(:)') && isequaln(m.tailYear,e.tailYear) && ...
            isequaln(m.calibrationYear,e.windCalYear);
        try
            boundary=boundary && isequaln(m.fitYears,e.years(p.weather.train));
        catch
            boundary=false;
        end
        add('data.fittingBoundary','data',testStatus(boundary),{m.fitYears,m.calibrationYear,m.tailYear}, ...
            'configured fit years; explicitly declared calibration year; unscored tail year', ...
            '2019 calibration is an external structural reference; weather-process fitting uses training years.',prov);
        w=p.weather; w=rmfield(w,intersect(fieldnames(w),{'provenanceFile','csvFile'}));
        identity=isequaln(m.processing,struct('weather',w,'re',p.re,'load',p.load));
        add('data.processingIdentity','data',testStatus(identity),'current prepared parameters','manifest processing parameters', ...
            'Changed scales, weather fit or source settings require regenerated provenance.',prov);
        root=fileparts(fileparts(mfilename('fullpath')));
        processorNames={'prepareRealData.m','fetchERA5OpenMeteo.m','era5ToHourly.m', ...
            'calibrateWindAlpha.m','windCF.m','fitWeatherModel.m','readWeatherCSV.m', ...
            'classifyRegime.m','hourlyProfiles.m','writeWeatherProvenance.m'};
        expectedProcessors=cellfun(@(s) fullfile(root,'data',s),processorNames,'UniformOutput',false);
        processorOK=isequal(sort({m.processors.path}),sort(expectedProcessors));
        add('data.processingSources','data',testStatus(processorOK),{m.processors.path},expectedProcessors, ...
            'The full processing source list must remain content-bound; omission cannot bypass the hash check.',prov);
        types=strcmp(m.provider,'Open-Meteo historical API') && strcmp(m.model,'ERA5') && ...
            strcmp(m.types.rawWeather,'reanalysis') && strcmp(m.types.renewables,'derived_from_ERA5_reanalysis') && ...
            strcmp(m.types.load,'scenario_temperature_reconstruction') && strcmp(m.types.capacity,'declared_scenario');
        add('data.publicationTypes','data',testStatus(types),m.types,'reanalysis / derived RE / scenario load and capacities', ...
            'Load is reconstructed from temperature; an external load file needs its own source record.',prov);
        A=[m.csv m.fit m.processors]; if ~isempty(m.externalLoad), A=[A m.externalLoad]; end
        hashes=strcmp(m.csv.path,csv) && strcmp(m.fit.path,fit);
        hashMissing=false;
        try
            for j=1:numel(A)
                if ~isfile(A(j).path), hashMissing=true; hashes=false;
                else, hashes=hashes && strcmp(A(j).sha256,fileSHA256(A(j).path)); end
            end
            for j=1:numel(m.raw)
                if ~isfile(m.raw(j).path), hashMissing=true; hashes=false;
                else, hashes=hashes && strcmp(m.raw(j).sha256,fileSHA256(m.raw(j).path)); end
            end
        catch, hashes=false;
        end
        hs=testStatus(hashes); if hashMissing, hs='missing'; end
        add('data.fileHashes','data',hs,'CSV, fit, raw cache and processing sources','unchanged SHA-256 hashes', ...
            'An unchanged filename is insufficient after a content change.',prov);
        [ok,detail]=verifyRaw(m,e);
        add('data.rawIdentity','data',testStatus(ok),detail,'all configured site-years, exact request identities and unique hourly clocks', ...
            'Legacy caches carry no retrieval time or missing-data mask.',prov);
        if ~present, return; end
        try
            F=load(fit,'rep'); fitOK=isequaln(F.rep.fit.train,p.weather.train(:)') && ...
                isequaln(F.rep.years,[e.years(:)' e.tailYear]);
        catch, fitOK=false;
        end
        add('data.fitReport','data',testStatus(fitOK),'fit_report.rep','same train indices and input years', ...
            'The fit report and provenance must agree about preprocessing inputs.',fit);
        try
            T=readtable(csv);
            csvOK=all(ismember({'year','day','EW','ES','EL'},T.Properties.VariableNames));
            if csvOK
                T=sortrows(T,{'year','day'});
                years=[e.years(:)' e.tailYear];
                csvOK=isequal(T.year,repelem(years(:),365)) && isequal(T.day,repmat((1:365)',numel(years),1));
                for f={'EW','ES','EL'}
                    v=T.(f{1}); csvOK=csvOK && isnumeric(v) && all(isfinite(v)) && all(v>=0);
                end
            end
        catch, csvOK=false;
        end
        add('data.csvCalendarValues','data',testStatus(csvOK),'daily calendar and energies','unique day 1:365 per model/tail year; finite nonnegative MWh', ...
            'Leap days are removed before assigning the 365-day model calendar.',csv);
        if ~csvOK, return; end
        try
            expectedW=readWeatherCSV(csv,p);
            actual=W; if isempty(actual), actual=expectedW; end
            ok=numel(actual)==numel(e.years);
            fn={'reg','eW','eS','eL','doy','EW','ES','EL','carbon','h2','N','calendarYear','sourceYearIndex'};
            for j=1:numel(expectedW)
                for k=1:numel(fn)
                    ok=ok && isfield(actual,fn{k}) && isequaln(actual(j).(fn{k}),expectedW(j).(fn{k}));
                end
            end
        catch, ok=false;
        end
        add('data.weatherMatchesCSV','data',testStatus(ok),'W and declared CSV','identical observed paths and calendar provenance', ...
            'Supplied weather cannot silently differ from the content-bound input.',csv);
    end
end

function [ok,detail]=verifyRaw(m,e)
ok=true; detail='';
try
    years=[e.years(:)' e.tailYear]; expected={};
    groups={e.reSites}; vars={e.vars};
    if isempty(e.loadFile), groups{end+1}=e.loadSites; vars{end+1}={'temperature_2m'}; end
    for g=1:numel(groups)
        sites=groups{g};
        for s=1:numel(sites)
            for y=years
                site=sites(s); id=sprintf('%s_%d',site.name,y); expected{end+1}=id; %#ok<AGROW>
                ii=find(strcmp({m.raw.id},id));
                if numel(ii)~=1, ok=false; continue; end
                a=m.raw(ii);
                want=struct('schema',1,'lat',site.lat,'lon',site.lon,'year',y,'model',char(e.model), ...
                    'timezone',char(e.timezone),'url',char(e.url),'windSpeedUnit','ms');
                ok=ok && isequaln(a.request,want) && isequal(a.variables,vars{g}) && ...
                    strcmp(a.path,fullfile(e.dataDir,'raw',[id '.mat']));
                L=load(a.path,'T','cacheMeta');
                t=(datetime(y,1,1):hours(1):datetime(y,12,31,23,0,0))';
                ok=ok && isequaln(L.cacheMeta,want) && isequal(L.T.time(:),t) && ...
                    all(ismember(vars{g},L.T.Properties.VariableNames));
                for k=1:numel(vars{g})
                    v=L.T.(vars{g}{k}); ok=ok && isnumeric(v) && all(isfinite(v(:)));
                end
            end
        end
    end
    ok=ok && numel(m.raw)==numel(expected) && numel(unique({m.raw.id}))==numel(expected);
    detail=sprintf('%d configured site-year cache records',numel(expected));
catch err
    ok=false; detail=err.message;
end
end

function T=plannedBudget(p)
nC2=p.exp.cGridN;
if isfield(p.exp,'cGridAbs') && ~isempty(p.exp.cGridAbs)
    nC2=numel(unique(p.exp.cGridAbs))+3;   % 绝对网格并入 M_0、M_crit(ε)、M_crit 三个理论锚点（名义质量已在网格中）
end
ny=numel(p.weather.test); ns=numel(p.exp.seeds); na=numel(p.exp.elementSeeds);
n3=numel(p.exp.e3MethodSeeds.M3); s3=numel(p.exp.e3MethodScenarios.M3);
models=3*ns+3*na; steps=p.ctdf.stepsPerStage*numel(p.ctdf.gammaStages);
subM=fieldnames(p.exp.e3MethodSeeds);
e3=ny*numel(setdiff(p.exp.e3Methods,subM))*ns*4;
for q=1:numel(subM)
    if ~any(strcmp(p.exp.e3Methods,subM{q})), continue; end
    sq=4;
    if isfield(p.exp.e3MethodScenarios,subM{q}), sq=numel(p.exp.e3MethodScenarios.(subM{q})); end
    e3=e3+ny*numel(p.exp.e3MethodSeeds.(subM{q}))*sq;
end
e2x=0;
if isfield(p.exp,'e2Extra') && ~isempty(p.exp.e2Extra)
    for q=1:numel(p.exp.e2Extra), e2x=e2x+numel(p.exp.e2Extra(q).c)*ny*ns; end
end
variant=1+2*numel(p.exp.sens)+p.exp.heatN^2;
names={'trained_models';'optimizer_steps';'training_transitions';'validation_transitions'; ...
    'E1_episodes';'E2_episodes';'E2_extra_episodes';'E3_episodes';'M3_closed_loop_episodes';'E4_state_method_seed_gamma'; ...
    'E5_episodes';'E6_variants';'E6_episodes';'E7_timing_records';'GT_independent_continuations_per_state'; ...
    'GT_max_environment_days';'central_candidate_count_requested';'local_candidate_evaluations_per_sweep'; ...
    'M3_closed_loop_truncation_mass';'GT_max_truncation_mass'};
count=[models;models*steps;p.data.nTransitions;p.data.nTransitions*p.data.valFrac; ...
    ny*ns;numel(p.exp.e2Methods)*nC2*ny*ns;e2x;e3;ny*n3*s3; ...
    3*ns*numel(p.ctdf.gammaStages)*p.exp.gtStates;5*na*ny*numel(p.exp.e5Scenarios); ...
    variant;variant*ny*ns;numel(p.exp.scaleList)*3*p.exp.timingReps;p.exp.gtR; ...
    (p.exp.gtStates+p.exp.gtValStates)*p.exp.gtR*p.exp.gtTcap;4+p.ctdf.nRandCand; ...
    (numel(p.plant.pmax)+numel(p.station.pRedMax)+1)*(4+p.policy.nLhs); ...
    max(p.ctdf.gammaStages)^p.exp.stepwiseTcapCtrl;max(p.ctdf.gammaStages)^p.exp.gtTcap];
unit=repmat({'count'},size(names)); unit(end-1:end)={'probability'};
T=table(names,count,unit,repmat({'planned_not_completed'},numel(names),1), ...
    'VariableNames',{'Component','Count','Unit','Status'});
end

function value=at(s,path)
value=s;
for f=strsplit(path,'.')
    if ~isstruct(value) || ~isfield(value,f{1}), value=[]; return; end
    value=value.(f{1});
end
end
function v=getf(s,f,d)
if isfield(s,f) && ~isempty(s.(f)), v=s.(f); else, v=d; end
end
function s=testStatus(ok)
if ok, s='pass'; else, s='fail'; end
end
function s=show(v)
if ischar(v), s=v; else
    try, s=jsonencode(v); catch, s=class(v); end
end
end
