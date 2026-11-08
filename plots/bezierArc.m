function P = bezierArc(p0, p1, bend, n)
%BEZIERARC 二次贝塞尔弧线：起点 p0、终点 p1（1×2），控制点位于中点沿法向偏移 bend·|p1 − p0|，n 个点（缺省 60）。
%   bend 的符号决定弧线弯向（从 p0 指向 p1 的左侧为正）。

if nargin < 4
    n = 60;
end
p0 = p0(:)';
p1 = p1(:)';
d = p1 - p0;
c = (p0 + p1) / 2 + bend * [-d(2), d(1)];
t = linspace(0, 1, n)';
P = (1 - t) .^ 2 .* p0 + 2 * (1 - t) .* t .* c + t .^ 2 .* p1;
end
