function [Z, xc, yc] = kde2(x, y, xe, ye, bw)
%KDE2 二维高斯核密度估计（二维直方图 + 可分离高斯平滑，不依赖统计工具箱）。
%   x、y 为样本；xe、ye 为等距分箱边界；bw = [bx, by] 为带宽（缺省按各维 Silverman 规则）。
%   输出 Z（numel(yc)×numel(xc)，可直接用于 contour(xc, yc, Z)），xc、yc 为分箱中心。

x = double(x(:));
y = double(y(:));
ok = isfinite(x) & isfinite(y);
x = x(ok);
y = y(ok);
n = numel(x);
if nargin < 5 || isempty(bw)
    bw = [0.9 * std(x) * n ^ (-1 / 6), 0.9 * std(y) * n ^ (-1 / 6)];
end
N = histcounts2(x, y, xe, ye);          % numel(xc)×numel(yc)
dx = xe(2) - xe(1);
dy = ye(2) - ye(1);
hx = max(1, ceil(4 * bw(1) / dx));
hy = max(1, ceil(4 * bw(2) / dy));
kx = exp(-0.5 * ((-hx:hx)' * dx / bw(1)) .^ 2);
ky = exp(-0.5 * ((-hy:hy) * dy / bw(2)) .^ 2);
Z = conv2(kx, ky, N, 'same')';          % 转置为 行 = y
Z = Z / max(sum(Z(:)) * dx * dy, eps);
xc = (xe(1:end - 1) + xe(2:end)) / 2;
yc = (ye(1:end - 1) + ye(2:end)) / 2;
end
