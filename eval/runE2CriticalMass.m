function e2 = runE2CriticalMass(C, methods, years, seeds, epDir, extra)
%RUNE2CRITICALMASS E2 临界循环质量扫描。
%   c 网格：0.5·M_LL 至 2·M_crit 均匀取 p.exp.cGridN 个点，并入 0.8·M_0 至 1.15·M_crit(ε) 的 p.exp.cDenseN 个加密点
%   （几何尾转折区；M_crit(ε) 不可用时取 M_crit），合并后升序去重；每个点覆盖全部测试年份 × 种子（常规工况）。
%   均匀点取值与旧版一致，已缓存的逐回合结果可直接复用。
%   p.exp.cGridAbs 非空时改用该绝对网格（并入 M_0、M_crit(ε)、M_crit 与名义质量），加密点照常并入（cDenseN = 0 时不加密）。
%   pF/eventF 为电厂断供概率，forecastExposure 为预测裕度暴露，eventShed/shedMWh 为失负荷；
%   事件断供频率拐点与固定预留缓冲的几何尾计算值对照绘制。
%   跨 c 点保持年份配对的 bootstrap 默认200次；少于2年不报告年际区间。
%   methods：结构体数组，字段 name 与 factory（@(seed) 控制器）。
%   epDir（可选）：断点续跑的逐回合缓存目录（见 evalEpisodes），已完成的回合直接读取。
%   extra（可选）：只在部分质量点评估的对照方法（结构体数组，字段 name、factory、cList），结果单独存于 e2.extra，
%                  与主方法在相同质量点、年份与种子上配对（用于检验守恒约束在训练分布两端的作用）；不进入拐点与图 F05。
%   e2.designOpt：各方法计入循环铁年化资金成本（c·铁粉单价·折现率）后的总成本最低质量点及其成本，
%                 回应"比较优势是否依赖名义质量点"：每个方法都在自己的最优质量下比较。
%   输出 e2：cGrid、episodes（全部回合指标表）、daily（方法 × c × 种子的逐日最小铁裕度，图 F05）、
%            summary（方法 × c 的均值与置信区间）、knee（拐点估计）、
%            capacity（M_LL、M_crit、M_crit(ε)、M_0、P_F 曲线）、local（c ≥ M_crit 的局部瓶颈计数）。

if nargin < 5
    epDir = '';
end
if nargin < 6
    extra = [];
end
p = C.p;
cm = C.cm;
cGrid = linspace(0.5 * cm.M_LL, 2 * cm.M_crit, p.exp.cGridN);
if isfield(p.exp, 'cGridAbs') && ~isempty(p.exp.cGridAbs)
    an = [cm.M_0, cm.M_eps, cm.M_crit, C.cNominal];          % 网格中加入理论锚点与名义质量，供图 F05 标注
    an = an(isfinite(an) & an >= min(p.exp.cGridAbs) & an <= max(p.exp.cGridAbs));
    cGrid = unique(sort([p.exp.cGridAbs(:)', an]));
end
nDense = 8;
if isfield(p.exp, 'cDenseN') && ~isempty(p.exp.cDenseN)
    nDense = p.exp.cDenseN;
end
mHi = cm.M_eps;
if ~(isfinite(mHi) && mHi > cm.M_0)
    mHi = cm.M_crit;
end
if nDense > 0 && isfinite(cm.M_0) && mHi > cm.M_0
    cDense = linspace(0.8 * cm.M_0, 1.15 * mHi, nDense);
    cDense = cDense(cDense > cGrid(1) & cDense < cGrid(end));
    keep = arrayfun(@(c) all(abs(cGrid - c) > 0.005 * (cGrid(end) - cGrid(1))), cDense);
    cGrid = sort([cGrid, cDense(keep)]);
end
Tall = {};
daily = struct('method', {}, 'c', {}, 'minMuFe', {});
for m = 1:numel(methods)
    for s = seeds(:)'
        ctrl = methods(m).factory(s);
        for c = cGrid
            specs = makeEvalSpecs(p, years, s, {'normal'}, c);
            [Rk, T] = evalEpisodes(C.ctx, C.W, specs, ctrl, [], epDir);
            T.method = repmat({methods(m).name}, height(T), 1);
            Tall{end + 1} = T; %#ok<AGROW>
            md = arrayfun(@(r) r.daily.minMuFe, Rk, 'UniformOutput', false);
            daily(end + 1) = struct('method', methods(m).name, 'c', c, 'minMuFe', [md{:}]); %#ok<AGROW>
        end
    end
end
E = vertcat(Tall{:});
% 部分质量点的对照方法（与主方法同一年份、种子与质量点配对）
e2.extra = struct('episodes', [], 'summary', [], 'paired', []);
if ~isempty(extra)
    Tx = {};
    for m = 1:numel(extra)
        cx = cGrid(arrayfun(@(c) any(abs(extra(m).cList(:) - c) <= 1e-6 * max(1, c)), cGrid));
        if isempty(cx)
            cx = extra(m).cList(:)';
        end
        for s = seeds(:)'
            ctrl = extra(m).factory(s);
            for c = cx
                specs = makeEvalSpecs(p, years, s, {'normal'}, c);
                [~, T] = evalEpisodes(C.ctx, C.W, specs, ctrl, [], epDir);
                T.method = repmat({extra(m).name}, height(T), 1);
                Tx{end + 1} = T; %#ok<AGROW>
            end
        end
    end
    Ex = vertcat(Tx{:});
    e2.extra.episodes = Ex;
    e2.extra.summary = statsUtils('summaryTable', Ex, {'method', 'c'}, {'pF', 'eventF', 'shedMWh', 'curRate', 'cost'});
    e2.extra.paired = pairedAt(E, Ex, 'M1');
end
e2.cGrid = cGrid;
e2.cNominal = C.cNominal;
e2.episodes = E;
e2.daily = daily;
e2.summary = statsUtils('summaryTable', E, {'method', 'c'}, ...
    {'pF', 'eventF', 'eventShed', 'shedMWh', 'curRate', 'rustBlockMWh', 'cost'});
e2.designOpt = designOptimum(E, p);
% 理论曲线与拐点
cf = linspace(cGrid(1), cGrid(end), 400);
e2.capacity = struct('M_LL', cm.M_LL, 'M_crit', cm.M_crit, 'M_eps', cm.M_eps, 'M_0', cm.M_0, 'eps', cm.eps, ...
    'cFine', cf, 'PF', cm.PF(cf), 'ci', cm.ci);
e2.capacity.referenceOnly=cm.referenceOnly;
e2.capacity.designExact=cm.designExact;
e2.capacity.bufferSpec=cm.bufferSpec;
e2.capacity.boundKind=cm.boundKind;
e2.metricScope='eventF/pF: plant iron starvation; eventShed/shedMWh: realised unserved load.';
[kt1, ~] = statsUtils('knee2seg', cf, cm.PF(cf));
[kt2, ~] = statsUtils('kneeCurv', cf, cm.PF(cf));
e2.knee = struct('method', {}, 'twoSeg', {}, 'twoSegCI', {}, 'curv', {}, 'curvCI', {}, 'theoryTwoSeg', {}, ...
    'theoryCurv', {}, 'devTwoSeg', {}, 'devCurv', {});
rs = RandStream('twister', 'Seed', p.seed + 5);
names = unique(E.method, 'stable');
for m = 1:numel(names)
    sel = strcmp(E.method, names{m});
    Em = E(sel, :);
    y = arrayfun(@(c) mean(Em.eventF(abs(Em.c - c) < 1e-9 * max(1, c)), 'omitnan'), cGrid);
    k1 = statsUtils('knee2seg', cGrid, y);
    k2 = statsUtils('kneeCurv', cGrid, y);
    B = 200;
    if isfield(p.exp,'kneeBootB'), B=p.exp.kneeBootB; end
    kb = nan(B, 2);
    yearIds=unique(Em.year);
    for b = 1:B
        sampledYears=yearIds(randi(rs,numel(yearIds),numel(yearIds),1));
        yb = nan(size(cGrid));
        for q = 1:numel(cGrid)
            v=nan(numel(sampledYears),1);
            for yy=1:numel(sampledYears)
                mask=Em.year==sampledYears(yy) & abs(Em.c-cGrid(q))<1e-9*max(1,cGrid(q));
                v(yy)=mean(Em.eventF(mask),'omitnan');
            end
            yb(q)=mean(v,'omitnan');
        end
        if nnz(~isnan(yb)) >= 4
            kb(b, 1) = statsUtils('knee2seg', cGrid, yb);
            kb(b, 2) = statsUtils('kneeCurv', cGrid, yb);
        end
    end
    e2.knee(m).method = names{m};
    e2.knee(m).twoSeg = k1;
    e2.knee(m).twoSegCI = quantileLin(kb(:, 1), [0.025, 0.975]);
    e2.knee(m).curv = k2;
    e2.knee(m).curvCI = quantileLin(kb(:, 2), [0.025, 0.975]);
    if numel(yearIds)<2
        e2.knee(m).twoSegCI=[NaN NaN]; e2.knee(m).curvCI=[NaN NaN];
    end
    e2.knee(m).theoryTwoSeg = kt1;
    e2.knee(m).theoryCurv = kt2;
    e2.knee(m).devTwoSeg = (k1 - kt1) / kt1;
    e2.knee(m).devCurv = (k2 - kt2) / kt2;
    hiC = Em.c >= cm.M_crit;
    e2.local(m) = struct('method', names{m}, 'localFe', sum(Em.localFe(hiC)), 'localOx', sum(Em.localOx(hiC)), ...
        'localRB', sum(Em.localRB(hiC)), 'episodes', nnz(hiC)); %#ok<AGROW>
end
end

function D = designOptimum(E, p)
% 各方法在每个质量点的年化总成本 = 运行成本（评估期折算到年）+ 循环铁资金成本 c·铁粉单价·r，取最低点；
% 并报告在对方最优点、在名义质量点的比较。料仓、还原站与电解槽投资与 c 无关，不改变排序。
yr = 365 / p.exp.evalDays;
r = p.retire.discount;
meth = unique(E.method, 'stable');
rows = {};
for m = 1:numel(meth)
    Em = E(strcmp(E.method, meth{m}), :);
    cs = unique(Em.c);
    tot = zeros(numel(cs), 1);
    op = zeros(numel(cs), 1);
    for k = 1:numel(cs)
        op(k) = mean(Em.cost(Em.c == cs(k))) * yr;
        tot(k) = op(k) + cs(k) * p.iron.price * r;
    end
    [tb, kb] = min(tot);
    rows(end + 1, :) = {meth{m}, cs(kb), tb, op(kb), cs(kb) * p.iron.price * r}; %#ok<AGROW>
end
D = cell2table(rows, 'VariableNames', {'method', 'cOpt', 'totalAnnual', 'opAnnual', 'ironCapitalAnnual'});
end

function P = pairedAt(E, Ex, ref)
% 对照方法与参考方法在相同年份、种子与质量点上的配对成本差（对照 − 参考，元/评估期）与配对 t 检验
rows = {};
mx = unique(Ex.method, 'stable');
for m = 1:numel(mx)
    X = Ex(strcmp(Ex.method, mx{m}), :);
    for c = unique(X.c)'
        Xc = X(X.c == c, :);
        Rc = E(strcmp(E.method, ref) & E.c == c, :);
        [ok, ia, ib] = intersect([Xc.year, Xc.seed], [Rc.year, Rc.seed], 'rows');
        if isempty(ok)
            continue;
        end
        dlt = Xc.cost(ia) - Rc.cost(ib);
        n = numel(dlt);
        se = std(dlt) / sqrt(max(n, 1));
        tval = mean(dlt) / max(se, eps);
        pv = NaN;
        if n > 1
            pv = 2 * (1 - tcdfLocal(abs(tval), n - 1));
        end
        rows(end + 1, :) = {mx{m}, ref, c, n, mean(Rc.cost(ib)), mean(Xc.cost(ia)), mean(dlt), ...
            mean(dlt) / max(mean(Rc.cost(ib)), eps), pv}; %#ok<AGROW>
    end
end
if isempty(rows)
    P = table();
    return;
end
P = cell2table(rows, 'VariableNames', {'method', 'ref', 'c', 'n', 'refCost', 'cost', 'dCost', 'dRel', 'pValue'});
end

function v = tcdfLocal(t, df)
% Student t 累积分布（不依赖统计工具箱）
x = df / (df + t ^ 2);
v = 1 - 0.5 * betainc(x, df / 2, 0.5);
end
