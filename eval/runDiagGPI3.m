function dg = runDiagGPI3(C, model, lib, ref, lam, yrTrain, yrVal, seed, epDir)
%RUNDIAGGPI3 价值校准诊断：训练年标定、验证年检验（不训练、不改模型参数）。
%   校准（只用训练年）：
%     Q^true_w  各候选固定策略在训练年 × 常规工况 × 名义质量上的实际平均日成本，换算为与 Q̃ 同口径的价值
%               −(日均成本 / C_ref) / (1 − γ)；
%     Q̄^mod_w   沿 M0 轨迹（训练年）取的状态上，CTDF-WM 用公共随机数估计的 Q̃_w 的平均；
%     b_w = Q^true_w − Q̄^mod_w。决策时取 argmax_w [Q̃_w(s) + b_w]：各候选的价值水平由训练年实测确定，
%     世界模型只负责随状态变化的相对优劣（控制变量校准）。
%   检验（只用验证年）：M0、M1cal（每日重选）、M1calH（保持 H 天）。
%   并报告：训练年实测排序与验证年实测排序的一致性、校准前模型平均价值与训练年实测排序的一致性。

p = C.p;
ctx = C.ctx;
W = C.W;
c = C.cNominal;
K = p.ctdf.K;
H = C.Tl.H;
w0 = ref.w;
cands = lib.candidates;
nC = size(cands, 2);
E0 = embeddingsFromIds(lib, cands);
gamma = model.gammaFinal;

% ---------- 1 训练年实测 ----------
t0 = tic;
specsTr = makeEvalSpecs(p, yrTrain, seed, {'normal'}, c);
costTr = zeros(nC, 1);
for m = 1:nC
    ctrl = makeController('fixed', sprintf('cand%02d', m), jointPolicy(lib, cands(:, m)));
    [~, T] = evalEpisodes(ctx, W, specsTr, ctrl, [], epDir);
    costTr(m) = mean(T.cost) / p.exp.evalDays;
end
Qtrue = -(costTr / ctx.Cref) / (1 - gamma);
fprintf('诊断 3：训练年实测完成（%d 候选 × %d 年，%.1f min）。\n', nC, numel(yrTrain), toc(t0) / 60);

% ---------- 2 训练年状态上的模型平均价值 ----------
t0 = tic;
yrsS = yrTrain(round(linspace(1, numel(yrTrain), min(4, numel(yrTrain)))));
rsS = RandStream('twister', 'Seed', 9001);
Qsum = zeros(nC, 1);
nS = 0;
for y = yrsS(:)'
    sp = makeEvalSpecs(p, y, seed, {'normal'}, c);
    [seg, cap] = buildEvalSegment(ctx, W, sp);
    env = IronRustEnv(ctx);
    env.reset(sp.seed, sp.c, sp.initSOC, struct('seg', seg, 'capSched', cap, 'initMode', 'deterministic'));
    for t = 1:sp.len
        obs = env.getObs();
        if t > sp.warmup && mod(t - sp.warmup, 15) == 1
            rv = riskValueCRN(model, obs.s, obs.c, E0, ctx, rsS, K);
            Qsum = Qsum + rv.Q(:);
            nS = nS + 1;
        end
        env.step(policyAct(obs, w0, ctx));
    end
end
Qmod = Qsum / max(nS, 1);
b = Qtrue - Qmod;
fprintf('诊断 3：模型平均价值完成（%d 个状态，%.1f min）。\n', nS, toc(t0) / 60);
valCost = ref.table.MeanCost(:);
dg.calib = table((1:nC)', costTr, Qtrue, Qmod, b, valCost, 'VariableNames', ...
    {'cand', 'trainDailyCost', 'Qtrue', 'Qmod', 'offset', 'valEpisodeCost'});
dg.calibSummary = struct('nStates', nS, 'spearmanTrainVsVal', spearman(-costTr, -valCost), ...
    'spearmanQmodVsTrain', spearman(Qmod, Qtrue), 'rankM0Train', rankOf(Qtrue, find(all(cands == w0.id(:), 1), 1)), ...
    'scaleQtrue', std(Qtrue), 'scaleQmod', std(Qmod));

% ---------- 3 验证年闭环 ----------
specsV = makeEvalSpecs(p, yrVal, seed, {'normal'}, c);
vars = struct('name', {'M0', 'M1cal', 'M1calH'}, ...
    'ctrl', {makeController('fixed', 'M0', w0), ...
    makeController('gpicrn', 'M1cal', model, lib, struct('lambda', lam, 'K', K, 'holdDays', 1, 'offset', b')), ...
    makeController('gpicrn', 'M1calH', model, lib, struct('lambda', lam, 'K', K, 'holdDays', H, 'offset', b'))});
Tall = {};
for v = 1:numel(vars)
    t0 = tic;
    [~, T] = evalEpisodes(ctx, W, specsV, vars(v).ctrl, [], epDir);
    T.variant = repmat({vars(v).name}, height(T), 1);
    Tall{end + 1} = T; %#ok<AGROW>
    fprintf('诊断 3：%s 完成（%d 回合，%.1f min）。\n', vars(v).name, height(T), toc(t0) / 60);
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
dg.offset = b;
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
