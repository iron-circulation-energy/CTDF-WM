function rv = riskValueCRN(model, s, c, candEmb, ctx, rs, K, opts)
%RISKVALUECRN 公共随机数下的候选价值与断供风险（与 riskValue 同一估计量）。
%   全部候选共用同一组随机数，只改变策略条件 w，因此候选之间的价值差 Q̃_w − Q̃_w′ 中由抽样带来的噪声
%   大部分相互抵消；单个候选的 Q̃ 仍为无偏蒙特卡洛估计。不改变模型与训练，只改变决策时的抽样方式。
%   opts（可选）：
%     mode       'ghm'（缺省，CTDF-WM、无守恒流与各要素对照模型）或 'stepwise'（M3 一步模型逐步展开）
%     X0         D×K 源样本（模型坐标），给出时直接使用（同一日内多次评估共用，见 gpiSelectCRN 分布式模式）
%     gammaEval、Tcap   'stepwise' 模式的折扣与截断步数
%   输出字段与 riskValue 一致：Q、R、nodeFe、nodeOx、gamma、theta；另含 Qk（各公共样本的价值，K×C）。

if nargin < 8
    opts = struct();
end
C = size(candEmb, 2);
cfg = model.cfg;
mode = getf(opts, 'mode', 'ghm');
switch lower(mode)
    case 'ghm'
        X0 = getf(opts, 'X0', []);
        if isempty(X0)
            X0 = sampleSource(model.meta, model.norm.n, model.norm.matScale, K, cfg, rs);   % D×K（模型坐标）
        end
        X0in = repmat(double(gather(X0)), 1, C);                     % 第 (m−1)·K + k 列 = 第 k 个公共样本
        smp = sampleGHM(model, repmat(s, 1, C), c, candEmb, K, rs, [], X0in);   % D×K×C
        gamma = model.gammaFinal;
    case 'stepwise'
        gamma = getf(opts, 'gammaEval', 0.99);
        smp = stepwiseRolloutCRN(model, s, c, candEmb, K, gamma, getf(opts, 'Tcap', 200), rs);
    otherwise
        error('riskValueCRN:mode', '未知模式 %s。', mode);
end
D = size(smp, 1);
Sflat = reshape(smp, D, K * C);
prices = struct('carbon', s(ctx.L.xi.carbon), 'h2', s(ctx.L.xi.h2));
r = stateReward(Sflat, ctx, prices);
[muFe, muOx] = computeMargins(Sflat, ctx, ctx.margin);
st = ctx.stats;
th = cfg.varthetaDays * max(mean(st.deltaDbarP), 1e-6);
thOx = cfg.varthetaDays * max(mean(st.deltaUbarR), 1e-6);
sig = @(v) 1 ./ (1 + exp(-v));
rv.Qk = reshape(r, K, C) / (1 - gamma);             % 各公共样本的价值（K×C），供配对比较的标准误
rv.Q = mean(rv.Qk, 1);
rv.R = mean(reshape(sig(-min(muFe, [], 1) / th), K, C), 1);
nP = size(muFe, 1);
nR = size(muOx, 1);
rv.nodeFe = reshape(mean(reshape(sig(-muFe / th), nP, K, C), 2), nP, C);
rv.nodeOx = reshape(mean(reshape(sig(-muOx / thOx), nR, K, C), 2), nR, C);
rv.gamma = gamma;
rv.theta = th;
end

function smp = stepwiseRolloutCRN(model1, s, c, candEmb, K, gamma, Tcap, rs)
% 逐步推演（公共随机数）：K 条推演的展开步数 T ~ Geometric(1 − γ)（T ≥ 1，截断于 Tcap）与每一步的源样本
% 在全部候选之间共用，只改变策略条件；其余与 riskValue 的 stepwiseRollout 相同。
C = size(candEmb, 2);
D = numel(s);
U = rand(rs, 1, K);
T = 1 + floor(log(max(U, realmin)) / log(gamma));
T = min(max(T, 1), Tcap);
TT = repmat(T, 1, C);                         % 第 (m−1)·K + k 列 = 候选 m 的第 k 条推演
cur = repmat(s, 1, K * C);
wR = repelem(candEmb, 1, K);
fin = zeros(D, K * C);
params = prepareGHMParams(model1, model1.ema);
for step = 1:max(T)
    actK = T >= step;
    act = repmat(actK, 1, C);
    X0 = double(gather(sampleSource(model1.meta, model1.norm.n, model1.norm.matScale, nnz(actK), model1.cfg, rs)));
    X0in = repmat(X0, 1, C);
    nxt = sampleGHM(model1, cur(:, act), c, wR(:, act), 1, rs, params, X0in);
    cur(:, act) = reshape(nxt, D, []);
    done = TT == step;
    fin(:, done) = cur(:, done);
end
smp = reshape(fin, D, K, C);
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = d;
end
end
