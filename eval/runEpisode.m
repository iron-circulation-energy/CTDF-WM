function out = runEpisode(ctx, W, spec, ctrl)
%RUNEPISODE 在环境中按控制器运行一个评估回合，并计算的统一指标。
%   每日顺序：观测 → 决策前裕度与荷电状态→ 控制器决策（计时）→ env.step。
%   指标只统计 warmup 之后的 evalDays 天：
%     pF          断供概率：当日到货后，存在电厂可用铁不足以承担其按容量分摊的必要放电量的天数比例
%     forecastExposure  H-day forecast margin below zero; distinct from realised supply
%     pShed       发生失负荷的天数比例
%     shedMWh     失负荷电量（MWh）
%     curRate     弃电率 = 弃电量 / 风光可用电量
%     rustBlockMWh 锈阻塞弃电量（MWh）
%     cost        总成本（元， 的各分量之和），costParts（7×1，元）
%     decTime     单次决策时间均值（s）
%     localFe     plant-days of current-day iron shortfall;
%                 localForecastFe/localOx count forecast-margin violations separately.
%     events      低风光事件（连续 reg = 2）个数；eventShed、eventF：事件期间或其后 ⌈T_loop⌉ 天内发生失负荷 /
%                 当日铁短缺的事件比例；预测裕度暴露另存。
%     loadMWh     评估期负荷电量（MWh），maxConsRel 守恒相对误差，trunc 动作截断量合计
%   spec.keepTrace 为真时输出逐日轨迹 trace（图 F06、F09 用）。
%   另始终输出（评估期，single 精度，供作图）：
%     out.daily     minMuFe（min_i μ^Fe_i，t）、soc、cost（元）、RE、load、shed、cur、nh3（MWh）、
%                   shipFe（还原站发出的铁粉，t）、shipOx（运回还原站的铁锈，t）、fc7（未来 1—7 日必需燃铁电量预测之和，MWh）、reg；
%     out.lineFlow  各线路评估期日均发运量（nE×1，t/d）。

p = ctx.p;
topo = ctx.topo;
[seg, cap, ext] = buildEvalSegment(ctx, W, spec);
env = IronRustEnv(ctx);
env.reset(spec.seed, spec.c, spec.initSOC, struct('seg', seg, 'capSched', cap, 'initMode', 'deterministic'));
L = spec.len;
nP = topo.nP;
nR = topo.nR;
st.rs = RandStream('twister', 'Seed', 1e4 * spec.seed + 17 * spec.year + 3);
st.prevId = [];
muFe = zeros(nP, L);
muOx = zeros(nR, L);
soc = zeros(1, L);
shed = zeros(1, L);
cur = zeros(1, L);
RE = zeros(1, L);
rb = zeros(1, L);
rbJ = zeros(nR, L);
cost = zeros(1, L);
Z = zeros(ctx.L.nCost, L);
shortFe = zeros(nP, L);
safetyFe = zeros(nP, L);
shortFeMWh = zeros(nP, L);
decT = zeros(1, L);
risk = nan(1, L);
Qv = nan(1, L);
ids = zeros(nP + nR + 1, L);
IFe = zeros(nP, L);
SOx = zeros(nR, L);
bAct = zeros(nP, L);
rhoAct = zeros(nR, L);
mpcT = nan(1, L);
fc7 = zeros(1, L);
shipFe = zeros(1, L);
shipOx = zeros(1, L);
nh3 = zeros(1, L);
flowSum = zeros(topo.nE, 1);
eFeOut = (topo.mat == 1) & ismember(topo.from, topo.R);     % 还原站发出的铁粉线路
eOxIn = (topo.mat == 2) & ismember(topo.to, topo.R);        % 运回还原站的铁锈线路
truncSum = 0;
maxCons = 0;
for t = 1:L
    obs = env.getObs();
    [mf, mo] = computeMargins(obs.s, ctx);
    muFe(:, t) = mf;
    muOx(:, t) = mo;
    soc(t) = env.soc();
    IFe(:, t) = obs.x(ctx.idx.IFe);
    SOx(:, t) = obs.x(ctx.idx.SOx);
    fc7(t) = sum(obs.fc.must(2:min(8, numel(obs.fc.must))));
    t0 = tic;
    [a, st, dg] = controllerAct(ctrl, obs, ctx, st);
    decT(t) = toc(t0);
    info = env.step(a);
    ir = realizedIronShortfall(obs, info, ctx);
    shortFe(:, t) = ir.shortfallT;
    safetyFe(:, t) = ir.safetyShortfallT;
    shortFeMWh(:, t) = ir.shortfallMWh;
    shed(t) = info.shed;
    cur(t) = info.cur;
    RE(t) = info.RE;
    rb(t) = info.rustBlockMWh;
    rbJ(:, t) = info.rustBlockJ;
    cost(t) = info.cost;
    Z(:, t) = info.z;
    risk(t) = dg.risk;
    Qv(t) = dg.Q;
    if ~isempty(dg.id) && numel(dg.id) == size(ids, 1)
        ids(:, t) = dg.id;
    end
    if ~isempty(dg.mpc)
        mpcT(t) = dg.mpc.time;
    end
    bAct(:, t) = info.b;
    rhoAct(:, t) = info.rho;
    shipFe(t) = sum(info.f(eFeOut));
    shipOx(t) = sum(info.f(eOxIn));
    nh3(t) = info.nh3MWh;
    if t > spec.warmup
        flowSum = flowSum + info.f(:);
    end
    tr = info.trunc;
    truncSum = truncSum + tr.b + tr.rho + tr.f;
    maxCons = max(maxCons, abs(sum(env.x) - spec.c) / spec.c);
end
ev = (spec.warmup + 1):L;
m.pF = mean(any(shortFe(:, ev) > 1e-6, 1));
m.forecastExposure = mean(any(muFe(:, ev) < 0, 1));
m.safetyExposure = mean(any(safetyFe(:, ev) > 1e-6, 1));
m.ironShortfallMWh = sum(shortFeMWh(:, ev), 'all');
m.pShed = mean(shed(ev) > 1e-6);
m.shedMWh = sum(shed(ev));
m.curRate = sum(cur(ev)) / max(sum(RE(ev)), 1e-9);
m.curMWh = sum(cur(ev));
m.rustBlockMWh = sum(rb(ev));
m.cost = sum(cost(ev));
m.costParts = sum(Z(:, ev), 2);
m.decTime = mean(decT(ev));
m.localFe = nnz(shortFe(:, ev) > 1e-6);
m.localForecastFe = nnz(muFe(:, ev) < 0);
m.localOx = nnz(muOx(:, ev) < 0);
m.localRB = nnz(rbJ(:, ev) > 1e-6);
m.loadMWh = sum(seg.EL(ev));
m.REMWh = sum(RE(ev));
m.maxConsRel = maxCons;
m.trunc = truncSum;
m.mpcTime = mean(mpcT(ev), 'omitnan');
% 实际低风光事件窗口内的断供与失负荷统计。
reg = seg.reg(1:L);
[lens, starts] = runLengths(reg(ev) == 2);
starts = starts + spec.warmup;
lag = ceil(ctx.Tl.mean);
eShed = false(1, numel(lens));
eF = false(1, numel(lens));
eForecast = false(1, numel(lens));
for q = 1:numel(lens)
    win = starts(q):min(L, starts(q) + lens(q) - 1 + lag);
    eShed(q) = any(shed(win) > 1e-6);
    eF(q) = any(any(shortFe(:, win) > 1e-6));
    eForecast(q) = any(any(muFe(:, win) < 0));
end
m.events = numel(lens);
m.eventLens = lens;
m.eventShed = mean(eShed);
m.eventF = mean(eF);
m.eventForecastExposure = mean(eForecast);
if isempty(lens)
    m.eventShed = NaN;
    m.eventF = NaN;
    m.eventForecastExposure = NaN;
end
threshold=.5;
if isfield(p.exp,'warningRiskThreshold'), threshold=p.exp.warningRiskThreshold; end
es=struct('shed',shed,'cur',cur,'ironShortT',sum(shortFe,1), ...
    'forecastMin',min(muFe,[],1),'safetySlack',IFe-ctx.safeFe,'risk',risk);
out.injectedEvent=eventWindowMetrics(es,ext,spec.warmup,lag,threshold);
im=out.injectedEvent;
m.injectedShedMWh=NaN; m.injectedAnyShed=NaN; m.injectedSafeDays=NaN;
m.followupShedMWh=NaN; m.followupAnyShed=NaN; m.injectedWarningLeadDays=NaN;
m.injectedComplete=NaN; m.followupComplete=NaN;
if im.available
    m.injectedComplete=double(im.core.complete); m.followupComplete=double(im.followup.complete);
    if im.core.complete
        m.injectedShedMWh=im.core.shedMWh; m.injectedAnyShed=im.core.anyShed;
        m.injectedSafeDays=im.core.safeAllPlantDays; m.injectedWarningLeadDays=im.warningLeadDays;
    end
    if im.followup.complete
        m.followupShedMWh=im.followup.shedMWh; m.followupAnyShed=im.followup.anyShed;
    end
end
out.metrics = m;
out.spec = spec;
out.ctrlName = ctrl.name;
out.ext = ext;
out.starvationDefinition = ir.definition;
out.reliabilityDefinition = 'pShed/eventShed and injectedShedMWh: realised unserved load; pF/eventF: plant iron starvation.';
out.transitionScope = 'Normal-capacity fitted weather reference; outages and station failures are distribution-shift stress tests with current capacities observed.';
out.eventDefinition = 'Low-renewable spell plus one loop-time follow-up; overlapping windows are clustered by weather year.';
out.daily = struct('minMuFe', single(min(muFe(:, ev), [], 1)), 'soc', single(soc(ev)), 'cost', single(cost(ev)), ...
    'RE', single(RE(ev)), 'load', single(seg.EL(ev)), 'shed', single(shed(ev)), 'cur', single(cur(ev)), ...
    'nh3', single(nh3(ev)), 'shipFe', single(shipFe(ev)), 'shipOx', single(shipOx(ev)), 'fc7', single(fc7(ev)), ...
    'reg', uint8(seg.reg(ev)));
out.daily.ironShortfallT = single(sum(shortFe(:, ev), 1));
out.daily.ironShortfallMWh = single(sum(shortFeMWh(:, ev), 1));
out.daily.safetyShortfallT = single(sum(safetyFe(:, ev), 1));
out.lineFlow = flowSum / max(numel(ev), 1);
out.trace = [];
if isfield(spec, 'keepTrace') && spec.keepTrace
    out.trace = struct('soc', soc, 'muFe', muFe, 'muOx', muOx, 'shed', shed, 'cur', cur, 'RE', RE, ...
        'rustBlock', rb, 'rustBlockJ', rbJ, 'cost', cost, 'Z', Z, 'risk', risk, 'Q', Qv, 'ids', ids, ...
        'IFe', IFe, 'SOx', SOx, 'b', bAct, 'rho', rhoAct, 'reg', reg, 'decTime', decT, 'warmup', spec.warmup, ...
        'mpcTime', mpcT);
    out.trace.ironShortfallT = shortFe;
    out.trace.safetyShortfallT = safetyFe;
end
end
