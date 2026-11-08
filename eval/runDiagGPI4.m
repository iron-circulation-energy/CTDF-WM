function dg = runDiagGPI4(C, model, lib, ref, yrTrain, seed, epDir3)
%RUNDIAGGPI4 价值误差的成本分项定位（只用训练年，不训练、不改模型参数）。
%   对 16 个候选，比较七个日成本分项（运行、物流、持有、补铁、弃电、失负荷、溢出，元/日）的
%     实测：各候选固定策略在训练年 × 常规工况 × 名义质量上的日均值（读取 diagGPI3 的回合缓存，缺失时重算）；
%     模型：沿 M0 轨迹（训练年，与 diagGPI3 相同的状态）用公共随机数采样未来状态，对应分量的样本均值。
%   报告每个量：两者在候选间的 Spearman 相关、候选间离散度之比（模型/实测）、平均水平之比（模型/实测），
%   以及该分项实测离散度占总成本实测离散度的份额（哪一项决定了候选的好坏）。

p = C.p;
ctx = C.ctx;
W = C.W;
c = C.cNominal;
K = p.ctdf.K;
w0 = ref.w;
cands = lib.candidates;
nC = size(cands, 2);
E0 = embeddingsFromIds(lib, cands);
names = ctx.L.costNames;                 % 运行、物流、持有、补铁、弃电、失负荷、溢出（元/日）
nK = numel(names);

% ---------- 实测分项 ----------
specsTr = makeEvalSpecs(p, yrTrain, seed, {'normal'}, c);
truth = zeros(nC, nK);
costY = zeros(nC, numel(specsTr));
for m = 1:nC
    ctrl = makeController('fixed', sprintf('cand%02d', m), jointPolicy(lib, cands(:, m)));
    Rk = evalEpisodes(ctx, W, specsTr, ctrl, [], epDir3);
    P = zeros(nK, numel(Rk));
    for k = 1:numel(Rk)
        P(:, k) = Rk(k).metrics.costParts(:);
        costY(m, k) = Rk(k).metrics.cost;
    end
    truth(m, :) = mean(P, 2)' / p.exp.evalDays;
end

% ---------- 模型分项 ----------
yrsS = yrTrain(round(linspace(1, numel(yrTrain), min(4, numel(yrTrain)))));
rs = RandStream('twister', 'Seed', 9001);
acc = zeros(nC, nK);
nS = 0;
for y = yrsS(:)'
    sp = makeEvalSpecs(p, y, seed, {'normal'}, c);
    [seg, cap] = buildEvalSegment(ctx, W, sp);
    env = IronRustEnv(ctx);
    env.reset(sp.seed, sp.c, sp.initSOC, struct('seg', seg, 'capSched', cap, 'initMode', 'deterministic'));
    for t = 1:sp.len
        obs = env.getObs();
        if t > sp.warmup && mod(t - sp.warmup, 15) == 1
            X0 = sampleSource(model.meta, model.norm.n, model.norm.matScale, K, model.cfg, rs);
            X0in = repmat(double(gather(X0)), 1, nC);
            smp = sampleGHM(model, repmat(obs.s, 1, nC), obs.c, E0, K, rs, [], X0in);
            Sf = reshape(smp, size(smp, 1), K * nC);
            [~, comp] = physicalQuantityCost(Sf(ctx.L.iZ, :), ctx, obs.s(ctx.L.xi.carbon), obs.s(ctx.L.xi.h2));
            acc = acc + reshape(mean(reshape(comp, nK, K, nC), 2), nK, nC)';
            nS = nS + 1;
        end
        env.step(policyAct(obs, w0, ctx));
    end
end
modelC = acc / max(nS, 1);

% ---------- 汇总 ----------
costT = truth;
tot = sum(costT, 2);
sdTot = std(tot);
rows = cell(nK + 1, 6);
for k = 1:nK
    rows(k, :) = {names{k}, spearman(modelC(:, k), truth(:, k)), std(modelC(:, k)) / max(std(truth(:, k)), eps), ...
        mean(modelC(:, k)) / max(mean(truth(:, k)), eps), std(costT(:, k)) / max(sdTot, eps), mean(truth(:, k))};
end
totM = sum(modelC, 2);
rows(nK + 1, :) = {'total', spearman(totM, tot), std(totM) / max(sdTot, eps), ...
    mean(totM) / max(mean(tot), eps), 1, mean(tot)};
dg.components = cell2table(rows, 'VariableNames', {'component', 'spearman', 'spreadRatio', 'levelRatio', ...
    'shareOfTrueSpread', 'trueDailyMean'});
dg.truth = array2table(truth, 'VariableNames', names);
dg.model = array2table(modelC, 'VariableNames', names);
dg.nStates = nS;
% 改进余地上限：每个训练年事后挑当年最优的候选（按年切换的完美决策者）相对 M0 的节省
iM0 = find(all(cands == w0.id(:), 1), 1);
[bestY, argY] = min(costY, [], 1);
dg.headroom = struct('M0mean', mean(costY(iM0, :)), 'oracleYearMean', mean(bestY), ...
    'savingPct', 100 * (1 - mean(bestY) / mean(costY(iM0, :))), 'fracYearsM0Best', mean(argY == iM0), ...
    'nYears', size(costY, 2));
dg.costByYear = costY;
end

function r = spearman(a, b)
ra = rankv(a);
rb = rankv(b);
a = ra - mean(ra);
b = rb - mean(rb);
r = sum(a .* b) / max(sqrt(sum(a .^ 2) * sum(b .^ 2)), eps);
end

function r = rankv(x)
[~, o] = sort(x(:));
r = zeros(numel(x), 1);
r(o) = 1:numel(x);
end
