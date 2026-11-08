function q = quantileLin(x, pr)
%QUANTILELIN 线性插值分位数（R type 7 规则，即 h = (n − 1)·p + 1；与 MATLAB quantile 的默认规则不同），不依赖统计工具箱。
%   x 为向量，pr 为概率（标量或向量，取值 0~1）。空向量返回 NaN。

x = sort(x(:));
x = x(~isnan(x));
n = numel(x);
q = nan(size(pr));
if n == 0
    return;
end
for m = 1:numel(pr)
    h = (n - 1) * pr(m) + 1;
    lo = floor(h);
    hi = ceil(h);
    lo = min(max(lo, 1), n);
    hi = min(max(hi, 1), n);
    if lo == hi || x(lo) == x(hi)
        q(m) = x(lo);
    elseif isinf(x(hi))
        q(m) = x(hi);
    else
        q(m) = x(lo) + (h - lo) * (x(hi) - x(lo));
    end
end
end
