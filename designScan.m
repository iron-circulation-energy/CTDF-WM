function D = designScan(pMults, cMasses, merge)
%DESIGNSCAN 重训前的设计点选取（预先约定的规则，只用固定候选策略与验证年，不训练）。
%   D = designScan()                 还原功率倍数 0.75、1、1.25、1.5（相对基准各站功率）× 循环质量 1.0—3.0 Mt
%   D = designScan(pMults, cMasses)  自定义网格
%   D = designScan(pMults, cMasses, merge)  并入此前扫描的结果后在全部组合中选取（merge 为时间戳或 designScan.csv 路径，
%                                    可为元胞数组；同一组合以本次结果为准）。用于设计点落在网格边界时向外扩展网格。
%   规则：每个组合在验证年（常规工况）上评估全部候选固定策略，取验证成本最低者的运行成本；
%         年化总成本 = 运行成本（折算到年）+ 充能侧投资年金与运维（电解槽、还原厂、料仓）+ 循环铁资金成本（c·铁粉单价·r），
%         取年化总成本最低的组合为设计点，写入 config/design_point.mat（params_paper 读取）。
%   参数（如 κ）改变后须重新运行；设计点位于网格边界时给出警告，应扩展网格后重跑。约 0.5—1.5 h。
%   输出图 F25（补充图 20）：充能功率 × 循环质量的年化总成本与失负荷，设计点以红框标出。
setupPaths();
if nargin < 1 || isempty(pMults)
    pMults = [0.75, 1, 1.25, 1.5];
end
if nargin < 2 || isempty(cMasses)
    cMasses = [1.0, 1.5, 2.0, 2.5, 3.0] * 1e6;
end
p = params_paper();
% 回到基准还原功率（params_paper 已按旧设计点放大时先还原）
p.station.pRedMax = p.station.pRedMax / p.design.pMult;
p.design.pMult = 1;
p = deriveParams(p);
C = buildCase(p);
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
outDir = fullfile(p.exp.resultsRoot, 'designScan', stamp);
if ~exist(outDir, 'dir'), mkdir(outDir); end
fprintf('设计点扫描：还原功率倍数 %s × 循环质量 %s Mt，κ = %.2f，验证年 %s。\n', mat2str(pMults), ...
    mat2str(cMasses / 1e6), p.station.kappa(1), mat2str(p.weather.val));
dg = runDiagSizing(C, p.weather.val, p.exp.seeds(1), pMults, fullfile(outDir, 'episodes'), cMasses);
T = dg.table;
r = p.retire.discount;
crf = r / (1 - (1 + r) ^ (-p.station.life));
yr = 365 / p.exp.evalDays;
kW = 1e3;
n = height(T);
T.opAnnual = T.bestCost * yr;
T.chargeCapexAnnual = zeros(n, 1);
T.ironCapitalAnnual = T.cKt * 1e3 * p.iron.price * r;
for k = 1:n
    pv = p;
    pv.station.pRedMax = T.mult(k) * p.station.pRedMax;
    pv = deriveParams(pv);
    eRed = pv.iron.hFe * pv.station.kappa(:) ./ pv.station.etaEl(:) + pv.station.epsAux(:);
    elShare = (pv.station.kappa(:) ./ pv.station.etaEl(:)) * pv.iron.hFe ./ eRed;
    capEl = pv.station.capexElPerKw * sum(pv.station.pRedMax(:) .* elShare) * kW;
    capRed = pv.station.capexRedPerKwFe * sum(pv.station.rhoMax(:) * pv.iron.hFe / 24) * kW;
    capInv = [pv.plant.capFe(:); pv.plant.capOx(:); pv.station.capFe(:); pv.station.capOx(:); pv.hub.capFe(:); pv.hub.capOx(:)];
    capSilo = pv.retire.siloCapexPerT * sum(capInv);
    T.chargeCapexAnnual(k) = (capEl + capRed + capSilo) * (crf + pv.retire.opexFrac);
end
T.totalAnnual = T.opAnnual + T.chargeCapexAnnual + T.ironCapitalAnnual;
if nargin >= 3 && ~isempty(merge)
    if ~iscell(merge), merge = {merge}; end
    for q = 1:numel(merge)
        fq = merge{q};
        if ~endsWith(fq, '.csv')
            fq = fullfile(p.exp.resultsRoot, 'designScan', fq, 'designScan.csv');
        end
        T0 = readtable(fq);
        T0 = T0(:, T.Properties.VariableNames);
        keep = ~ismember([T0.mult, T0.cKt], [T.mult, T.cKt], 'rows');
        T = [T; T0(keep, :)]; %#ok<AGROW>
        fprintf('并入 %s 的 %d 个组合。\n', fq, nnz(keep));
    end
    T = sortrows(T, {'mult', 'cKt'});
    pMults = unique(T.mult)';
    cMasses = unique(T.cKt)' * 1e3;
end
[~, b] = min(T.totalAnnual);
design = struct('pMult', T.mult(b), 'cNominal', T.cKt(b) * 1e3, 'kappa', p.station.kappa(1), ...
    'rule', 'validation years, fixed candidates, min operating + annualised charging capex + iron capital', ...
    'stamp', stamp, 'totalAnnual', T.totalAnnual(b));
writetable(T, fullfile(outDir, 'designScan.csv'), 'Encoding', 'UTF-8');
f = fullfile(fileparts(mfilename('fullpath')), 'config', 'design_point.mat');
save(f, 'design', 'T');
disp(T(:, {'mult', 'cKt', 'pRedMW', 'bestShedMWh', 'bestCurRate', 'opAnnual', 'chargeCapexAnnual', 'ironCapitalAnnual', 'totalAnnual'}));
fprintf('设计点：还原功率 ×%g（%.0f MW），循环质量 %.2f Mt；年化总成本 %.4g 元。已写入 %s。\n', design.pMult, ...
    T.pRedMW(b), design.cNominal / 1e6, design.totalAnnual, f);
if T.mult(b) == min(pMults) || T.mult(b) == max(pMults) || T.cKt(b) * 1e3 == min(cMasses) || T.cKt(b) * 1e3 == max(cMasses)
    warning('designScan:edge', '设计点位于扫描网格边界，应扩展该方向的网格后重跑 designScan。');
end
D = struct('design', design, 'table', T, 'dir', outDir);
try
    S = plotStyle(p);
    setappdata(groot, 'CTDF_keepFigures', true);       % 设计图保存后保持显示
    F25_designMap(T, p, S, fullfile(outDir, 'F25_designMap'));
    setappdata(groot, 'CTDF_keepFigures', false);
catch err
    setappdata(groot, 'CTDF_keepFigures', false);
    warning('designScan:fig', '设计图未能绘制：%s', err.message);
end
end
