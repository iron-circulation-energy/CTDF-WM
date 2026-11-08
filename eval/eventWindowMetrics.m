function out = eventWindowMetrics(s, ext, warmup, lag, riskThreshold)
%EVENTWINDOWMETRICS Prespecified injected-event window, separate from annual spells.
% All series include warm-up. Safety slack is start-of-day inventory minus safety.
% Lead time is relative to the first minimum safety slack within the core event;
% an alarm must precede that minimum, within [event start-lag, minimum day].
if nargin < 5, riskThreshold=.5; end
L=numel(s.shed);
out=struct('available',false,'core',[],'followup',[],'warningLeadDays',NaN, ...
    'forecastLeadDays',NaN,'valleyDay',NaN,'riskThreshold',riskThreshold);
out.definition='Prespecified injected core and core+loop follow-up windows; incomplete windows are flagged.';
if ~isfield(ext,'start') || strcmpi(ext.type,'none'), return; end
validateattributes(lag,{'numeric'},{'scalar','integer','nonnegative'});
validateattributes(ext.start,{'numeric'},{'scalar','integer','positive'});
validateattributes(ext.days,{'numeric'},{'scalar','integer','positive'});
out.available=true;
last=ext.start+ext.days-1;
out.core=measure(ext.start,last);
out.followup=measure(ext.start,last+lag);
core=max(warmup+1,ext.start):min(L,last);
if isempty(core), return; end
[~,i]=min(min(s.safetySlack(:,core),[],1));
valley=core(i); out.valleyDay=valley-warmup;
prior=max(warmup+1,ext.start-lag):valley;
hit=find(isfinite(s.risk(prior)) & s.risk(prior)>=riskThreshold,1);
if ~isempty(hit), out.warningLeadDays=valley-prior(hit); end
hit=find(s.forecastMin(prior)<0,1);
if ~isempty(hit), out.forecastLeadDays=valley-prior(hit); end

    function w=measure(first,lastDay)
        ix=max(warmup+1,first):min(L,lastDay);
        w=struct('startDay',first-warmup,'endDay',lastDay-warmup, ...
            'requestedDays',lastDay-first+1,'observedDays',numel(ix), ...
            'complete',first>warmup && lastDay<=L,'shedMWh',NaN,'curMWh',NaN, ...
            'anyShed',NaN,'shedDays',NaN,'ironShortDays',NaN, ...
            'safeAllPlantDays',NaN,'safePlantDays',NaN);
        if isempty(ix), return; end
        w.shedMWh=sum(s.shed(ix)); w.curMWh=sum(s.cur(ix));
        w.anyShed=double(any(s.shed(ix)>1e-6)); w.shedDays=nnz(s.shed(ix)>1e-6);
        w.ironShortDays=nnz(s.ironShortT(ix)>1e-6);
        w.safeAllPlantDays=nnz(all(s.safetySlack(:,ix)>=0,1));
        w.safePlantDays=nnz(s.safetySlack(:,ix)>=0);
    end
end
