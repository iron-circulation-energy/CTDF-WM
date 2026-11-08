function N05_capacityCheck(R, S, outBase)
%N05_CAPACITYCHECK 补充图 18：各省事件缓冲质量与多年循环库存的对照（t 铁/MW 改造容量，对数坐标）。
%   横轴：序列峰值储能能量折算的铁库存 + 在途量（多年累计亏欠）；纵轴：事件缓冲质量（单次最长事件）；
%   颜色为低风光日频率；对角线为 1:1，阴影为 ±25%。

T = R.T;
pk = cellfun(@(t) t.peakFe, R.info.th);
x = cellfun(@(t) t.Msp, R.info.th) ./ pk;
y = cellfun(@(t) t.Mevent, R.info.th) ./ pk;
fig = styledFigure(S, 6.4, 5.2);
ax = axes(fig, 'Position', [0.12, 0.13, 0.70, 0.82]);
hold(ax, 'on');
% 坐标范围收紧到数据所在区间（对数坐标两侧各留余量），使各省点位与标注分开
xl = [min(x) / 1.2, max(x) * 1.5];
yl = [min(y) / 1.3, max(y) * 1.3];
g = [min(xl(1), yl(1)), max(xl(2), yl(2))];
fill(ax, [g, fliplr(g)], [0.75 * g, fliplr(1.25 * g)], S.grid, 'EdgeColor', 'none');
plot(ax, g, g, '--', 'Color', S.axis, 'LineWidth', 0.9);
lf = T.lowFreq;
cl = [min(lf), max(lf)];
if diff(cl) <= 0
    cl = cl + [-0.01, 0.01];
end
scatter(ax, x, y, 40, lf, 'filled', 'MarkerEdgeColor', [1, 1, 1], 'LineWidth', 0.5);
% 标注避让：按纵向对数位置排序，横向相近的标注之间保持最小间距，移动后以细线连回点位
lx = log10(x(:));
ly = log10(y(:));
ty = ly;
dy = 0.045 * diff(log10(yl));
dx = 0.22 * diff(log10(xl));
[~, o] = sort(ly);
for it = 1:60
    moved = false;
    for a = 1:numel(o)
        i = o(a);
        for b = 1:a - 1
            j = o(b);
            if abs(lx(i) - lx(j)) < dx && abs(ty(i) - ty(j)) < dy
                ty(i) = ty(j) + dy;
                moved = true;
            end
        end
    end
    if ~moved, break; end
end
for i = 1:height(T)
    tx = 10 ^ (lx(i) + 0.012 * diff(log10(xl)));
    if abs(ty(i) - ly(i)) > 1e-9
        plot(ax, [x(i), tx], [y(i), 10 ^ ty(i)], '-', 'Color', [0.75, 0.75, 0.75], 'LineWidth', 0.4);
    end
    text(ax, tx, 10 ^ ty(i), [' ', char(provEnglish(T.short(i)))], 'FontSize', S.fs - 2.4, 'Color', S.tick, ...
        'VerticalAlignment', 'middle');
end
set(ax, 'XScale', 'log', 'YScale', 'log');
xlim(ax, xl);
ylim(ax, yl);
styleAxes(ax, S, true, true);
xlabel(ax, lab(S, '序列峰值库存 + 在途量/(t·MW^{-1})', 'Multi-year inventory (t MW^{-1})'));
ylabel(ax, lab(S, '事件缓冲质量/(t·MW^{-1})', 'Event-buffer mass (t MW^{-1})'));
colormap(ax, S.seq);
clim(ax, cl);
cb = colorbar(ax);
cb.Position = [0.86, 0.25, 0.022, 0.55];
styleColorbar(cb, S, lab(S, '低风光日频率', 'Low-renewable day share'));
r = median(T.thmRatio);
text(ax, 0.03, 0.96, sprintf(lab(S, '事件缓冲 / 多年库存 中位数 %.2f', 'median ratio %.2f'), r), 'Units', 'normalized', 'FontSize', S.fs - 0.5, 'Color', S.ink, 'VerticalAlignment', 'top');
addNote(fig, S, lab(S, '每 MW 改造容量；阴影为 ±25%', 'Per MW of retrofit capacity; band ±25%'));
saveFigure(fig, outBase);
end
