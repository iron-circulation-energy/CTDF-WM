function F25_designMap(T, p, S, outBase, bMin, bSel, target)
%F25_DESIGNMAP 补充图 20：充能功率 × 循环质量的设计图（单图，designScan 的结果）。
%   色块为年化总成本（运行成本 + 充能侧投资年金 + 循环铁资金成本，亿元/年），格内数字为最优固定策略的年失负荷（GWh）；
%   红框为选定的设计点（designSelect：一倍标准误内取失负荷最小），虚线框为纯总成本最低点。功率不足时增加质量几乎不降失负荷（质量以锈积压于还原站），
%   功率足够后增加质量才缩短缺铁，二者互补。
pm = unique(T.mult);
cs = unique(T.cKt);
Z = nan(numel(pm), numel(cs));
U = Z;
PR = Z;
yr = 365 / p.exp.evalDays;
for k = 1:height(T)
    i = find(pm == T.mult(k));
    j = find(cs == T.cKt(k));
    Z(i, j) = T.totalAnnual(k) / 1e8;
    U(i, j) = T.bestShedMWh(k) * yr / 1e3;
    PR(i, j) = T.pRedMW(k);
end
if nargin < 7
    target = [];
end
if nargin < 5 || isempty(bMin)
    [~, bMin] = min(T.totalAnnual);
end
if nargin < 6 || isempty(bSel)
    bSel = bMin;
end
ib = find(pm == T.mult(bSel));
jb = find(cs == T.cKt(bSel));
i0 = find(pm == T.mult(bMin));
j0 = find(cs == T.cKt(bMin));
[fig, P, isPanel] = panelHost(S, 5.6, 3.8, target);
ax = axes(fig, 'Position', P([0.14, 0.16, 0.64, 0.72]));
hold(ax, 'on');
cmap = S.warm;
lo = min(Z(:), [], 'omitnan');
hi = max(Z(:), [], 'omitnan');
for i = 1:numel(pm)
    for j = 1:numel(cs)
        if ~isfinite(Z(i, j))
            patch(ax, j + [-0.5, 0.5, 0.5, -0.5], i + [-0.5, -0.5, 0.5, 0.5], [0.94, 0.94, 0.94], 'EdgeColor', 'w', ...
                'LineWidth', 0.8);
            continue;                                  % 未扫描的组合
        end
        v = (Z(i, j) - lo) / max(hi - lo, eps);
        col = cmap(max(1, min(size(cmap, 1), 1 + round(v * (size(cmap, 1) - 1)))), :);
        patch(ax, j + [-0.5, 0.5, 0.5, -0.5], i + [-0.5, -0.5, 0.5, 0.5], col, 'EdgeColor', 'w', 'LineWidth', 0.8);
        tc = S.ink;
        if v > 0.6
            tc = [1, 1, 1];
        end
        text(ax, j, i, sprintf('%.0f', U(i, j)), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
            'FontSize', S.fs - 1.2, 'Color', tc);
    end
end
if bSel ~= bMin
    plot(ax, j0 + 0.5 * [-1, 1, 1, -1, -1] * 0.92, i0 + 0.5 * [-1, -1, 1, 1, -1] * 0.92, '--', 'Color', S.hl, 'LineWidth', 0.9);
end
hlBox(ax, jb - 0.5, ib - 0.5, 1, 1, S, 1.4);
xlim(ax, [0.5, numel(cs) + 0.5]);
ylim(ax, [0.5, numel(pm) + 0.5]);
set(ax, 'XTick', 1:numel(cs), 'XTickLabel', compose('%g', round(cs / 1e3, 2)), 'YTick', 1:numel(pm), ...
    'YTickLabel', compose('%.2g', mean(PR, 2, 'omitnan') / 1e3), 'TickLength', [0, 0], 'Box', 'off');
styleAxes(ax, S, false, false);
xlabel(ax, lab(S, '循环铁质量/Mt', 'Circulating iron (Mt)'));
ylabel(ax, lab(S, '还原站充能功率/GW', 'Charging power (GW)'));
title(ax, lab(S, '格内数字：最优固定策略的年缺供电量/GWh', 'Cell labels: annual unserved energy of the best fixed policy (GWh yr^{-1})'), ...
    'FontWeight', 'normal', 'FontSize', S.fs - 1.2, 'Color', S.tick);
tk = linspace(lo, hi, 5);
drawColorbar(fig, P([0.82, 0.16, 0.025, 0.72]), cmap, [lo, hi], tk, compose('%.0f', tk), ...
    lab(S, '年化总成本/亿元', 'Annualised total cost (100 M CNY)'), S, 'v');
finishFigure(fig, S, outBase, isPanel, '');
end
