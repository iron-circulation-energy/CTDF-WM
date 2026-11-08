function dg = runDiagSizing(C, years, seed, mults, epRoot, cList)
%RUNDIAGSIZING 还原功率规模扫描：把各还原站电解 + 还原总功率乘以 mults，重建算例后在验证年上评估全部候选固定策略
%   （常规工况、原名义循环质量），报告每个规模下验证成本最低的候选及其失负荷、断供与弃电，并给出全部候选的均值。
%   cList（可选，t）：循环质量网格，缺省只用原名义质量；给出时扫描 还原功率 × 循环质量 的全部组合。
%   只评估固定策略，不训练、不改已训练模型；用于判断失负荷由充能（还原）能力还是循环质量限制。

p0 = C.p;
if nargin < 6 || isempty(cList)
    cList = C.cNominal;
end
rows = {};
for k = 1:numel(mults)
  for c = cList(:)'
    t0 = tic;
    pv = p0;
    pv.station.pRedMax = mults(k) * p0.station.pRedMax;
    pv = deriveParams(pv);
    Cv = buildCase(pv, C.W);
    lib = policyLibrary(pv, Cv.topo, Cv.stats, pv.seed);
    cands = lib.candidates;
    nC = size(cands, 2);
    specs = makeEvalSpecs(pv, years, seed, {'normal'}, c);
    epDir = fullfile(epRoot, sprintf('x%g', mults(k)));       % 回合文件名含 c，不同质量可共用目录
    M = zeros(nC, 6);
    for m = 1:nC
        ctrl = makeController('fixed', sprintf('cand%02d', m), jointPolicy(lib, cands(:, m)));
        [~, T] = evalEpisodes(Cv.ctx, Cv.W, specs, ctrl, [], epDir);
        M(m, :) = [mean(T.cost), mean(T.shedMWh), mean(T.eventF, 'omitnan'), mean(T.pF), mean(T.curRate), ...
            mean(T.rustBlockMWh)];
    end
    [~, b] = min(M(:, 1));
    rows(end + 1, :) = {mults(k), c / 1e3, sum(pv.station.pRedMax), sum(pv.station.rhoMax), M(b, 1), M(b, 2), M(b, 3), ...
        M(b, 4), M(b, 5), M(b, 6), mean(M(:, 1)), mean(M(:, 2)), b}; %#ok<AGROW>
    fprintf('规模 ×%g、质量 %.0f kt：最优候选 %d，成本 %.4g 元，失负荷 %.4g MWh（%.1f min）。\n', mults(k), c / 1e3, b, ...
        M(b, 1), M(b, 2), toc(t0) / 60);
  end
end
dg.table = cell2table(rows, 'VariableNames', {'mult', 'cKt', 'pRedMW', 'rhoMaxTpd', 'bestCost', 'bestShedMWh', 'bestEventF', ...
    'bestPF', 'bestCurRate', 'bestRustBlockMWh', 'meanCost', 'meanShedMWh', 'bestCand'});
end
