function [T, metadata] = summarizePredictionAccuracy(raw)
%SUMMARIZEPREDICTIONACCURACY Average seeds within states, states within weather years.
% Intervals use weather-year means; duplicating training seeds cannot create
% additional weather observations. Unknown years or one year give no weather CI.
% Distance definitions remain separate groups. The first 11 columns retain E4's
% legacy schema; appended fields state the metric and effective coverage.
required={'Method','gamma','Horizon','state','year','seed','W1','ValueErr','ConsErr','NegFrac','distanceMethod'};
if ~istable(raw) || ~all(ismember(required,raw.Properties.VariableNames))
    error('summarizePredictionAccuracy:schema','Raw prediction records are missing required columns.');
end
rows=cell(0,11);
extra=struct('distanceMethod',{},'nYears',{},'nStates',{},'nSeeds',{},'yearKnown',{},'ciUnit',{}, ...
    'modelSamplesMin',{},'modelSamplesMax',{},'referenceSamplesMin',{},'referenceSamplesMax',{}, ...
    'referenceTail',{},'modelTail',{},'tailMismatch',{},'independentReferencePaths',{}, ...
    'RiskErr',{},'RElo',{},'REhi',{});
if ~isempty(raw)
    [G,methods,gammas,distances]=findgroups(string(raw.Method),raw.gamma,string(raw.distanceMethod));
    for k=1:numel(methods)
        R=raw(G==k,:);
        known=all(isfinite(R.year));
        [stateGroup,~,stateYears]=findgroups(R.state,R.year);
        if ~known
            % The source-year cluster is unknown; retain a descriptive mean only.
            stateGroup=findgroups(R.state); stateYears=nan(max(stateGroup),1);
        end
        hasRisk=ismember('RiskErr',R.Properties.VariableNames);
        stateMetrics=nan(max(stateGroup),4);
        for j=1:max(stateGroup)
            sel=stateGroup==j;
            rk=NaN;
            if hasRisk, rk=mean(R.RiskErr(sel),'omitnan'); end
            stateMetrics(j,:)=[mean(R.W1(sel),'omitnan'),mean(R.ValueErr(sel),'omitnan'),mean(R.NegFrac(sel),'omitnan'),rk];
        end
        ny=numel(unique(R.year(isfinite(R.year))));
        if known
            ys=unique(stateYears);
            metrics=nan(numel(ys),4);
            for j=1:numel(ys), metrics(j,:)=mean(stateMetrics(stateYears==ys(j),:),1,'omitnan'); end
        else
            metrics=stateMetrics;
        end
        mu=mean(metrics,1,'omitnan'); lo=[NaN,NaN]; hi=lo;
        ciUnit="unavailable_missing_year";
        if known, ciUnit="unavailable_single_weather_year"; end
        if known && ny>=2
            [~,~,lo(1),hi(1)]=statsUtils('meanCI',metrics(:,1));
            [~,~,lo(2),hi(2)]=statsUtils('meanCI',metrics(:,2));
            lo=max(lo,0);
            ciUnit="weather_year";
        end
        rows(end+1,:)={char(methods(k)),gammas(k),1/(1-gammas(k)),mu(1),lo(1),hi(1), ...
            mu(2),lo(2),hi(2),max(R.ConsErr,[],'omitnan'),mu(3)}; %#ok<AGROW>
        z.distanceMethod=distances(k); z.nYears=ny; z.nStates=size(stateMetrics,1);
        z.nSeeds=numel(unique(R.seed)); z.yearKnown=known; z.ciUnit=ciUnit;
        z.modelSamplesMin=reduceField(R,'modelSamples',@min);
        z.modelSamplesMax=reduceField(R,'modelSamples',@max);
        z.referenceSamplesMin=reduceField(R,'referenceSamples',@min);
        z.referenceSamplesMax=reduceField(R,'referenceSamples',@max);
        z.referenceTail=reduceField(R,'referenceTail',@max);
        z.modelTail=reduceField(R,'modelTail',@max);
        z.tailMismatch=reduceField(R,'tailMismatch',@max);
        z.independentReferencePaths=reduceField(R,'independentReferencePaths',@min);
        z.RiskErr=mu(4); z.RElo=NaN; z.REhi=NaN;
        if known && ny>=2 && all(isfinite(metrics(:,4)))
            [~,~,z.RElo,z.REhi]=statsUtils('meanCI',metrics(:,4)); z.RElo=max(z.RElo,0);
        end
        extra(end+1)=z; %#ok<AGROW>
    end
end
T=cell2table(rows,'VariableNames',{'Method','gamma','Horizon','W1','W1lo','W1hi', ...
    'ValueErr','VElo','VEhi','ConsErr','NegFrac'});
if ~isempty(extra), T=[T,struct2table(extra)]; end
metadata=struct('ciUnit','weather year','meanOrder','training seeds within state, states within year, equal-weight years', ...
    'missingYearRule','No weather-year CI when any source year is unknown or fewer than two years are present', ...
    'distanceDefinition','exact = empirical Euclidean W1; scaled_sliced = sqrt(D) times mean projected 1D W1', ...
    'referenceUncertainty','Weather-year intervals and reference-path Monte Carlo error are reported separately', ...
    'yearDefinition','gt.year source-year identifier, which may be a dataset year index', ...
    'metricSpace','Model coordinates; comparisons require a shared normalization', ...
    'nRawRows',height(raw));
end

function v=reduceField(T,name,fun)
v=NaN;
if ismember(name,T.Properties.VariableNames)
    x=T.(name);
    if all(isfinite(x)), v=fun(x); end
end
end
