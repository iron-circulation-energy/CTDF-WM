function e1 = runE1Retirement(C, ctrlFactory, years, seeds, opts)
%RUNE1RETIREMENT E1 改造与直接退役对比（图 5）。
%   改造情景：以给定控制器（p.exp.e1Method）在测试年份 × 种子的常规工况回合上运行铁—锈闭环系统，
%   统计评估期失负荷（EUE）、运行成本、弃电量与风光可用电量；
%   退役情景：retirementCounterfactual（同一评估期的逐小时风光与负荷，完全预见调度，二分法匹配 EUE）。
%   opts 字段（可选）：spec 附加字段（carbon、h2 覆盖，E6 用）、cache（退役情景 P—EUE 缓存）、type、
%   altType（为真时另以 p.retire.altTypes 中的其余替代方案（默认 4 h 电池与 100 h 长时储能）计算 e1.resAlt
%   与 e1.resAlts，图 F17 用；E6 不使用）、
%   epDir（断点续跑的逐回合缓存目录，见 evalEpisodes；E6 不使用）、
%   foresightDays（替代方案滚动预见天数，缺省 p.retire.foresightDays；Inf 时不计算有限预见版本）、
%   e2（E2 结果；给出时计算可靠性—保留价值曲线 e1.curve）。
%   输出 e1：res（退役反事实结果，含保留资产价值及其容量/电量分解）、retro（改造情景汇总）、episodes。
%   会计期：res.RV 采用共同会计期（最早到期电厂的剩余寿命，较长寿命资产以残值计入，偏保守）；
%   res.RVplant 按各电厂自身剩余寿命分摊同一年化成本差（按装机容量加权），res.RVhorizon 为会计期 5—25 年的取值，
%   二者为会计期的敏感性，不改变 res.RV。

p = C.p;
if nargin < 5
    opts = struct();
end
epDir = '';
if isfield(opts, 'epDir')
    epDir = opts.epDir;
end
extra = struct();
if isfield(opts, 'carbon')
    extra.carbon = opts.carbon;
end
if isfield(opts, 'h2')
    extra.h2 = opts.h2;
end
Tall = {};
wx = {};
logi = 0;      % 改造情景物流运费合计（元）
logiRail = 0;  % 其中铁路部分（元）
opOnly = 0;    % 运行成本中的机组可变、备用与掺氨部分（元，不含物流与惩罚项）
for s = seeds(:)'
    ctrl = ctrlFactory(s);
    specs = makeEvalSpecs(p, years, s, {'normal'}, C.cNominal, extra);
    [Rr, T] = evalEpisodes(C.ctx, C.W, specs, ctrl, [], epDir);
    for q = 1:numel(Rr)
        nd = Rr(q).spec.len - Rr(q).spec.warmup;
        logi = logi + Rr(q).metrics.costParts(2);
        opOnly = opOnly + Rr(q).metrics.costParts(1);
        logiRail = logiRail + nd * sum(Rr(q).lineFlow(:) .* C.ctx.lineCostPerT(:) .* (C.topo.mode(:) == 1));
    end
    Tall{end + 1} = T; %#ok<AGROW>
    for q = 1:numel(specs)
        seg = buildEvalSegment(C.ctx, C.W, specs(q));
        ev = (specs(q).warmup + 1):specs(q).len;
        [RE, D] = hourlyProfiles(seg.EW(ev), seg.ES(ev), seg.EL(ev), seg.doy(ev), p.weather);
        wx{end + 1} = struct('RE', RE, 'D', D, 'carbon', seg.carbon); %#ok<AGROW>
    end
end
E = vertcat(Tall{:});
retro.eueMWh = sum(E.shedMWh);
retro.opCost = sum(E.cost);
retro.curMWh = sum(E.curMWh);
retro.REMWh = sum(E.REMWh);
retro.logisticsCost = logi;
retro.railCost = logiRail;
retro.opOnly = opOnly;
retro.evalDays = height(E) * p.exp.evalDays;
retro.c = C.cNominal;
retro.pF = mean(E.pF);
ro = struct('type', p.retire.type);
if isfield(opts, 'cache') && ~isempty(opts.cache)
    ro.cache = opts.cache;
end
e1.res = retirementCounterfactual(C.ctx, wx, retro, ro);
e1.res.type = p.retire.type;
e1.res = addHorizons(e1.res, p);
if isfield(opts, 'altType') && opts.altType
    ctxA = C.ctx;
    alts = altTypes(p);
    for k = 1:numel(alts)
        ctxA.p.retire.(alts{k}) = altSpec(p, alts{k});
    end
    alts = setdiff(alts, {p.retire.type}, 'stable');
    e1.resAlts = {};
    for k = 1:numel(alts)
        rk = retirementCounterfactual(ctxA, wx, retro, struct('type', alts{k}));
        rk.type = alts{k};
        e1.resAlts{end + 1} = addHorizons(rk, p);
    end
    if ~isempty(e1.resAlts)
        e1.resAlt = e1.resAlts{1};
    end
end
e1.retro = retro;
e1.episodes = E;
if isfield(p.retire, 'acct')
    e1.acct = e1Comprehensive(e1.res, p, C.stats.Phi, retro);   % 全面核算（只改核算，不重跑闭环）
end
% 信息对称：替代方案滚动有限预见（retirementForesight），与完全预见并列报告
fdays = Inf;
if isfield(p.retire, 'foresightDays') && ~isempty(p.retire.foresightDays)
    fdays = p.retire.foresightDays;
end
if isfield(opts, 'foresightDays')
    fdays = opts.foresightDays;
end
if isfinite(fdays)
    rf = retirementForesight(C.ctx, wx, retro, struct('type', p.retire.type, 'foresightDays', fdays, 'Pref', e1.res.P));
    rf.type = p.retire.type;
    e1.resForesight = addHorizons(rf, p);
    if isfield(p.retire, 'acct')
        e1.acctForesight = e1Comprehensive(rf, p, C.stats.Phi, retro);
    end
end
% 可靠性—保留价值曲线：E2 各质量点上同一方法、同一测试年与种子的改造结果，替代方案按各点的 EUE 匹配
if isfield(opts, 'e2') && ~isempty(opts.e2)
    e1.curve = reliabilityCurve(C, wx, opts.e2, p, e1.res.cache);
end
end

function T = reliabilityCurve(C, wx, e2, p, cache)
% 每个质量点 c：改造情景取 E2 中 p.exp.e1Method 的回合（与 E1 相同的测试年 × 种子、常规工况），
% 替代方案按完全预见调度、二分法匹配该点的 EUE（P—EUE 缓存与质量无关，各点共用），给出保留资产价值与全面核算。
E = e2.episodes;
E = E(strcmp(E.method, p.exp.e1Method), :);
loadMWh = 0;
for m = 1:numel(wx)
    loadMWh = loadMWh + sum(wx{m}.D(:));
end
cs = unique(E.c)';
rows = {};
for c = cs
    Ec = E(E.c == c, :);
    rc = struct('eueMWh', sum(Ec.shedMWh), 'opCost', sum(Ec.cost), 'curMWh', sum(Ec.curMWh), 'REMWh', sum(Ec.REMWh), ...
        'evalDays', height(Ec) * p.exp.evalDays, 'c', c, 'pF', mean(Ec.pF));
    if height(Ec) ~= numel(wx)
        warning('runE1Retirement:curve', '质量 %.0f t 的回合数 %d 与 E1 评估期数 %d 不一致，跳过。', c, height(Ec), numel(wx));
        continue;
    end
    r = retirementCounterfactual(C.ctx, wx, rc, struct('type', p.retire.type, 'cache', cache));
    r.type = p.retire.type;
    cache = r.cache;
    rvCore = NaN; rvDesign = NaN; rvAll = NaN;
    if isfield(p.retire, 'acct')
        A = e1Comprehensive(r, p, C.stats.Phi, rc);
        rvCore = A.summary.RV_core;
        rvDesign = A.summary.RV_design2030;
        rvAll = A.summary.RV_all2030;
    end
    rows(end + 1, :) = {c, rc.eueMWh / max(loadMWh, eps), rc.pF, r.P, r.matched, r.RV, rvCore, rvDesign, rvAll}; %#ok<AGROW>
end
T = cell2table(rows, 'VariableNames', {'c', 'eueShare', 'pF', 'Prep', 'matched', 'RV', 'RVcore', 'RVdesign2030', 'RVall2030'});
end

function a = altTypes(p)
a = {'battery', 'ldes100'};
if isfield(p.retire, 'altTypes') && ~isempty(p.retire.altTypes)
    a = p.retire.altTypes;
end
end

function sp = altSpec(p, name)
% 替代方案参数；p.retire 中已有时直接使用，否则取默认值（100 h 金属—空气类长时储能，参数为情景设定）
if isfield(p.retire, name)
    sp = p.retire.(name);
    return;
end
switch name
    case 'ldes100'
        sp = struct('capexP', 1500, 'capexE', 150, 'etaCharge', 0.65, 'etaDischarge', 0.65, 'hours', 100);
    otherwise
        error('runE1Retirement:altType', '未定义的替代方案 %s。', name);
end
end

function res = addHorizons(res, p)
% 会计期敏感性：同一年化成本差按不同会计期折现（年化成本差 ΔA = RV/AF(N_common)）
r = p.retire.discount;
af = @(N) (r == 0) .* N + (r ~= 0) .* (1 - (1 + r) .^ (-N)) ./ max(r, eps);
if ~isfield(res, 'detail') || ~isfinite(res.RV)
    res.RVplant = NaN;
    res.RVhorizon = table();
    return;
end
dA = res.RV / res.detail.annuityFactor;
life = min(p.plant.remainLife(:), p.retire.lifeRep);
w = p.plant.pmax(:) / sum(p.plant.pmax(:));
res.RVplant = dA * sum(w .* af(life));
N = (5:5:25)';
res.RVhorizon = table(N, dA * af(N), 'VariableNames', {'horizonYears', 'RV'});
res.annualDiff = dA;
end
