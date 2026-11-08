function spec = makeBufferSpec(stats, Tl, p)
%MAKEBUFFERSPEC 事件缓冲的互不重叠配置：工序预留、安全库存、放能端自由铁与充能端自由锈。
% 声明工序预留时，该部分不用于事件缓冲；未声明时以 Phi*Tloop 作为平均周转参照。

names = {'Phi','deltaD','deltaU','Dmax','Umax'};
for k = 1:numel(names)
    validateattributes(stats.(names{k}),{'numeric'},{'scalar','real','finite','nonnegative'});
end
validateattributes([stats.Dmax,stats.Umax],{'numeric'},{'integer'});
validateattributes(Tl.mean,{'numeric'},{'scalar','real','finite','nonnegative'});
validateattributes(stats.qhat,{'numeric'},{'scalar','real','finite','>=',0,'<=',1});
validateattributes(p.stats.epsRisk,{'numeric'},{'scalar','real','finite','>',0,'<',1});
validateattributes(p.plant.safetyFe,{'numeric'},{'real','finite','nonnegative'});
validateattributes(p.station.safetyOx,{'numeric'},{'real','finite','nonnegative'});

spec.version = 1;
spec.model = 'fixed-reserve prepared dual buffer';
spec.M_LL = stats.Phi * Tl.mean;
spec.processReserveSpecified = isfield(p.stats,'processReserveT') && ~isempty(p.stats.processReserveT);
spec.M_occ = spec.M_LL;
spec.reserveSource = 'average_turnover_reference';
if spec.processReserveSpecified
    validateattributes(p.stats.processReserveT,{'numeric'},{'scalar','real','finite','nonnegative'});
    spec.M_occ = p.stats.processReserveT;
    spec.reserveSource = 'declared_fixed_reserve';
end
spec.safeFeP = p.plant.safetyFe(:);
spec.safeOxR = p.station.safetyOx(:);
spec.safetyT = sum(spec.safeFeP) + sum(spec.safeOxR);
spec.deltaD = stats.deltaD;
spec.deltaU = stats.deltaU;
spec.Dmax = stats.Dmax;
spec.Umax = stats.Umax;
spec.freeFeTarget = spec.deltaD * spec.Dmax;
spec.freeOxTarget = spec.deltaU * spec.Umax;
spec.baseMass = spec.M_occ + spec.safetyT;
spec.M_0 = spec.baseMass + spec.freeOxTarget;
spec.M_crit = spec.M_0 + spec.freeFeTarget;
spec.Phi = stats.Phi;
spec.Tloop = Tl.mean;
spec.qhat = stats.qhat;
spec.tailIdentified = ~isfield(stats,'qhatIdentified') || stats.qhatIdentified;
spec.riskQ = spec.qhat;
if ~spec.tailIdentified, spec.riskQ = NaN; end
spec.epsRisk = p.stats.epsRisk;
if isfield(p.stats,'deltaQuantile') && isfield(p.stats,'dQuantile')
    if p.stats.deltaQuantile < 1 || p.stats.dQuantile < 1
        spec.boundKind = 'empirical_quantile';
    else
        spec.boundKind = 'empirical_sample_maximum';
    end
else
    spec.boundKind = 'empirical_unspecified';
end
spec.referenceOnly = ~spec.processReserveSpecified;
spec.designExact = false;
spec.networkExact = false;
spec.recoveryRateT = 0; % 事件间恢复能力不由平均通量推断
spec.scope = ['Prepared-buffer construction: reserve and safety stocks are disjoint from event buffers; ', ...
    'timed network feasibility is evaluated with the full material model.'];
end
