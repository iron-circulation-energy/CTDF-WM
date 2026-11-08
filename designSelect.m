function D = designSelect(stamps, z)
%DESIGNSELECT 由 designScan 的结果按"一倍标准误规则"选取设计点（不重新扫描，读取已缓存的回合）。
%   D = designSelect({'20261106_114007','20261106_122556'})
%   规则：各组合的年化总成本 = 运行成本 + 充能侧投资年金 + 循环铁资金成本。验证年只有数年，成本差异小于
%   逐年配对差的 z 倍标准误（缺省 z = 1）时在统计上无法区分，视为并列最低；在并列组合中取年失负荷最小者。
%   这与模型选择中的一倍标准误规则（Breiman et al. 1984；Hastie et al. 2009）同理：在无法区分的候选中取更稳健者。
%   同时报告纯总成本最低的组合。结果写入 config/design_point.mat，并重绘图 F25（红框为选定点，虚线框为纯最低点）。
%   各组合最优候选的逐年回合从 designScan 的缓存目录读取，缺失时重新计算（每个组合约 10 s）。
setupPaths();
if nargin < 2 || isempty(z)
    z = 1;
end
if ~iscell(stamps), stamps = {stamps}; end
p = params_paper();
p.station.pRedMax = p.station.pRedMax / p.design.pMult;
p.design.pMult = 1;
p = deriveParams(p);
root = fullfile(p.exp.resultsRoot, 'designScan');
T = [];
src = {};
for q = numel(stamps):-1:1                           % 后一次扫描优先
    Tq = readtable(fullfile(root, stamps{q}, 'designScan.csv'));
    if isempty(T)
        keep = true(height(Tq), 1);
    else
        keep = ~ismember([Tq.mult, Tq.cKt], [T.mult, T.cKt], 'rows');
    end
    T = [T; Tq(keep, :)]; %#ok<AGROW>
    src = [src; repmat(stamps(q), nnz(keep), 1)]; %#ok<AGROW>
end
[T, ix] = sortrows(T, {'mult', 'cKt'});
src = src(ix);
C = buildCase(p);
years = p.weather.val;
seed = p.exp.seeds(1);
yr = 365 / p.exp.evalDays;
n = height(T);
ny = numel(years);
opY = nan(n, ny);
shY = nan(n, ny);
mults = unique(T.mult)';
for mlt = mults
    pv = p;
    pv.station.pRedMax = mlt * p.station.pRedMax;
    pv = deriveParams(pv);
    Cv = buildCase(pv, C.W);
    lib = policyLibrary(pv, Cv.topo, Cv.stats, pv.seed);
    for k = find(T.mult == mlt)'
        cand = lib.candidates(:, T.bestCand(k));
        ctrl = makeController('fixed', sprintf('cand%02d', T.bestCand(k)), jointPolicy(lib, cand));
        specs = makeEvalSpecs(pv, years, seed, {'normal'}, T.cKt(k) * 1e3);
        epDir = fullfile(root, src{k}, 'episodes', sprintf('x%g', mlt));
        [~, Te] = evalEpisodes(Cv.ctx, Cv.W, specs, ctrl, [], epDir);
        [~, o] = ismember(years(:), Te.year);
        opY(k, :) = Te.cost(o)' * yr;
        shY(k, :) = Te.shedMWh(o)';
    end
end
fixedK = T.chargeCapexAnnual + T.ironCapitalAnnual;
totY = opY + fixedK;
T.totalAnnualCheck = mean(totY, 2);
[~, b0] = min(T.totalAnnual);
dlt = totY - totY(b0, :);
T.dTotal = mean(dlt, 2);
T.seDiff = std(dlt, 0, 2) / sqrt(ny);
T.seDiff(b0) = 0;
T.tie = T.dTotal <= z * T.seDiff;
T.tie(b0) = true;
T.shedGWh = mean(shY, 2) / 1e3;
cand = find(T.tie);
[~, j] = min(T.shedGWh(cand));
b = cand(j);
design = struct('pMult', T.mult(b), 'cNominal', T.cKt(b) * 1e3, 'kappa', p.station.kappa(1), ...
    'rule', sprintf(['validation years, fixed candidates; least annualised total cost within %g paired standard error ', ...
    '(ties) and, among ties, least unserved load'], z), 'stamp', strjoin(stamps, '+'), 'totalAnnual', T.totalAnnual(b), ...
    'minCostMult', T.mult(b0), 'minCostC', T.cKt(b0) * 1e3);
f = fullfile(fileparts(mfilename('fullpath')), 'config', 'design_point.mat');
save(f, 'design', 'T');
disp(T(T.tie, {'mult', 'cKt', 'pRedMW', 'totalAnnual', 'dTotal', 'seDiff', 'shedGWh', 'bestCurRate'}));
fprintf(['纯总成本最低：×%g（%.0f MW）、%.2f Mt，%.4g 元/年，失负荷 %.0f GWh/年。\n', ...
    '一倍标准误规则选定：×%g（%.0f MW）、%.2f Mt，%.4g 元/年（高 %.1f%%，标准误 %.1f%%），失负荷 %.0f GWh/年。已写入 %s。\n'], ...
    T.mult(b0), T.pRedMW(b0), T.cKt(b0) / 1e3, T.totalAnnual(b0), T.shedGWh(b0), ...
    T.mult(b), T.pRedMW(b), T.cKt(b) / 1e3, T.totalAnnual(b), 100 * T.dTotal(b) / T.totalAnnual(b0), ...
    100 * T.seDiff(b) / T.totalAnnual(b0), T.shedGWh(b), f);
outDir = fullfile(root, ['select_' char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))]);
mkdir(outDir);
writetable(T, fullfile(outDir, 'designSelect.csv'), 'Encoding', 'UTF-8');
S = plotStyle(p);
setappdata(groot, 'CTDF_keepFigures', true);
try
    F25_designMap(T, p, S, fullfile(outDir, 'F25_designMap'), b0, b);
catch err
    warning('designSelect:fig', '设计图未能绘制：%s', err.message);
end
setappdata(groot, 'CTDF_keepFigures', false);
D = struct('design', design, 'table', T, 'dir', outDir);
end
