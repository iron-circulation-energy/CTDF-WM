function M = natMonteCarlo(n, N, Cl, R)
%NATMONTECARLO 全国评估最优路线排序对改造投资、每循环损耗、还原氢耗与储存设施投资联合不确定性的稳健性。
%   M = natMonteCarlo(n, N, Cl, R)；R 为基准 natAssess 结果。
%   在 n.mc 给出的区间内独立均匀抽取 n.mc.draws 组参数（随机流 mt19937ar，种子 n.mc.seed）：
%     改造投资比例 n.mc.retrofitFrac（同时作用于铁与氨路线的煤电改造）、每循环铁损耗 n.mc.loss、
%     还原氢耗 κ n.mc.kappa、铁粉储存设施投资 n.mc.siloPerT。
%   每组参数作为一个情景交给 natAssess（与情景分析相同的储能服务口径，服务按基准参考效率计算一次后复用），
%   结果写入 n.outDir/mc 子目录，不覆盖基准结果。
%   M.prov  逐省：基准最优路线、与基准相同的比例 pSame、铁燃料路线（FeL/FeX/FeT）最优的比例 pIron、绿氨最优的比例 pNH3
%   M.draws 逐抽样：参数与汇总（铁燃料最优省数、循环铁总量、可保留资产价值）
%   结果按 n.mc 与年份缓存在 n.outDir/national_mc.mat，参数与年份不变时直接读取。

cacheFile = fullfile(n.outDir, 'national_mc.mat');
key = struct('mc', n.mc, 'years', Cl.years(:)', 'base', R.winners(:, 1)', 'version', 3);   % version 3：重庆、西藏借用相邻省份风电代表点
if isfile(cacheFile)
    try
        L = load(cacheFile, 'M');
        if isfield(L.M, 'key') && isequaln(L.M.key, key)
            M = L.M;
            fprintf('蒙特卡洛结果沿用缓存（%d 组抽样）。\n', height(M.draws));
            return;
        end
    catch
    end
end
c = n.mc;
rs = RandStream('mt19937ar', 'Seed', c.seed);
u = rand(rs, c.draws, 4);
pick = @(rg, v) rg(1) + (rg(2) - rg(1)) * v;
frac = pick(c.retrofitFrac, u(:, 1));
loss = pick(c.loss, u(:, 2));
kappa = pick(c.kappa, u(:, 3));
silo = pick(c.siloPerT, u(:, 4));
sc = struct('name', {}, 'label', {}, 'set', {});
for k = 1:c.draws
    sc(k).name = sprintf('mc%03d', k);
    sc(k).label = sc(k).name;
    sc(k).set = {'fe.capRetro', frac(k) * n.coal.capex, 'nh3.capRetro', frac(k) * n.coal.capex, ...
        'fe.loss', loss(k), 'fe.kappa', kappa(k), 'fe.siloPerT', silo(k)};
end
nm = n;
nm.scenarios = sc;
nm.outDir = fullfile(n.outDir, 'mc');
nm.quiet = true;
nm.portfolio.enable = false;                       % 蒙特卡洛只检验单一路线排序，组合优化只在设定情景中求解
fprintf('蒙特卡洛：%d 组参数抽样（改造比例、损耗、还原氢耗、储存设施投资）。\n', c.draws);
Rm = natAssess(nm, N, Cl);
W = Rm.winners;
base = R.winners(:, 1);
iron = W == "FeL" | W == "FeX" | W == "FeT";
M.prov = table(R.T.name, R.T.short, base, mean(W == base, 2), mean(iron, 2), mean(W == "NH3L", 2), ...
    'VariableNames', {'name', 'short', 'baseWinner', 'pSame', 'pIron', 'pNH3'});
s = Rm.scen;
M.draws = table(frac, loss, kappa, silo, s.nFe, s.nNH3L, s.nH2S + s.nH2T, s.MtTotal, s.assetBn, ...
    'VariableNames', {'retrofitFrac', 'loss', 'kappa', 'siloPerT', 'nFe', 'nNH3', 'nH2', 'MtTotal', 'assetBn'});
q = @(x) quantile(x, [0.05, 0.5, 0.95]);
M.nFeQ = q(M.draws.nFe);
M.assetQ = q(M.draws.assetBn);
M.MtQ = q(M.draws.MtTotal);
M.key = key;
writetable(M.prov, fullfile(n.outDir, 'national_mc_provinces.csv'), 'Encoding', 'UTF-8');
writetable(M.draws, fullfile(n.outDir, 'national_mc_draws.csv'), 'Encoding', 'UTF-8');
save(cacheFile, 'M');
fprintf(['蒙特卡洛（%d 组）：铁燃料路线最优省数 %.0f（5%%—95%%：%.0f—%.0f）；', ...
    '最优路线与基准一致的省份比例中位数 %.0f%%；可保留资产价值 %.0f 亿元（%.0f—%.0f）。\n'], ...
    c.draws, M.nFeQ(2), M.nFeQ(1), M.nFeQ(3), 100 * median(M.prov.pSame), M.assetQ(2), M.assetQ(1), M.assetQ(3));
end
