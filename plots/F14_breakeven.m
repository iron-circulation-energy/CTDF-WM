function F14_breakeven(e6, p, S, outBase)
%F14_BREAKEVEN 图 F14：铁路、水运单位千瓦时运费（含铁锈回运）随运距的变化与特高压单位输电成本（E6）。
%   运费 = c^tr·d·(1 + m_Ox)/(η̄·h_Fe·1000)（元/kWh），η̄ 为改造机组平均效率；圆点为盈亏平衡运距；
%   竖虚线为还原站—枢纽干线的实际运距；p.transport.railCostRange 存在时以阴影表示铁路运价范围。

be = e6.breakeven;
d = be.d(:)';
k = (1 + be.mOx) / (be.eta * p.iron.hFe * 1000);
fig = styledFigure(S, 6.4, 4.0);
ax = axes(fig, 'Position', [0.11, 0.13, 0.86, 0.82]);
hold(ax, 'on');
h = gobjects(1, 3);
legLab = cell(1, 3);
if isfield(p.transport, 'railCostRange')
    rr = p.transport.railCostRange;
    fill(ax, [d, fliplr(d)], [rr(1) * d * k, fliplr(rr(2) * d * k)], S.accent, 'FaceAlpha', 0.16, 'EdgeColor', 'none');
    legLab{1} = sprintf(lab(S, '铁路（%.3g 元/(t·km)，阴影 %.3g—%.3g）', 'Rail, %.3g CNY t^{-1} km^{-1}, band %.3g–%.3g'), p.transport.railCost, rr(1), rr(2));
else
    legLab{1} = sprintf(lab(S, '铁路（%.3g 元/(t·km)）', 'Rail, %.3g CNY t^{-1} km^{-1}'), p.transport.railCost);
end
h(1) = plot(ax, d, be.rail, '-', 'Color', S.accent, 'LineWidth', 2.0);
h(2) = plot(ax, d, be.water, '-', 'Color', S.teal, 'LineWidth', 2.0);
legLab{2} = sprintf(lab(S, '水运（%.3g 元/(t·km)）', 'Waterway, %.3g CNY t^{-1} km^{-1}'), p.transport.waterCost);
h(3) = plot(ax, d, be.uhv, '--', 'Color', S.slate, 'LineWidth', 1.6);
legLab{3} = sprintf(lab(S, '特高压输电（%.4g 元/kWh）', 'UHV transmission, %.4g CNY kWh^{-1}'), p.transport.uhvCostPerKwh);
yTop = min(max(be.rail) * 1.02, max([be.uhv(:); be.water(:)]) * 6);
yTop = max(yTop, 2 * max(be.uhv));
pts = {be.dRail, S.accent, [-0.02, 0.36]; be.dWater, S.teal, [0.02, 0.12]};
for q = 1:2
    db = pts{q, 1};
    if isfinite(db) && db <= d(end)
        yb = interp1(d, be.uhv, db);
        plot(ax, db, yb, 'o', 'MarkerSize', 6, 'MarkerFaceColor', pts{q, 2}, 'MarkerEdgeColor', 'w');
        tx = db + pts{q, 3}(1) * d(end);
        ty = yb + pts{q, 3}(2) * yTop;
        plot(ax, [db, tx], [yb, ty], '-', 'Color', pts{q, 2}, 'LineWidth', 0.6);
        text(ax, tx, ty, sprintf(lab(S, '盈亏平衡 %.0f km', 'break-even %.0f km'), db), 'Color', pts{q, 2}, 'VerticalAlignment', 'bottom', ...
            'HorizontalAlignment', 'center');
    end
end
[dist, nm] = trunkDistances(p);
for q = 1:numel(dist)
    if dist(q) <= d(end)
        plot(ax, [dist(q), dist(q)], [0, yTop], ':', 'Color', [0.70, 0.70, 0.70], 'LineWidth', 0.8);
        text(ax, dist(q) + 0.008 * d(end), 0.22 * yTop, sprintf('%s %.0f km', nm{q}, dist(q)), 'Rotation', 90, ...
            'FontSize', S.fs - 1.5, 'Color', [0.43, 0.43, 0.43]);
    end
end
legend(ax, h, legLab, 'Location', 'northwest', 'Box', 'off');
xlim(ax, [0, d(end)]);
ylim(ax, [0, yTop]);
styleAxes(ax, S, true);
xlabel(ax, lab(S, '运距/km', 'Distance (km)'));
ylabel(ax, lab(S, '单位千瓦时运输成本/(元/kWh)', 'Delivery cost (CNY kWh^{-1})'));
addNote(fig, S, sprintf(lab(S, '含铁锈回运；机组平均效率 %.3f', 'Includes rust return; mean plant efficiency %.3f'), be.eta));
saveFigure(fig, outBase);
end

function [dist, nm] = trunkDistances(p)
% 还原站 → 枢纽（或电厂）铁粉线路的运距与名称（同一运距只保留一条）
N = p.net.nodes;
L = p.net.lines;
dist = [];
nm = {};
for e = 1:size(L, 1)
    a = find(strcmp(N(:, 1), L{e, 1}), 1);
    if strcmp(L{e, 3}, 'Fe') && strcmp(N{a, 2}, 'R') && ~any(abs(dist - L{e, 6}) < 30)
        dist(end + 1) = L{e, 6}; %#ok<AGROW>
        nm{end + 1} = sprintf('%s—%s', shortName(p, L{e, 1}), shortName(p, L{e, 2})); %#ok<AGROW>
    end
end
end

function s = shortName(p, id)
s = id;
if isfield(p, 'site')
    j = find(strcmp({p.site.id}, id), 1);
    if ~isempty(j)
        s = siteEnglish(p.site(j).id, p.site(j).short);
    end
end
end
