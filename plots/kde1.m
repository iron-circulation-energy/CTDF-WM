function f = kde1(x, g, bw)
%KDE1 一维高斯核密度估计（分箱 + 卷积，等距网格 g，不依赖统计工具箱）。
%   f = kde1(x, g)：带宽取 Silverman 规则 0.9·min(σ, IQR/1.34)·n^(−1/5)；f = kde1(x, g, bw) 指定带宽。
%   输出 f 与 g 同尺寸，积分为 1（网格外的样本按截断处理）。

x = double(x(:));
x = x(isfinite(x));
g = double(g(:)');
f = zeros(size(g));
n = numel(x);
if n < 2
    return;
end
if nargin < 3 || isempty(bw)
    q = quantileLin(x, [0.25, 0.75]);
    s = min(std(x), (q(2) - q(1)) / 1.34);
    if s <= 0
        s = max(std(x), eps);
    end
    bw = 0.9 * s * n ^ (-0.2);
end
dg = g(2) - g(1);
idx = round((x - g(1)) / dg) + 1;
idx = idx(idx >= 1 & idx <= numel(g));
cnt = accumarray(idx, 1, [numel(g), 1])';
h = max(1, ceil(4 * bw / dg));
k = exp(-0.5 * ((-h:h) * dg / bw) .^ 2);
f = conv(cnt, k, 'same');
f = f / max(sum(f) * dg, eps);
end
