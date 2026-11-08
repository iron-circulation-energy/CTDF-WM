function t = twoSlope(v, vmin, vmax)
%TWOSLOPE 以 0 为中心的双斜率归一化：v = vmin → 0，v = 0 → 0.5，v = vmax → 1（截断到 [0, 1]）。
%   用于发散色图在正负范围不对称时保持 0 对应中间色。vmin < 0 < vmax。

t = 0.5 * ones(size(v));
neg = v < 0;
t(neg) = 0.5 * (1 - v(neg) / vmin);
pos = v > 0;
t(pos) = 0.5 + 0.5 * v(pos) / vmax;
t = min(1, max(0, t));
end
