function F08_dailyCostBox(e3, S, outBase, target)
%F08_DAILYCOSTBOX 图 F08：常规工况下各方法测试期逐日运行成本（箱线 + 抖动散点；模板 9 右上）。
%   箱体为四分位数，须为 1.5 倍四分位距内的最远值；散点为随机抽取的至多 365 个日值；顶部为均值（万元/日）与名次（越低越好）。

if nargin < 4
    target = [];
end
D = e3.daily(strcmp({e3.daily.scenario}, 'normal'));
if isempty(D)
    return;
end
names = unique({D.method}, 'stable');
ord = [names(strcmp(names, 'M1')), names(~strcmp(names, 'M1'))];
n = numel(ord);
V = cell(1, n);
for i = 1:n
    c = arrayfun(@(r) r.d.cost, D(strcmp({D.method}, ord{i})), 'UniformOutput', false);
    V{i} = double([c{:}]) / 1e4;
end
mu = cellfun(@mean, V);
[rk, tied] = tieRank(mu);
rs = RandStream('twister', 'Seed', 1);
[fig, P, isPanel] = panelHost(S, 6.4, 4.0, target);
ax = axes(fig, 'Position', P([0.12, 0.22, 0.85, 0.62]));
hold(ax, 'on');
for i = 1:n
    v = V{i};
    c = S.methodColor(ord{i});
    q = quantileLin(v, [0.25, 0.5, 0.75]);
    iq = q(3) - q(1);
    wl = min(v(v >= q(1) - 1.5 * iq));
    wh = max(v(v <= q(3) + 1.5 * iq));
    k = randperm(rs, numel(v), min(365, numel(v)));
    scatter(ax, i + (rand(rs, numel(k), 1) - 0.5) * 0.44, v(k), 6, c, 'filled', 'MarkerFaceAlpha', 0.35, ...
        'MarkerEdgeColor', 'none');
    plot(ax, i + [-0.25, 0.25, 0.25, -0.25, -0.25], q([1, 1, 3, 3, 1]), '-', 'Color', c, 'LineWidth', 1.6);
    plot(ax, i + [-0.25, 0.25], [q(2), q(2)], '-', 'Color', c, 'LineWidth', 2.0);
    plot(ax, [i, i], [wl, q(1)], '-', 'Color', c, 'LineWidth', 1.3);
    plot(ax, [i, i], [q(3), wh], '-', 'Color', c, 'LineWidth', 1.3);
    plot(ax, i + [-0.12, 0.12], [wl, wl], '-', 'Color', c, 'LineWidth', 1.3);
    plot(ax, i + [-0.12, 0.12], [wh, wh], '-', 'Color', c, 'LineWidth', 1.3);
end
allv = [V{:}];
q = quantileLin(allv, [0.001, 0.999]);
yl = q + [-0.08, 0.05] * diff(q);
ylim(ax, yl);
for i = 1:n
    c = S.methodColor(ord{i});
    text(ax, i, yl(2) + 0.13 * diff(yl), sprintf('%.1f', mu(i)), 'HorizontalAlignment', 'center', ...
        'FontWeight', 'bold', 'Color', c, 'FontSize', S.fs + 0.5, 'Clipping', 'off');
    text(ax, i, yl(2) + 0.05 * diff(yl), [sprintf('#%d', rk(i)), repmat('=', 1, double(tied(i)))], 'HorizontalAlignment', 'center', 'Color', c, ...
        'FontSize', S.fs - 0.5, 'Clipping', 'off');
end
labs = cellfun(S.methodLabel, ord, 'UniformOutput', false);
set(ax, 'XTick', 1:n, 'XTickLabel', labs, 'XTickLabelRotation', 18);
xlim(ax, [0.5, n + 0.5]);
styleAxes(ax, S, true);
ylabel(ax, lab(S, '测试期逐日运行成本/万元', 'Daily operating cost (10^4 CNY)'));
finishFigure(fig, S, outBase, isPanel, lab(S, '常规工况；顶部为均值与名次（越低越好），散点为抽样日值', 'Normal conditions; top, mean and rank; points, sampled days'));
end
