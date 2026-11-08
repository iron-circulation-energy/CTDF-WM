function out = checkEventRisk(ctx, stats, cm, nEvents, seed)
%CHECKEVENTRISK 固定工序预留下的孤立事件风险检查（使用 cm.bufferSpec）。
%   在简化准备缓冲模型（preparedBufferSim，split = 'rustFirst'，即先满足锈目标、其余全部作为自由铁）中，对每个循环铁
%   质量 c 求断供阈值 D*(c)：持续 D 天的低风光事件导致缺铁断供的最小 D（事件开始时系统处于目标状态）；
%   再按几何分布 P(D > d) = q^d 抽取 nEvents 次低风光事件，统计经验断供概率并给出 Wilson 95% 置信区间，
%   与 P_F(c) = min{1, q^⌊(c − M_0)/δ^D⌋} 比较；对 log P_F 与 c 做线性回归，比较拟合斜率与
%   理论斜率 ln q / δ^D。
%   输出 out：table（c、(c − M_0)/δ^D、D* 缓冲、D* 理论、经验概率及区间、理论概率）、slopeFit、slopeTheory。
%   事件持续时间按几何分布抽样，用于检查事件风险公式的实现。

q = stats.qhat;
dD = stats.deltaD;
if isfield(stats,'qhatIdentified') && ~stats.qhatIdentified
    error('checkEventRisk:unidentifiedTail', ...
        'The low-renewable continuation probability is not identified by observed transitions.');
end
validateattributes(q,{'numeric'},{'scalar','real','finite','>=',0,'<=',1});
if q == 1
    error('checkEventRisk:nondecayingTail', ...
        'A nondecaying tail has no finite event-duration grid for this verification.');
end
if ~isscalar(dD) || ~isfinite(dD) || dD <= 0
    error('checkEventRisk:noDepletion', ...
        'The geometric depletion threshold requires a strictly positive daily iron deficit.');
end
validateattributes(nEvents,{'numeric'},{'scalar','real','finite','positive','integer'});
spec = checkedBufferSpec(ctx,stats,cm);
M0 = spec.M_0;
if q == 0
    kmax = 3;
else
    kmax = max(3, ceil(log(1e-3) / log(q)));
end
units = (0.5:1:kmax + 0.5)';
cGrid = M0 + dD * units;
rs = RandStream('twister', 'Seed', seed);
U = rand(rs, nEvents, 1);
if q == 0
    Dsamp = ones(nEvents,1);                         % every observed event exits after day one
else
    Dsamp = 1 + floor(log(max(U, realmin)) / log(q));  % P(D = d) = (1 − q)·q^(d−1)
end
nc = numel(cGrid);
DstarF = nan(nc, 1);
DstarT = floor((cGrid - M0) / dD) + 1;
Dlim = max([max(Dsamp)+2;DstarT]);
Pemp = zeros(nc, 1);
ciLo = zeros(nc, 1);
ciHi = zeros(nc, 1);
Pth = min(1, q .^ floor(max(cGrid - M0, 0) / dD));
% 'rustFirst' 先满足锈目标 δ^U·U_max（已计入 M_0），其余 c − M_0 全部为电厂自由铁，
% 故理论断供阈值 D* = ⌊(c − M_0)/δ^D⌋ + 1，单次事件断供概率 P(D ≥ D*) = q^(D*−1)。
for m = 1:nc
    r = preparedBufferSim(cGrid(m), spec, repmat('D',1,Dlim), struct('split','rustFirst'));
    if r.violFe>0
        DstarF(m) = r.first(1);
    end
    if isnan(DstarF(m))
        Pemp(m) = NaN; ciLo(m) = NaN; ciHi(m) = NaN;
    else
        k = sum(Dsamp >= DstarF(m));
        Pemp(m) = k / nEvents;
        [ciLo(m), ciHi(m)] = wilsonCI(k, nEvents);
    end
end
T = table(cGrid, units, DstarF, DstarT, Pemp, ciLo, ciHi, Pth, 'VariableNames', ...
    {'c', 'ExcessUnits', 'DstarBuffer', 'DstarTheory', 'Pemp', 'CILo', 'CIHi', 'Ptheory'});
sel = Pemp > 0;
if nnz(sel) >= 2
    A = [ones(nnz(sel), 1), cGrid(sel)];
    coef = A \ log(Pemp(sel));
    out.slopeFit = coef(2);
else
    out.slopeFit = NaN;
end
out.slopeTheory = log(q) / dD;
out.table = T;
out.thresholdMatch = mean(DstarF == DstarT);
out.M0buffer = spec.M_occ+spec.safetyT+spec.freeOxTarget;
out.M0formula = M0;
out.bufferSpec = spec;
out.referenceOnly = spec.referenceOnly;
out.designExact = false;
out.boundKind = spec.boundKind;
out.scope = ['Synthetic geometric isolated-event check in the fixed-reserve prepared-buffer model. ', ...
    'A constant draw at its stated bound is constructed, not inferred from weather. ',spec.scope];
end

function [lo, hi] = wilsonCI(k, n)
z = 1.96;
ph = k / n;
den = 1 + z ^ 2 / n;
cen = (ph + z ^ 2 / (2 * n)) / den;
hw = z * sqrt(ph * (1 - ph) / n + z ^ 2 / (4 * n ^ 2)) / den;
lo = max(cen - hw, 0);
hi = min(cen + hw, 1);
end
