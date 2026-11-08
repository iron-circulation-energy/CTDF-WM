function F04_reLoadJoint(W, p, S, outBase)
%F04_RELOADJOINT 图 F04：风光日电量与负荷日电量的联合分布（分季节；联合核密度 + 边缘密度；模板 5 左上）。
%   等值线为最高密度区域（包含 25%、50%、75%、90% 概率质量），浅赭色区为低风光区（< regLow × 全部日均值）。

w = p.weather;
Y = numel(W);
mth = month(datetime(2001, 1, 1) + caldays(0:364));
re = zeros(1, 365 * Y);
ld = re;
mo = re;
for y = 1:Y
    k = (y - 1) * 365 + (1:365);
    re(k) = (W(y).EW(1:365) + W(y).ES(1:365)) / 1e3;
    ld(k) = W(y).EL(1:365) / 1e3;
    mo(k) = mth;
end
grp = {ismember(mo, [12, 1, 2]), lab(S, '冬季（12—2 月）', 'Winter, Dec–Feb'), S.slate; ismember(mo, 6:8), ...
    lab(S, '夏季（6—8 月）', 'Summer, Jun–Aug'), S.accent; ~ismember(mo, [12, 1, 2, 6, 7, 8]), lab(S, '春秋季', 'Spring and autumn'), S.teal};
xl = [0, 1.05 * quantileLin(re, 0.999)];
qy = quantileLin(ld, [0.001, 0.999]);
yl = qy + [-1, 1] * 0.08 * diff(qy);
gx = linspace(xl(1), xl(2), 200);
gy = linspace(yl(1), yl(2), 200);
fig = styledFigure(S, 5.8, 5.2);
ax = axes(fig, 'Position', [0.12, 0.10, 0.64, 0.66]);
at = axes(fig, 'Position', [0.12, 0.77, 0.64, 0.15]);
ar = axes(fig, 'Position', [0.77, 0.10, 0.15, 0.66]);
hold(ax, 'on');
hold(at, 'on');
hold(ar, 'on');
xLow = w.regLow * mean(re);
fill(ax, [xl(1), xLow, xLow, xl(1)], [yl(1), yl(1), yl(2), yl(2)], [0.95, 0.91, 0.87], 'EdgeColor', 'none');
text(ax, xl(1) + 0.01 * diff(xl), yl(2) - 0.02 * diff(yl), sprintf(lab(S, '低风光区（< %.1f 倍均值）', 'low-renewable zone, < %.1f × mean'), w.regLow), ...
    'VerticalAlignment', 'top', 'FontSize', S.fs - 1, 'Color', [0.61, 0.29, 0.20]);
h = gobjects(1, 3);
for g = 1:3
    sel = grp{g, 1};
    c = grp{g, 3};
    scatter(ax, re(sel), ld(sel), 2, c, 'filled', 'MarkerFaceAlpha', 0.18, 'MarkerEdgeColor', 'none');
    [Z, xc, yc] = kde2(re(sel), ld(sel), linspace(xl(1), xl(2), 121), linspace(yl(1), yl(2), 121));
    lv = hdrLevels(Z, [0.25, 0.5, 0.75, 0.9]);
    for j = 1:numel(lv)
        contour(ax, xc, yc, Z, [lv(j), lv(j)], 'LineColor', c, 'LineWidth', 0.6 + 0.25 * j);
    end
    fx = kde1(re(sel), gx);
    fy = kde1(ld(sel), gy);
    fill(at, [gx, fliplr(gx)], [fx, zeros(size(fx))], c, 'FaceAlpha', 0.2, 'EdgeColor', 'none');
    plot(at, gx, fx, '-', 'Color', c, 'LineWidth', 1.1);
    fill(ar, [fy, zeros(size(fy))], [gy, fliplr(gy)], c, 'FaceAlpha', 0.2, 'EdgeColor', 'none');
    plot(ar, fy, gy, '-', 'Color', c, 'LineWidth', 1.1);
    h(g) = scatter(ax, nan, nan, 28, c, 'filled');
end
legend(ax, h, grp(:, 2), 'Location', 'northeast', 'Box', 'off');
xlim(ax, xl);
ylim(ax, yl);
styleAxes(ax, S, true, true);
xlabel(ax, lab(S, '西部风光日电量/(GWh/d)', 'Daily renewable energy (GWh d^{-1})'));
ylabel(ax, lab(S, '负荷日电量/(GWh/d)', 'Daily load (GWh d^{-1})'));
xlim(at, xl);
ylim(ar, yl);
axis(at, 'off');
axis(ar, 'off');
addNote(fig, S, '');
saveFigure(fig, outBase);
end
