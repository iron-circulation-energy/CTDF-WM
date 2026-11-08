function R = natAssess(n, N, Cl)
%NATASSESS 全国 31 省评估：季节性储能需求、临界循环铁质量与路线竞争边界。
%   R = natAssess(n, N, Cl)；n = params_national()，N = natLoadInputs(n)，Cl = natClimate(N, n)。
%   对 n.scenarios 的每个情景各算一遍（情景只改动参数，不改动气象数据），基准情景的逐省结果写入 R.T，
%   全部情景的汇总写入 R.scen，并导出 n.outDir/national_results.csv、national_scenarios.csv 与 .mat。
%
%   每省：
%     储能服务  natStorage(r, d, η_ref, λ, pinQ)，r = φ_W·cf_W + (1 − φ_W)·cf_S（φ_W 为 2019 年风电容量占比），
%               d 为日负荷指数；η_ref 为铁路线（或情景 h2Service 下氢路线）往返效率。
%     输入电价  省内风光组合度电成本 LCOE_i × surplusValue（ERA5 校正后多年平均容量因子）。
%     路线（LCOS，元/kWh 放电量，natCost）：
%       FeL  省内还原、省内铁路短驳（里程 dLocal）、省内改造煤电燃烧；
%       FeX  其他省 h 还原（h 的电价与充电利用小时）、跨省铁路运铁（里程 dHub(h, i)）至省 i 电厂，取 h 的最小值；
%       FeT  特高压送端省 h 就地铁循环（h 的电价、充电利用小时与省内里程），电力经特高压直流送省 i：
%            LCOS_h/(1 − 线损) + 输电价，取送入省 i 的各回线路的最小值（仅有线路的受端省）；
%       H2S  省内电解制氢 + 盐穴储氢 + 氢燃机（仅盐穴等级 ≤ saltTierMax 的省）；
%       H2T  省内电解制氢 + 地面储罐 + 氢燃机；
%       NH3L 省内电解制氢 + 合成氨 + 液氨储罐 + 省内改造煤电纯氨燃烧（与 FeL 同样复用本省机组）。
%     临界循环铁质量  以省内 2005 年后投运煤电容量 C_i 作为放电功率，可稳定供应的平均负荷
%                     P̄_i = min(C_i/P_dis, 本省 2019 年平均负荷)，实际改造容量 = P̄_i·P_dis；
%                     序列峰值库存 M_sp 与临界循环质量的 M_event（natCapacityCheck）分别乘以 P̄_i，记为就地口径参考值 MtSP；
%                     汇总量 MtTotal 只计铁基路线获胜的省份，并按获胜路线（FeL、FeX、FeT）各自的充电条件与周转时间重算（MtWin）。
%     可保留资产价值  搁浅风险机组按 n.coal.life 年直线折算到提前退役年 n.coal.retireYear 的剩余寿命价值
%                     （单位造价 n.coal.capex），计入最优路线为 FeL 或 FeX（改造本省机组）的省份；另报 ±5 年与扣除改造投资后的净值。
%     风光结构      φ_W 的几率按 n.svc.windOdds 缩放（mix2024、pv2035 情景改变风电与光伏的相对规模）。
%     水电          基准情景下各省水电按 2019 年消纳占比视为平稳出力，从日负荷中扣除（n.svc.hydro）。
%   Cl.years必须为严格递增且连续的真实历年，避免将缺失年份两侧错误拼成连续过程。

if ~isfield(Cl,'years') || ~isnumeric(Cl.years) || ~isreal(Cl.years) || ...
        isempty(Cl.years) || ~isvector(Cl.years) || any(~isfinite(Cl.years)) || ...
        any(Cl.years~=fix(Cl.years)) || any(diff(Cl.years(:))~=1)
    error('natAssess:nonConsecutiveYears', ...
        ['Cl.years must contain strictly increasing consecutive integer calendar years. ', ...
         'Complete missing years before chronological sizing; cached data are unchanged.']);
end
if size(Cl.cfW,2)~=numel(Cl.years) || size(Cl.cfS,2)~=numel(Cl.years) || size(Cl.load,2)~=numel(Cl.years)
    error('natAssess:yearDimension','The year axis of cfW, cfS and load must match Cl.years.');
end
R.n = n;
R.years = Cl.years(:)';
sc = n.scenarios;
S = cell(numel(sc), 1);
R.winners = strings(height(N.prov), numel(sc));
serviceCache = struct('key', {}, 'svc', {});
for k = 1:numel(sc)
    ns = applyScenario(n, sc(k).set);
    % Technology sensitivities retain the baseline renewable/load service.
    % Only an explicitly changed service reference (e.g. h2Service) resizes it.
    if strcmpi(ns.svc.etaRef, 'h2')
        ns.svc.referenceEta = n.h2.etaEl*n.h2.etaGT;
    else
        ns.svc.referenceEta = n.fe.etaSt/(n.fe.kappa/n.fe.etaEl+n.fe.eps/n.fe.hFe);
    end
    key = [double(ns.svc.hydro), ns.svc.lambda, ns.svc.pinQ, ns.svc.referenceEta, windOdds(ns)];
    if isfield(n, 'portfolio') && isfield(n.portfolio, 'enable')
        ns.portfolio.enable = n.portfolio.enable && any(strcmp(sc(k).name, n.portfolio.scenarios));
    end
    hit = find(arrayfun(@(a) isequal(a.key,key),serviceCache),1);
    cached = [];
    if ~isempty(hit), cached = serviceCache(hit).svc; end
    [T, info] = assessOnce(ns, N, Cl, cached);
    if isempty(hit)
        serviceCache(end+1) = struct('key',key,'svc',{info.svc}); %#ok<AGROW>
    end
    if k == 1
        R.T = T;
        R.info = info;
    end
    S{k} = summarize(T, sc(k), ns);
    R.winners(:, k) = T.winner;
    if isfield(ns, 'portfolio') && isfield(ns.portfolio, 'enable') && ns.portfolio.enable && any(T.portOK)
        R.Tport.(sc(k).name) = T(:, portCols());
    end
end
R.scen = vertcat(S{:});
if ~exist(n.outDir, 'dir')
    mkdir(n.outDir);
end
Tout = R.T;
Tout.compFeL = [];
writetable(Tout, fullfile(n.outDir, 'national_results.csv'), 'Encoding', 'UTF-8');
writetable(R.scen, fullfile(n.outDir, 'national_scenarios.csv'), 'Encoding', 'UTF-8');
save(fullfile(n.outDir, 'national_results.mat'), 'R');
b = R.scen(1, :);
if isfield(n, 'quiet') && n.quiet
    return;
end
fprintf(['全国评估（基准，%d—%d 年 ERA5）：最优路线 FeL %d、FeX %d、FeT %d、H2S %d、H2T %d、NH3L %d 省；', ...
    '季节性储能自治天数中位数 %.0f d；铁基路线最优省份按获胜路线所需循环铁合计 %.0f Mt（为 2019 年全国粗钢产量的 %.0f%%）；', ...
    '铁燃料路线最优省份改造煤电 %.0f GW，可保留剩余寿命价值 %.0f 亿元（%.0f—%.0f）。\n'], ...
    R.years(1), R.years(end), b.nFeL, b.nFeX, b.nFeT, b.nH2S, b.nH2T, b.nNH3L, b.medD, b.MtTotal, 100 * b.steelShare, ...
    b.gwFeWin, b.assetBn, b.assetBnLo, b.assetBnHi);
if isfield(R, 'Tport')
    pn = fieldnames(R.Tport);
    for q = 1:numel(pn)
        bq = R.scen(R.scen.name == string(pn{q}), :);
        fprintf(['全国组合优化（%s）：%d 省求解；铁基路线在最优组合中承担 ≥ %.0f%% 放电量的省份 %d 个（与其他路线共存 %d 个）；', ...
            '全国储能放电量份额 铁 %.0f%%、氨 %.0f%%、氢 %.0f%%；组合相对最优单一路线降本 中位数 %.1f%%、按电量加权 %.1f%%。\n'], ...
            bq.label, bq.nPortProv, 100 * getfOr(n, 'portfolio', 'minShare', 0.05), bq.nFeInPort, bq.nMixed, ...
            100 * bq.feSharePort, 100 * bq.nh3SharePort, 100 * bq.h2SharePort, 100 * bq.mixGainMed, 100 * bq.mixGainWeighted);
        fn = 'national_portfolio.csv';
        if ~strcmp(pn{q}, 'base')
            fn = sprintf('national_portfolio_%s.csv', pn{q});
        end
        writetable(R.Tport.(pn{q}), fullfile(n.outDir, fn), 'Encoding', 'UTF-8');
    end
    save(fullfile(n.outDir, 'national_results.mat'), 'R');
end
end

function c = portCols()
c = {'name', 'short', 'winner', 'portOK', 'singleBestRoute', 'singleBest', 'portCost', 'mixGain', 'shareFe', ...
    'shareNH3', 'shareH2S', 'shareH2T', 'portEoutTWh', 'saltTier', 'gwYoung'};
end

function v = getfOr(n, a, b, d)
v = d;
if isfield(n, a) && isfield(n.(a), b)
    v = n.(a).(b);
end
end

function [T, info] = assessOnce(n, N, Cl, cached)
P = N.prov;
nP = height(P);
f = n.fe;
etaFe = f.etaSt / (f.kappa / f.etaEl + f.eps / f.hFe);
etaH2 = n.h2.etaEl * n.h2.etaGT;
etaNH3 = n.nh3.etaSt / (n.nh3.h2PerNH3 / f.etaEl + n.nh3.elSyn);
etaRef = etaFe;
if strcmpi(n.svc.etaRef, 'h2')
    etaRef = etaH2;
end
if isfield(n.svc,'referenceEta')
    etaRef = n.svc.referenceEta;
end
crf = @capitalFactor;
svc = cell(nP, 1);
svcFe = cell(nP, 1);
svcH2 = cell(nP, 1);
svcNH3 = cell(nP, 1);
th = cell(nP, 1);
rAll = cell(nP, 1);
lcoe = zeros(nP, 1);
phiUsed = zeros(nP, 1);
loopL = 2 * P.dLocal / n.rail.speed + n.rail.dwell;
for i = 1:nP
    cw = squeeze(Cl.cfW(i, :, :));
    cs = squeeze(Cl.cfS(i, :, :));
    dl = squeeze(Cl.load(i, :, :));
    if isvector(cw)
        cw = cw(:)';
        cs = cs(:)';
        dl = dl(:)';
    end
    if n.svc.hydro
        dl = dl - P.hydroShare(i);                  % 水电按 2019 年消纳占比平稳出力，风光 + 储能承担其余负荷
    end
    phi = P.phiW(i);
    o = windOdds(n);
    phi = phi * o / (phi * o + 1 - phi);             % 风电容量占比的几率按情景缩放
    phiUsed(i) = phi;
    r = phi * cw + (1 - phi) * cs;
    rAll{i} = r;
    if isempty(cached)
        svc{i} = natStorage(r, dl, etaRef, n.svc.lambda, n.svc.pinQ, Cl.years);
    else
        svc{i} = cached{i};
    end
    sFe = natRouteService(svc{i},etaFe);
    svcFe{i} = sFe;
    svcH2{i} = natRouteService(svc{i},etaH2);
    svcNH3{i} = natRouteService(svc{i},etaNH3);
    th{i} = natCapacityCheck(sFe, r, n, loopL(i));
    th{i}.SFe = sFe.S;
    th{i}.peakFe = svc{i}.peakDis;
    if ~sFe.feasible
        th{i}.Msp = NaN;
        th{i}.Mevent = NaN;
    end
    annW = n.re.capexW * (crf(n.r, n.re.lifeW) + n.re.om);
    annS = n.re.capexS * (crf(n.r, n.re.lifeS) + n.re.om);
    lcoe(i) = (phi * annW + (1 - phi) * annS) / (8760 * (phi * mean(cw(:)) + (1 - phi) * mean(cs(:))));
end
pin = lcoe * n.re.surplusValue;
hIn = cellfun(@(s) s.hIn, svc);
C = N.coal;
young = C.year >= n.coal.yearMin & C.provIdx > 0 & C.year+n.coal.life > n.coal.retireYear;
gwY = accumarray(C.provIdx(young), C.mw(young), [nP, 1]) / 1e3;

FeL = nan(nP, 1);
FeX = nan(nP, 1);
FeT = nan(nP, 1);
H2S = nan(nP, 1);
H2T = nan(nP, 1);
NH3L = nan(nP, 1);
hubX = zeros(nP, 1);
shX = cell(nP, 1);                                   % 跨省运铁最优送端的路线服务（获胜路线铁质量用）
loopX = nan(nP, 1);
shT = cell(nP, 1);                                   % 送端特高压最优线路的送端路线服务
hT = zeros(nP, 1);
lineT = strings(nP, 1);
compFeL = zeros(nP, 4);
U = N.uhv;
useLine = U.status == "operating";
if n.uhv.includeConstruction
    useLine = useLine | U.status == "construction";
end
for i = 1:nP
    s = svc{i};
    if svcFe{i}.feasible && gwY(i) > 0
        [FeL(i), compFeL(i, :)] = natCost('fe', svcFe{i}, pin(i), n, P.dLocal(i), loopL(i));
    end
    best = inf;
    for h = setdiff(1:nP, i)
        sh = natRouteService(s,etaFe,svc{h}.chAvailable);
        if ~sh.feasible || gwY(i) <= 0
            continue;
        end
        dd = N.dHub(h, i);
        c = natCost('fe', sh, pin(h), n, dd, 2 * dd / n.rail.speed + n.rail.dwell);
        if c < best
            best = c;
            hubX(i) = h;
            shX{i} = sh;
            loopX(i) = 2 * dd / n.rail.speed + n.rail.dwell;
        end
    end
    FeX(i) = best;
    li = find(useLine & U.toIdx == i);
    best = inf;
    for q = li(:)'
        h = U.fromIdx(q);
        % The sending store supplies the same delivered trajectory plus line losses.
        sent = s;
        sent.de = s.de/(1-n.uhv.loss);
        sh = natRouteService(sent,etaFe,svc{h}.chAvailable);
        if ~sh.feasible || U.mw(q) <= 0 || gwY(h) <= 0
            continue;
        end
        c = natCost('fe', sh, pin(h), n, P.dLocal(h), loopL(h)) / (1 - n.uhv.loss) + n.uhv.tariff;
        if c < best
            best = c;
            lineT(i) = U.name(q);
            shT{i} = sh;
            hT(i) = h;
        end
    end
    if isfinite(best)
        FeT(i) = best;
    end
    if P.saltTier(i) <= n.h2.saltTierMax && svcH2{i}.feasible
        H2S(i) = natCost('h2', svcH2{i}, pin(i), n, 0, 0, n.h2.storeSalt);
    end
    if svcH2{i}.feasible
        H2T(i) = natCost('h2', svcH2{i}, pin(i), n, 0, 0, n.h2.storeTank);
    end
    if svcNH3{i}.feasible && gwY(i) > 0
        NH3L(i) = natCost('nh3', svcNH3{i}, pin(i), n, 0, 0);
    end
end
% 氨掺烧上限 β < 1：单一路线 NH3L 变为同一机组的氨—铁掺烧（放电量 β 来自氨、1 − β 来自就地铁循环），
% 成本按放电量份额加权；本省铁循环不可行时该路线不可行。
betaNH3 = 1;
if isfield(n.nh3, 'blendMax') && ~isempty(n.nh3.blendMax)
    betaNH3 = n.nh3.blendMax;
end
if betaNH3 < 1
    NH3L = betaNH3 * NH3L + (1 - betaNH3) * FeL;
end
L = [FeL, FeX, FeT, H2S, H2T, NH3L];
routes = ["FeL", "FeX", "FeT", "H2S", "H2T", "NH3L"];
Ls = L;
Ls(isnan(Ls)) = inf;
[srt, ord] = sort(Ls, 2);
winner = routes(ord(:, 1))';
winner(~isfinite(srt(:,1))) = "infeasible";
margin = srt(:, 2) - srt(:, 1);
margin(~isfinite(margin)) = NaN;
bestFe = min([FeL, FeX, FeT], [], 2, 'omitnan');
bestH2 = min([H2S, H2T], [], 2, 'omitnan');
bestNH3 = NH3L;

% 搁浅风险机组（情景 young2010 改变投运年下限）与剩余寿命价值
Trs = n.coal.retireYear + [-5, 0, 5];
A = zeros(nP, 3);                                    % 亿元，按直线折算到提前退役年的剩余寿命价值
for j = 1:3
    remF = max(0, C.year(young) + n.coal.life - Trs(j)) / n.coal.life;
    A(:, j) = accumarray(C.provIdx(young), C.mw(young) * 1e3 * n.coal.capex .* remF, [nP, 1]) / 1e8;
end
feWin = winner == "FeL" | winner == "FeX";           % 改造本省机组的路线（FeT 改造的是送端省机组，不计入受端省）
coalWin = feWin | winner == "NH3L";                 % 复用本省煤电的全部燃料路线（铁或氨）

% 临界循环铁质量（以搁浅风险煤电容量为放电功率）
eOut = f.etaSt * f.hFe;
% 以搁浅风险机组为放电功率可稳定供应的平均负荷，不超过本省 2019 年平均负荷（多余机组服务外送或退役，不计入）
pk = cellfun(@(t) t.peakFe, th);
Pbar = min(gwY * 1e3 ./ pk, P.consGWh * 1e3 / 8760);         % MW 平均负荷
retroGW = Pbar .* pk / 1e3;                                  % 实际改造容量（GW）
retroShare = retroGW ./ max(gwY, eps);
Msp = cellfun(@(t) t.Msp, th) .* Pbar / 1e6;                   % Mt
Mevent = cellfun(@(t) t.Mevent, th) .* Pbar / 1e6;
% 获胜路线的循环铁量（Mt）：就地铁循环取本省口径；跨省运铁按送端充电条件与跨省周转时间重算；
% 送端特高压按送端储能（含线损）与送端周转时间重算，稳定供电负荷取送端改造容量与受端负荷的较小者；非铁路线为 0。
MtWin = zeros(nP, 1);
MtWinThm = zeros(nP, 1);
for i = 1:nP
    switch winner(i)
        case "FeL"
            MtWin(i) = Msp(i);
            MtWinThm(i) = Mevent(i);
        case "FeX"
            t = natCapacityCheck(shX{i}, rAll{i}, n, loopX(i));
            MtWin(i) = t.Msp * Pbar(i) / 1e6;
            MtWinThm(i) = t.Mevent * Pbar(i) / 1e6;
        case "FeT"
            h = hT(i);
            t = natCapacityCheck(shT{i}, rAll{i}, n, loopL(h));
            pT = min(gwY(h) * 1e3 / max(shT{i}.peakDis, eps), P.consGWh(i) * 1e3 / 8760);
            MtWin(i) = t.Msp * pT / 1e6;
            MtWinThm(i) = t.Mevent * pT / 1e6;
    end
end
T = table(P.name, P.short, 'VariableNames', {'name', 'short'});
T.D = cellfun(@(s) s.D, svc);
T.S = cellfun(@(s) s.S, svc);
T.peakDis = cellfun(@(s) s.peakDis, svc);
T.hOut = cellfun(@(s) s.hOut, svc);
T.hIn = hIn;
T.K = cellfun(@(s) s.K, svc);
T.curt = cellfun(@(s) s.curt, svc);
T.direct = cellfun(@(s) s.direct, svc);
T.cfW = mean(reshape(Cl.cfW, nP, []), 2);
T.cfS = mean(reshape(Cl.cfS, nP, []), 2);
T.phiW = phiUsed;
T.lcoe = lcoe;
T.pin = pin;
T.FeL = FeL;
T.FeX = FeX;
T.hubX = strings(nP, 1);
T.hubX(hubX > 0) = P.short(hubX(hubX > 0));
T.FeT = FeT;
T.lineT = lineT;
T.H2S = H2S;
T.H2T = H2T;
T.NH3L = NH3L;
T.winner = winner;
T.margin = margin;
T.feMinusH2 = bestFe - bestH2;
T.feMinusNH3 = bestFe - bestNH3;
T.compFeL = compFeL;
T.saltTier = P.saltTier;
T.gwYoung = gwY;
T.retroGW = retroGW;
T.hydroShare = P.hydroShare;
T.assetAllBn = A(:, 2);                              % 搁浅风险机组在提前退役年的剩余寿命价值（亿元）
T.assetBn = A(:, 2) .* retroShare .* feWin;         % 铁路线胜出省份实际改造部分可保留的价值（按改造容量比例）
T.assetBnLo = A(:, 3) .* retroShare .* feWin;       % 提前退役年 +5 年：较低剩余价值
T.assetBnHi = A(:, 1) .* retroShare .* feWin;       % 提前退役年 −5 年：较高剩余价值
T.retrofitBn = n.fe.capRetro * retroGW * 1e6 / 1e8 .* feWin;   % 改造投资（亿元）
T.assetCoalBn = A(:, 2) .* retroShare .* coalWin;   % 铁或氨燃料路线胜出省份可保留的价值
T.PbarGW = Pbar / 1e3;
T.firmTWh = Pbar * 8760 / 1e6;
T.firmShare = T.firmTWh * 1e3 ./ P.consGWh;
T.MtSP = Msp;                                        % 就地铁循环口径的参考循环铁量（全部省份，与获胜路线无关）
T.MtThm = Mevent;
T.MtWin = MtWin;                                     % 获胜路线为铁基路线时的循环铁量（其余省份为 0）
T.MtWinThm = MtWinThm;
T.thmRatio = cellfun(@(t) t.Mevent / max(t.Msp, eps), th);          % 与容量无关（每 MW）
T.tPerMW = cellfun(@(t) t.Msp, th) ./ cellfun(@(t) t.peakFe, th);   % t 铁 / MW 改造容量
T.Dmax = cellfun(@(t) t.Dmax, th);
T.lowFreq = cellfun(@(t) t.lowFreq, th);
T.loopDays = loopL;
% 组合优化（日尺度容量扩展线性规划，natPortfolio）：多条路线共同满足同一放电需求，与单一路线“择一”对照
T.portOK = false(nP, 1);
T.portCost = nan(nP, 1);                             % 元/MWh 放电量
T.singleBest = nan(nP, 1);                           % 同一线性规划下最优单一路线的成本（元/MWh）
T.singleBestRoute = strings(nP, 1);
T.mixGain = nan(nP, 1);                              % 组合相对最优单一路线的成本降低比例
T.shareFe = zeros(nP, 1);
T.shareH2S = zeros(nP, 1);
T.shareH2T = zeros(nP, 1);
T.shareNH3 = zeros(nP, 1);
T.portEoutTWh = zeros(nP, 1);                        % 省级储能年放电量（TWh）
if isfield(n, 'portfolio') && isfield(n.portfolio, 'enable') && n.portfolio.enable
    for i = 1:nP
        Lmean = P.consGWh(i) * 1e3 / 8760;           % MW 平均负荷
        capCoal = gwY(i) * 1e3 / max(Lmean, eps);
        saltOK = P.saltTier(i) <= n.h2.saltTierMax;
        po = natPortfolio(svc{i}, pin(i), n, capCoal, saltOK, P.dLocal(i), loopL(i));
        if ~po.ok
            continue;
        end
        T.portOK(i) = true;
        T.portCost(i) = po.costPerMWh;
        for k = 1:numel(po.techs)
            switch po.techs{k}
                case 'Fe', T.shareFe(i) = po.share(k);
                case 'H2S', T.shareH2S(i) = po.share(k);
                case 'H2T', T.shareH2T(i) = po.share(k);
                case 'NH3', T.shareNH3(i) = po.share(k);
            end
        end
        best = inf;
        for k = 1:numel(po.techs)
            if strcmp(po.techs{k}, 'NH3') && betaNH3 < 1
                continue;                            % 掺烧上限下氨不能单独供电
            end
            ps = natPortfolio(svc{i}, pin(i), n, capCoal, saltOK, P.dLocal(i), loopL(i), po.techs(k));
            if ps.ok && ps.costPerMWh < best
                best = ps.costPerMWh;
                T.singleBestRoute(i) = string(po.techs{k});
            end
        end
        T.singleBest(i) = best;
        T.mixGain(i) = 1 - po.costPerMWh / best;
        T.portEoutTWh(i) = svc{i}.Eout * 24 * Lmean / 1e6;
    end
end
T.dLocal = P.dLocal;
T.feChargeFeasible = cellfun(@(s) s.feasible,svcFe);
T.h2ChargeFeasible = cellfun(@(s) s.feasible,svcH2);
T.nh3ChargeFeasible = cellfun(@(s) s.feasible,svcNH3);
T.feCycleResidual = cellfun(@(s) s.cycleResidual,svcFe);
T.h2CycleResidual = cellfun(@(s) s.cycleResidual,svcH2);
info.etaFe = etaFe;
info.etaH2 = etaH2;
info.etaNH3 = etaNH3;
info.pin = pin;
info.gwY = gwY;
info.loopL = loopL;
info.etaRef = etaRef;
info.eOut = eOut;
info.svc = svc;
info.svcFe = svcFe;
info.svcH2 = svcH2;
info.svcNH3 = svcNH3;
info.scope = 'Provincial service assessment; donor charging uses its reference surplus per MW mean load; UHV routes use line presence and rating.';
info.th = th;
info.routes = routes;
end

function s = summarize(T, sc, n)
w = T.winner;
s = table(string(sc.name), string(sc.label), 'VariableNames', {'name', 'label'});
s.nFeL = nnz(w == "FeL");
s.nFeX = nnz(w == "FeX");
s.nFeT = nnz(w == "FeT");
s.nH2S = nnz(w == "H2S");
s.nH2T = nnz(w == "H2T");
s.nNH3L = nnz(w == "NH3L");
s.nFe = s.nFeL + s.nFeX + s.nFeT;
s.medD = median(T.D);
s.medFeL = median(T.FeL);
s.medH2T = median(T.H2T);
s.medNH3L = median(T.NH3L, 'omitnan');
s.MtTotal = sum(T.MtWin,'omitnan');                 % 铁基路线获胜省份按获胜路线汇总的循环铁量
s.MtThmTotal = sum(T.MtWinThm,'omitnan');
s.MtRefAll = sum(T.MtSP,'omitnan');                  % 全部省份就地铁循环口径的参考总量（不用于路线结论）
s.nFeChargeInfeasible = nnz(~T.feChargeFeasible);
s.nNoFeasibleRoute = nnz(w == "infeasible");
if ismember('portOK', T.Properties.VariableNames) && any(T.portOK)
    ms = 0.05;
    if isfield(n, 'portfolio') && isfield(n.portfolio, 'minShare')
        ms = n.portfolio.minShare;
    end
    ok = T.portOK;
    wE = T.portEoutTWh(ok);
    s.nPortProv = nnz(ok);
    s.nFeInPort = nnz(ok & T.shareFe >= ms);           % 铁基路线在最优组合中承担 ≥ minShare 放电量的省份数
    s.feSharePort = sum(T.shareFe(ok) .* wE) / max(sum(wE), eps);   % 全国储能放电量中铁基路线的份额
    s.nh3SharePort = sum(T.shareNH3(ok) .* wE) / max(sum(wE), eps);
    s.h2SharePort = sum((T.shareH2S(ok) + T.shareH2T(ok)) .* wE) / max(sum(wE), eps);
    s.mixGainMed = median(T.mixGain(ok), 'omitnan');
    s.mixGainWeighted = sum(T.mixGain(ok) .* wE, 'omitnan') / max(sum(wE), eps);
    s.nMixed = nnz(ok & (T.shareFe >= ms) & (T.shareFe <= 1 - ms));   % 铁与其他路线共存的省份数
else
    s.nPortProv = 0; s.nFeInPort = NaN; s.feSharePort = NaN; s.nh3SharePort = NaN; s.h2SharePort = NaN;
    s.mixGainMed = NaN; s.mixGainWeighted = NaN; s.nMixed = NaN;
end
s.steelShare = s.MtTotal * 1e6 / n.steel2019;
s.firmTWh = sum(T.firmTWh);
fe = T.winner == "FeL" | T.winner == "FeX";
s.gwFeWin = sum(T.retroGW(fe));
s.retroGW = sum(T.retroGW);
s.assetBn = sum(T.assetBn);
s.assetBnLo = sum(T.assetBnLo);
s.assetBnHi = sum(T.assetBnHi);
s.netAssetBn = s.assetBn - sum(T.retrofitBn);
s.assetCoalBn = sum(T.assetCoalBn);
end

function o = windOdds(n)
o = 1;
if isfield(n.svc, 'windOdds')
    o = n.svc.windOdds;
end
end

function n = applyScenario(n, set)
for k = 1:2:numel(set)
    parts = strsplit(set{k}, '.');
    n.(parts{1}).(parts{2}) = set{k + 1};
end
end

function v = capitalFactor(r, life)
if r == 0
    v = 1 ./ life;
else
    v = r ./ (-expm1(-life .* log1p(r)));
end
end
