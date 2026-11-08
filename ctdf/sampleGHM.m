function [smp, rawX] = sampleGHM(model, S, c, wEmb, K, rs, params, X0in)
%SAMPLEGHM 从几何时域模型 m^{π_w}(·|s) 采样未来状态。
%   对每个条件 (s_m, w_m) 生成 K 个样本：X_0 ~ m_0，中点法自 t = 0 积分到 1（cfg.nOde 步），
%   物料分量做缩放单纯形欧氏投影（cfg.useTerminalProj 为真时，终端投影），再变换回原始坐标（t）。
%   S：D×M 原始状态；c：1×M 或标量；wEmb：dimW×M；params 缺省时使用 model.ema（目标网络）。
%   X0in（可选）：D×(K·M) 给定源样本（模型坐标，第 (m−1)·K + k 列对应第 m 个条件的第 k 个样本），
%   用于公共随机数比较（分布收缩经验检验）。
%   输出 smp：D×K×M（原始坐标，double）；rawX：D×K×M（终端投影前的模型坐标，供补充表 3、4 的检查）。
%   批量过大时分块计算。

if nargin < 7 || isempty(params)
    params = model.ema;
end
if nargin < 8
    X0in = [];
end
cfg = model.cfg;
meta = model.meta;
norm = model.norm;
n = norm.n;
D = norm.D;
M = size(S, 2);
if isscalar(c)
    c = c * ones(1, M);
end
c = reshape(c, 1, []);
[params, useGPU] = prepareGHMParams(model, params);
prec = cfg.precision;
Xs = toModel(S, c, norm);
cond = [Xs; log(c / norm.cRef)];
condR = repelem(cond, 1, K);
wR = repelem(wEmb, 1, K);
cR = repelem(c, 1, K);
N = M * K;
out = zeros(D, N);
chunk = 8192;
for st = 1:chunk:N
    cols = st:min(N, st + chunk - 1);
    if isempty(X0in)
        X0 = sampleSource(meta, n, norm.matScale, numel(cols), cfg, rs);
    else
        X0 = cast(X0in(:, cols), prec);
    end
    if useGPU
        X0 = gpuArray(X0);
        cc = gpuArray(cast(condR(:, cols), prec));
        ww = gpuArray(cast(wR(:, cols), prec));
    else
        cc = cast(condR(:, cols), prec);
        ww = cast(wR(:, cols), prec);
    end
    X1 = odeMidpoint(params, X0, cc, ww, 1, cfg.nOde, meta, cfg);
    if isa(X1, 'dlarray')
        X1 = extractdata(X1);
    end
    out(:, cols) = double(gather(X1));
end
if nargout > 1
    rawX = reshape(out, D, K, M);
end
if cfg.useTerminalProj
    out(1:n, :) = projectSimplex(out(1:n, :), norm.matScale);
end
Sout = fromModel(out, cR, norm);
smp = reshape(Sout, D, K, M);
end
