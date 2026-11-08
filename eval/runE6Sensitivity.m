function e6 = runE6Sensitivity(p, W, refId, years, seeds, varDir)
%RUNE6SENSITIVITY E6 敏感性分析与空间解耦适用条件。
%   单因素敏感性：p.exp.sens 中各因素取低、高两个水平（往返效率、还原氢耗、运输方式、运输距离、改造成本、
%   碳价、氢价），每个变体重新构造算例与统计量，循环铁总质量按同一设计规则取名义值（M_crit(ε) 或 M_crit），
%   以 M0 参考策略（同一联合策略编号 refId，参数以统计量为单位，随变体自适应）运行改造情景，
%   再做退役反事实，报告保留资产价值与断供概率。
%   二维热图：实际往返效率倍数 × 运价倍数（p.exp.heatN × p.exp.heatN；往返效率倍数的定义见 applyVariant 'roundtrip'）。
%   运输经济性：铁路、水运单位千瓦时运费 c^tr·d·(1 + m_Ox)/(η^st·h_Fe·1000)（元/kWh，含铁锈回运，
%   m_Ox 为锈与铁当量的质量比）随运距 d 的变化，与特高压单位输电成本 u_0 + u_1·d/1000 比较并求盈亏平衡运距。
%   说明：E6 统一使用 M0 运行改造情景（学习模型只对基准物理参数训练，变体下不重新训练）；碳价、氢价也会通过内层调度改变运行结果，须重新仿真。
%   varDir（可选，断点续跑）：每个变体的结果（rv、pf 与退役情景缓存）保存为 varDir 下的 base.mat、
%   sens_<因素名>_<水平序号>.mat（往返效率另加 _rte）、heatRTE_<a>_<b>.mat（热图单元下标），已存在的变体直接读取，不重新构造算例与运行。
%   各变体的控制器同名（M0），故 E6 不使用逐回合缓存（evalEpisodes 的 epDir）。
%   输出 e6：base、tornado（表）、heat（网格与矩阵）、breakeven。

if nargin < 6
    varDir = '';
end
if ~isempty(varDir) && ~exist(varDir, 'dir')
    mkdir(varDir);
end
[rvB, pfB, cacheB] = cachedVariant(varDir, 'base', p, W, struct(), refId, years, seeds, struct());
e6.base = struct('RV', rvB, 'pF', pfB);
rows = cell(0, 8);
for k = 1:numel(p.exp.sens)
    f = p.exp.sens(k);
    lv = {f.lo, f.hi};
    rv = zeros(1, 2);
    pf = zeros(1, 2);
    for h = 1:2
        [pv, over] = applyVariant(p, f.name, f.kind, lv{h});
        cache = struct();
        if any(strcmpi(f.name, {'roundtrip', 'kappa', 'mode', 'distance', 'retrofit', 'h2'}))
            cache = cacheB;                         % 退役情景只依赖气象、负荷、备用成本与替代容量参数
        end
        tag = sprintf('sens_%s_%d', regexprep(f.name, '[^A-Za-z0-9]', '_'), h);
        if strcmpi(f.name, 'roundtrip')
            tag = [tag, '_rte'];                    % 往返效率按实际倍率定义（旧版两端同乘的缓存不再沿用）
        end
        [rv(h), pf(h)] = cachedVariant(varDir, tag, pv, W, over, refId, years, seeds, cache);
    end
    rows(end + 1, :) = {f.name, f.label, num2str(f.lo), num2str(f.hi), rv(1), rv(2), pf(1), pf(2)}; %#ok<AGROW>
end
e6.tornado = cell2table(rows, 'VariableNames', {'Factor', 'Label', 'Low', 'High', 'RVlow', 'RVhigh', 'pFlow', 'pFhigh'});
% 热图
nH = p.exp.heatN;
gR = linspace(p.exp.heatRoundtrip(1), p.exp.heatRoundtrip(2), nH);
gT = linspace(p.exp.heatTransport(1), p.exp.heatTransport(2), nH);
RV = zeros(nH);
PF = zeros(nH);
for a = 1:nH
    for b = 1:nH
        pv = applyVariant(p, 'roundtrip', 'scale', gR(a));
        pv = applyVariant(pv, 'transport', 'scale', gT(b));
        [RV(a, b), PF(a, b)] = cachedVariant(varDir, sprintf('heatRTE_%d_%d', a, b), pv, W, struct(), refId, years, ...
            seeds, cacheB);
    end
end
e6.heat = struct('roundtrip', gR, 'transport', gT, 'RV', RV, 'pF', PF);
% 运输经济性与盈亏平衡运距
d = linspace(0, p.exp.breakevenMaxKm, 200);
eta = mean(p.plant.etaSt);
mOx = p.iron.oxMassRatio;
perKwh = @(cost) cost * d * (1 + mOx) / (eta * p.iron.hFe * 1000);
uhv = p.transport.uhvCostPerKwh + p.transport.uhvCostPer1000km * d / 1000;
be = @(cost) breakevenKm(p.transport.uhvCostPerKwh, cost * (1 + mOx) / (eta * p.iron.hFe * 1000), ...
    p.transport.uhvCostPer1000km / 1000);
e6.breakeven = struct('d', d, 'rail', perKwh(p.transport.railCost), 'water', perKwh(p.transport.waterCost), ...
    'uhv', uhv, 'dRail', be(p.transport.railCost), 'dWater', be(p.transport.waterCost), 'eta', eta, 'mOx', mOx);
% 季节性可靠供电口径：特高压线路只在亏缺时段输电，线路投资按实际利用小时回收（输电价 × 设计利用小时 / 实际利用小时）；
% 铁锈回程利用回空车辆（运价 × backhaulFrac）。另给出盈亏平衡运距随线路利用小时的变化。
e6c = struct('uhvRefHours', 5000, 'uhvHours', 2000, 'backhaulFrac', 1);
if isfield(p, 'retire') && isfield(p.retire, 'e6')
    fn = fieldnames(p.retire.e6);
    for k = 1:numel(fn)
        e6c.(fn{k}) = p.retire.e6.(fn{k});
    end
end
slope = @(cost, back) cost * (1 + back * mOx) / (eta * p.iron.hFe * 1000);   % 元/kWh/km
uFirm = @(h) p.transport.uhvCostPerKwh * e6c.uhvRefHours / h;
hGrid = [1000 1500 2000 3000 4000 5000];
e6.breakeven.firm = struct('uhvRefHours', e6c.uhvRefHours, 'uhvHours', e6c.uhvHours, 'backhaulFrac', e6c.backhaulFrac, ...
    'uhv', uFirm(e6c.uhvHours), ...
    'dRail', breakevenKm(uFirm(e6c.uhvHours), slope(p.transport.railCost, e6c.backhaulFrac), 0), ...
    'dWater', breakevenKm(uFirm(e6c.uhvHours), slope(p.transport.waterCost, 1), 0), ...
    'hours', hGrid, ...
    'dRailH', arrayfun(@(h) breakevenKm(uFirm(h), slope(p.transport.railCost, e6c.backhaulFrac), 0), hGrid), ...
    'dWaterH', arrayfun(@(h) breakevenKm(uFirm(h), slope(p.transport.waterCost, 1), 0), hGrid));
end

function [rv, pf, cache] = cachedVariant(varDir, tag, pv, W, over, refId, years, seeds, cache)
% 单个变体（断点续跑）：varDir 非空且 <tag>.mat 已存在时直接读取 rv、pf 与退役情景缓存；否则构造算例、
% 运行改造与退役情景并保存（先写临时文件再改名，中断时不会留下损坏的结果文件）
f = '';
if ~isempty(varDir)
    f = fullfile(varDir, [tag, '.mat']);
    if isfile(f)
        try
            L = load(f, 'rv', 'pf', 'cache');
            rv = L.rv;
            pf = L.pf;
            cache = L.cache;
            return;
        catch
            % 文件损坏：重新运行并覆盖
        end
    end
end
C = buildCase(pv, W);
[rv, pf, cache] = evalVariant(C, over, refId, years, seeds, cache);
if ~isempty(f)
    tmp = fullfile(varDir, [tag, '.tmp.mat']);
    save(tmp, 'rv', 'pf', 'cache');
    movefile(tmp, f, 'f');
end
end

function [rv, pf, cache] = evalVariant(C, over, refId, years, seeds, cache)
lib = policyLibrary(C.p, C.topo, C.stats, C.p.seed);
w0 = jointPolicy(lib, refId);
fac = @(s) makeController('fixed', 'M0', w0);
opts = over;
opts.foresightDays = Inf;                    % 敏感性只用完全预见口径（与 E6 原设定一致，避免逐变体重算滚动调度）
if ~isempty(fieldnames(cache))
    opts.cache = cache;
end
e1 = runE1Retirement(C, fac, years, seeds, opts);
rv = e1.res.RV;
pf = e1.retro.pF;
cache = e1.res.cache;
end

function d = breakevenKm(u0, aIron, u1)
% 铁运输单位电量运费 aIron·d 与特高压 u0 + u1·d 的盈亏平衡运距 d* = u0/(aIron − u1)。
% 斜率差不为正时两条直线在正运距上不相交（铁运输始终更便宜，或特高压固定成本为零时处处不劣），返回 Inf。
ds = aIron - u1;
if ds > 0 && u0 >= 0
    d = u0 / ds;
elseif u0 <= 0 && ds >= 0
    d = 0;
else
    d = Inf;
end
end
