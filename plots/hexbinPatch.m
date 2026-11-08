function [h, cnt] = hexbinPatch(ax, x, y, nx, ny, xl, yl)
%HEXBINPATCH 六边形分箱密度图（与 matplotlib hexbin 的网格定义一致，不依赖工具箱）。
%   nx、ny 为横、纵向六边形个数，xl、yl 为范围；颜色为 log10(计数)（使用坐标轴当前色图，CDataMapping 为 scaled），
%   边线白色。输出 patch 句柄与各六边形计数。

x = double(x(:));
y = double(y(:));
ok = isfinite(x) & isfinite(y) & x >= xl(1) & x <= xl(2) & y >= yl(1) & y <= yl(2);
x = x(ok);
y = y(ok);
sx = (xl(2) - xl(1)) / nx;
sy = (yl(2) - yl(1)) / ny;
xs = (x - xl(1)) / sx;
ys = (y - yl(1)) / sy;
ix1 = round(xs);
iy1 = round(ys);
ix2 = floor(xs);
iy2 = floor(ys);
d1 = (xs - ix1) .^ 2 + 3 * (ys - iy1) .^ 2;
d2 = (xs - ix2 - 0.5) .^ 2 + 3 * (ys - iy2 - 0.5) .^ 2;
use1 = d1 < d2;
cx = (ix2 + 0.5) * sx + xl(1);
cy = (iy2 + 0.5) * sy + yl(1);
cx(use1) = ix1(use1) * sx + xl(1);
cy(use1) = iy1(use1) * sy + yl(1);
[C, ~, j] = unique([cx, cy], 'rows');
cnt = accumarray(j, 1);
ox = sx * [0.5, 0.5, 0, -0.5, -0.5, 0];
oy = sy / 3 * [-0.5, 0.5, 1, 0.5, -0.5, -1];
nH = size(C, 1);
V = zeros(6 * nH, 2);
F = reshape(1:6 * nH, 6, nH)';
for k = 1:6
    V(k:6:end, :) = [C(:, 1) + ox(k), C(:, 2) + oy(k)];
end
h = patch(ax, 'Faces', F, 'Vertices', V, 'FaceVertexCData', log10(cnt), 'FaceColor', 'flat', ...
    'EdgeColor', 'w', 'LineWidth', 0.2, 'CDataMapping', 'scaled');
end
