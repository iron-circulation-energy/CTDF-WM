function out = referencePolicy(ctx, W, lib, valYears, c, seeds)
%REFERENCEPOLICY M0 参考策略：策略库候选联合策略中验证集平均成本最低的固定基准库存策略（E2 用）。
%   候选集为 lib.candidates（全体同原型 + 随机组合）；每个候选在验证年份 × 种子的常规工况回合上评估，
%   以 的总成本均值为准则选择（只使用验证年份，不接触测试年份）。
%   输出 out：w（所选联合策略）、id、table（各候选的平均成本、断供概率、失负荷、弃电率）、name。

p = ctx.p;
cands = lib.candidates;
nC = size(cands, 2);
specs = makeEvalSpecs(p, valYears, seeds, {'normal'}, c);
meanCost = zeros(nC, 1);
pF = zeros(nC, 1);
shed = zeros(nC, 1);
curR = zeros(nC, 1);
names = cell(nC, 1);
for m = 1:nC
    names{m} = candidateName(lib, cands(:, m));
    ctrl = makeController('fixed', names{m}, jointPolicy(lib, cands(:, m)));
    [~, T] = evalEpisodes(ctx, W, specs, ctrl);
    meanCost(m) = mean(T.cost);
    pF(m) = mean(T.pF);
    shed(m) = mean(T.shedMWh);
    curR(m) = mean(T.curRate);
end
[~, b] = min(meanCost);
out.id = cands(:, b);
out.w = jointPolicy(lib, out.id);
out.name = names{b};
out.table = table(names, meanCost, pF, shed, curR, 'VariableNames', {'Candidate', 'MeanCost', 'pF', 'ShedMWh', 'CurRate'});
end

function s = candidateName(lib, id)
if all(id == id(1)) && id(1) <= numel(lib.names)
    s = lib.names{id(1)};
else
    s = ['mix[' sprintf('%d', id) ']'];
end
end
