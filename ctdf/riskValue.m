function rv = riskValue(model, s, c, candEmb, ctx, rs, opts)
%RISKVALUE 候选策略的价值与断供风险。
%   对每个候选 w 从世界模型采样 K 个未来状态 X^(m)：
%     Q̃_w = mean_m r(X^(m)) /(1 − γ)，r(X) 按物理数量与价格权重计算；
%     R_w = mean_m σ(−min_i μ^Fe_i(X^(m)) / ϑ)，σ 为 Sigmoid，ϑ = varthetaDays·mean_i δ̄^D_i；
%   并输出各电厂节点风险 σ(−μ^Fe_i/ϑ) 与各还原站锈阻塞风险 σ(−μ^Ox_j/ϑ_Ox) 的样本均值（分布执行用）。
%   opts.mode = 'ghm'（默认，CTDF-WM / M4）或 'stepwise'（M3：一步模型逐步展开，
%   T ~ Geometric(1 − γ_eval)，截断于 Tcap，每步施加相同的终端投影）。
%   s：D×1 原始状态；candEmb：dimW×C。

if nargin < 7
    opts = struct();
end
K = getf(opts, 'K', model.cfg.K);
mode = getf(opts, 'mode', 'ghm');
C = size(candEmb, 2);
switch mode
    case 'ghm'
        gamma = model.gammaFinal;
        smp = sampleGHM(model, repmat(s, 1, C), c, candEmb, K, rs);      % D×K×C
    case 'stepwise'
        gamma = getf(opts, 'gammaEval', 0.99);
        Tcap = getf(opts, 'Tcap', 200);
        smp = stepwiseRollout(model, s, c, candEmb, K, gamma, Tcap, rs);
    otherwise
        error('riskValue:mode', '未知模式 %s。', mode);
end
D = size(smp, 1);
Sflat = reshape(smp, D, K * C);
prices = getf(opts, 'prices', struct('carbon', s(ctx.L.xi.carbon), 'h2', s(ctx.L.xi.h2)));
r = stateReward(Sflat, ctx, prices);
marginSpec=getf(opts,'marginSpec',ctx.margin);
[muFe, muOx] = computeMargins(Sflat, ctx, marginSpec);
st = ctx.stats;
th = model.cfg.varthetaDays * max(mean(st.deltaDbarP), 1e-6);
thOx = model.cfg.varthetaDays * max(mean(st.deltaUbarR), 1e-6);
sig = @(v) 1 ./ (1 + exp(-v));
riskAll = sig(-min(muFe, [], 1) / th);
rv.Q = mean(reshape(r, K, C), 1) / (1 - gamma);
rv.R = mean(reshape(riskAll, K, C), 1);
nP = size(muFe, 1);
nR = size(muOx, 1);
rv.nodeFe = squeeze(mean(reshape(sig(-muFe / th), nP, K, C), 2));
rv.nodeOx = squeeze(mean(reshape(sig(-muOx / thOx), nR, K, C), 2));
if nP == 1
    rv.nodeFe = reshape(rv.nodeFe, 1, C);
end
if nR == 1
    rv.nodeOx = reshape(rv.nodeOx, 1, C);
end
rv.gamma = gamma;
rv.theta = th;
rv.marginKind = getf(marginSpec,'kind','unspecified_affine');
if getf(opts, 'keepSamples', false)
    rv.samples = smp;
end
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = d;
end
end

function smp = stepwiseRollout(model1, s, c, candEmb, K, gamma, Tcap, rs)
% 逐步推演：从 s 出发，按一步模型连续采样 T 步（T ~ Geometric(1 − γ)，T ≥ 1，截断于 Tcap），取 S_T。
C = size(candEmb, 2);
D = numel(s);
Mtot = C * K;
U = rand(rs, 1, Mtot);
T = 1 + floor(log(max(U, realmin)) / log(gamma));
T = min(max(T, 1), Tcap);
cur = repmat(s, 1, Mtot);
wR = repelem(candEmb, 1, K);
fin = zeros(D, Mtot);
params = prepareGHMParams(model1, model1.ema);
for step = 1:max(T)
    act = T >= step;
    nxt = sampleGHM(model1, cur(:, act), c, wR(:, act), 1, rs, params);
    cur(:, act) = reshape(nxt, D, []);
    done = T == step;
    fin(:, done) = cur(:, done);
end
smp = reshape(fin, D, K, C);
end
