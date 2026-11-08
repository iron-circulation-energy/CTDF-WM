function cm = criticalMass(stats, Tl, p)
%CRITICALMASS 临界循环质量（临界循环质量、事件风险）及其自助法置信区间。
%   M_LL = Φ̄·T_loop is an average-turnover reference, never a pointwise occupancy guarantee.
%   Optional p.stats.processReserveT declares a fixed, disjoint process reserve M_occ.
%   Without it the numerical scan uses M_LL only as an illustrative reserve (referenceOnly=true).
%   M_0       = M_occ + δ^U·U_max + safety.
%   M_crit(ε) = M_0 + δ^D·ceil(ln ε / ln q); q=1 gives no finite bound.
%   P_F(c)    = min{1, q^⌊(c − M_0)/δ^D⌋}（单次低风光事件断供概率）
%   置信区间由 stats.bootRaw 的每个自助样本代入公式得到（2.5% 与 97.5% 分位数）。

spec = makeBufferSpec(stats,Tl,p);
safe = spec.safetyT;
eps0 = spec.epsRisk;
tailIdentified = spec.tailIdentified;
riskQ = spec.riskQ;
[cm.M_LL, cm.M_crit, cm.M_0, cm.M_eps] = masses(spec);
cm.bufferSpec = spec;
cm.M_occ = spec.M_occ;
cm.referenceOnly = spec.referenceOnly;
cm.designExact = false; % Network timing, prepositioning and recovery still require independent checks.
cm.processReserveSpecified = spec.processReserveSpecified;
cm.reserveSource = spec.reserveSource;
cm.boundKind = spec.boundKind;
cm.scope = spec.scope;
cm.tailIdentified = tailIdentified;
cm.requiredBufferDays = bufferDays(eps0, riskQ, stats.deltaD);
cm.finiteRiskCalibration = isfinite(cm.M_eps);
cm.eps = eps0;
cm.safe = safe;
cm.Tloop = Tl.mean;
cm.PF = @(c) tailBound(c, cm.M_0, stats.deltaD, riskQ);
cm.Meps = @(e) cm.M_0 + stats.deltaD * bufferDays(e, riskQ, stats.deltaD);
cm.slopeTheory = NaN;
if tailIdentified && stats.qhat > 0 && stats.deltaD > 0
    cm.slopeTheory = log(stats.qhat) / stats.deltaD;
end

if isfield(stats, 'bootRaw') && ~isempty(stats.bootRaw)
    T = stats.bootRaw;
    nb = height(T);
    vals = zeros(nb, 4);
    identified = true(nb, 1);
    if ismember('qhatIdentified', T.Properties.VariableNames)
        identified = logical(T.qhatIdentified);
    end
    for b = 1:nb
        sb = struct('Phi',T.Phi(b),'deltaD',T.deltaD(b),'deltaU',T.deltaU(b), ...
            'Dmax',T.Dmax(b),'Umax',T.Umax(b),'qhat',T.qhat(b),'qhatIdentified',identified(b));
        bootSpec = makeBufferSpec(sb,Tl,p);
        [vals(b, 1), vals(b, 2), vals(b, 3), vals(b, 4)] = masses(bootSpec);
    end
    cm.ci.M_LL = quantileLin(vals(:, 1), [0.025, 0.975]);
    cm.ci.M_crit = quantileLin(vals(:, 2), [0.025, 0.975]);
    cm.ci.M_0 = quantileLin(vals(:, 3), [0.025, 0.975]);
    cm.ci.M_eps = quantileLin(vals(:, 4), [0.025, 0.975]);
    cm.riskBootstrapIdentifiedFraction = mean(identified);
    if ~all(identified)
        % Dropping unidentified draws would silently condition the interval on successful estimation.
        cm.ci.M_eps = [NaN, NaN];
    end
end
end

function [ll, mc, m0, me] = masses(spec)
ll = spec.M_LL;
mc = spec.M_crit;
m0 = spec.M_0;
me = m0 + spec.deltaD * bufferDays(spec.epsRisk, spec.riskQ, spec.deltaD);
end

function d = bufferDays(e, q, delta)
validateattributes(e, {'numeric'}, {'finite','>',0,'<',1});
if isnan(q)
    d = nan(size(e));
    return;
end
validateattributes(q, {'numeric'}, {'scalar','finite','>=',0,'<=',1});
if delta == 0
    d = zeros(size(e));
elseif q == 0
    d = ones(size(e)); % D=1 almost surely.
elseif q == 1
    d = inf(size(e)); % No observed exit: do not invent finite tail calibration.
else
    d = ceil(log(e) / log(q));
end
end

function v = tailBound(c, m0, delta, q)
if isnan(q)
    v = nan(size(c));
    return;
end
if delta == 0
    v = double(c < m0);
    return;
end
u = max(c - m0, 0) / delta;
% Account only for floating-point error at exact integer buffer boundaries.
k = floor(u + 8 * eps(max(1, abs(u))));
v = min(1, q .^ k);
end
