function h = softFill(ax, x, lo, hi, col, a)
%SOFTFILL 区间带：在 x 上填充 [lo, hi]（行或列向量均可），颜色 col，透明度 a，无边线，不进入图例。
x = x(:)';
lo = lo(:)';
hi = hi(:)';
ok = isfinite(x) & isfinite(lo) & isfinite(hi);
x = x(ok);
lo = lo(ok);
hi = hi(ok);
if numel(x) < 2
    h = [];
    return;
end
h = fill(ax, [x, fliplr(x)], [lo, fliplr(hi)], col, 'FaceAlpha', a, 'EdgeColor', 'none');
end
