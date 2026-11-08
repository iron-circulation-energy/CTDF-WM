function dg = runDiagGPI2(C, model, lib, ref, lam, years, seed, epDir)
%RUNDIAGGPI2 公共随机数（CRN）决策诊断（只用验证年份，不训练、不改模型参数）。
%   B2 价值排序探针：沿 M0 轨迹（第一个验证年）每隔 12 天取一个状态，用两组独立的公共随机数
%      各估计一次全部候选的 Q̃，报告两次排序的 Spearman 相关（CRN 下的排序可重复性）；
%      并把各状态的 Q̃ 取平均，与候选在验证年上的实际平均成本（M0_selection）的排序比较
%      （模型价值排序是否与真实闭环排序一致）。
%   A2 闭环：验证年 × 常规工况 × 名义循环质量，比较
%      M0        固定参考策略
%      M1crn     集中式 GPI + 公共随机数，每日重选
%      M1crnH    集中式 GPI + 公共随机数，选定后保持 H = ⌈T_loop⌉ 天
%   输出 dg：probe、probeSummary、closed、closedSummary。

p = C.p;
ctx = C.ctx;
W = C.W;
c = C.cNominal;
K = p.ctdf.K;
H = C.Tl.H;
w0 = ref.w;
specs = makeEvalSpecs(p, years, seed, {'normal'}, c);
cands = lib.candidates;
nC = size(cands, 2);
E0 = embeddingsFromIds(lib, cands);
iM0 = find(all(cands == w0.id(:), 1), 1);

% ---------- B2 探针 ----------
probeEvery = 12;
sp = specs(1);
[seg, cap] = buildEvalSegment(ctx, W, sp);
env = IronRustEnv(ctx);
env.reset(sp.seed, sp.c, sp.initSOC, struct('seg', seg, 'capSched', cap, 'initMode', 'deterministic'));
rsA = RandStream('twister', 'Seed', 8001);
rsB = RandStream('twister', 'Seed', 8002);
rows = {};
Qsum = zeros(nC, 1);
nS = 0;
for t = 1:sp.len
    obs = env.getObs();
    if t > sp.warmup && mod(t - sp.warmup, probeEvery) == 1
        rA = riskValueCRN(model, obs.s, obs.c, E0, ctx, rsA, K);
        rB = riskValueCRN(model, obs.s, obs.c, E0, ctx, rsB, K);
        qA = rA.Q(:);
        qB = rB.Q(:);
        qm = (qA + qB) / 2;
        Qsum = Qsum + qm;
        nS = nS + 1;
        [~, ord] = sort(qm, 'descend');
        rk = find(ord == iM0, 1);
        if isempty(rk)
            rk = NaN;
        end
        rows(end + 1, :) = {t - sp.warmup, spearman(qA, qB), std(qm) / max(std(qA - qB) / sqrt(2), eps), rk, ...
            ord(1)}; %#ok<AGROW>
    end
    env.step(policyAct(obs, w0, ctx));
end
dg.probe = cell2table(rows, 'VariableNames', {'day', 'spearmanCRN', 'snrCRN', 'rankM0', 'topIdx'});
trueCost = ref.table.MeanCost(:);
Qbar = Qsum / max(nS, 1);
P = dg.probe;
dg.probeSummary = struct('nStates', height(P), 'medianSpearmanCRN', median(P.spearmanCRN, 'omitnan'), ...
    'medianSNRCRN', median(P.snrCRN, 'omitnan'), 'medianRankM0', median(P.rankM0, 'omitnan'), ...
    'spearmanMeanQvsTrue', spearman(Qbar, -trueCost), 'rankM0byMeanQ', rankOf(Qbar, iM0), 'iM0', iM0, 'nCand', nC);
dg.meanQ = table((1:nC)', Qbar, trueCost, 'VariableNames', {'cand', 'meanQ', 'valCost'});

% ---------- A2 闭环 ----------
vars = struct('name', {'M0', 'M1crn', 'M1crnH'}, ...
    'ctrl', {makeController('fixed', 'M0', w0), ...
    makeController('gpicrn', 'M1crn', model, lib, struct('lambda', lam, 'K', K, 'holdDays', 1)), ...
    makeController('gpicrn', 'M1crnH', model, lib, struct('lambda', lam, 'K', K, 'holdDays', H))});
Tall = {};
for v = 1:numel(vars)
    t0 = tic;
    [~, T] = evalEpisodes(ctx, W, specs, vars(v).ctrl, [], epDir);
    T.variant = repmat({vars(v).name}, height(T), 1);
    Tall{end + 1} = T; %#ok<AGROW>
    fprintf('诊断 A2：%s 完成（%d 回合，%.1f min）。\n', vars(v).name, height(T), toc(t0) / 60);
end
Ecl = vertcat(Tall{:});
dg.closed = Ecl;
nm = {vars.name}';
mcols = {'cost', 'shedMWh', 'eventF', 'pF', 'curRate', 'rustBlockMWh', 'decTime'};
S = zeros(numel(nm), numel(mcols));
for v = 1:numel(nm)
    sel = strcmp(Ecl.variant, nm{v});
    for k = 1:numel(mcols)
        S(v, k) = mean(Ecl.(mcols{k})(sel), 'omitnan');
    end
end
dg.closedSummary = [table(nm, 'VariableNames', {'variant'}), array2table(S, 'VariableNames', mcols)];
end

function k = rankOf(q, i)
[~, ord] = sort(q, 'descend');
k = find(ord == i, 1);
if isempty(k)
    k = NaN;
end
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
