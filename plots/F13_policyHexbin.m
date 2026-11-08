function F13_policyHexbin(e3, S, outBase, target)
%F13_POLICYHEXBIN 图 3b：本文方法的发运决策与低风光预测（模板“六边形密度 + 中位数与 10/90 分位线 + 边缘分布”；E3 常规工况）。
%   横轴：未来 1—7 日必需燃铁电量预测之和（GWh，共用预测器）；纵轴：当日还原站发出的铁粉量（kt/d）。
%   颜色为天数（对数，青色顺序色图）；赭色实线为分段条件中位数，赭色虚线为 10%/90% 分位数（段内样本 ≥ 30）；
%   顶部与右侧为边缘分布直方图；徽标为 Spearman 秩相关系数。
if nargin < 4
    target = [];
end
D = e3.daily(strcmp({e3.daily.scenario}, 'normal'));
meths = unique({D.method}, 'stable');
main = 'M1';
if ~any(strcmp(meths, main))
    main = meths{1};
end
D = D(strcmp({D.method}, main));
if isempty(D)
    return;
end
x = [];
y = [];
for k = 1:numel(D)
    x = [x, double(D(k).d.fc7(:)')]; %#ok<AGROW>
    y = [y, double(D(k).d.shipFe(:)')]; %#ok<AGROW>
end
x = x / 1e3;
y = y / 1e3;
ok = isfinite(x) & isfinite(y);
x = x(ok);
y = y(ok);
xl = [0, max(quantileLin(x, 0.995), eps)];
yl = [0, max(quantileLin(y, 0.998) * 1.06, eps)];

[fig, P, isPanel] = panelHost(S, 6.0, 4.6, target);
ax = axes(fig, 'Position', P([0.15, 0.17, 0.60, 0.58]));
hold(ax, 'on');
[~, cnt] = hexbinPatch(ax, x, y, 34, 20, xl, yl);
colormap(ax, S.seq);
cmax = max(log10(max(cnt)), 1);
clim(ax, [0, cmax]);
nb = 24;
edges = linspace(xl(1), xl(2), nb + 1);
xm = [];
q = zeros(0, 3);
for k = 1:nb
    s = y(x >= edges(k) & x < edges(k + 1));
    if numel(s) >= 30
        xm(end + 1) = (edges(k) + edges(k + 1)) / 2; %#ok<AGROW>
        q(end + 1, :) = quantileLin(s(:)', [0.1, 0.5, 0.9]); %#ok<AGROW>
    end
end
if numel(xm) >= 2
    plot(ax, xm, q(:, 1), '--', 'Color', S.hero, 'LineWidth', 1.0);
    plot(ax, xm, q(:, 3), '--', 'Color', S.hero, 'LineWidth', 1.0);
    plot(ax, xm, q(:, 2), '-', 'Color', 'w', 'LineWidth', 3.0);
    plot(ax, xm, q(:, 2), '-', 'Color', S.hero, 'LineWidth', 1.8);
end
xlim(ax, xl);
ylim(ax, yl);
xlabel(ax, lab(S, '未来 7 日必需燃铁电量预测/GWh', 'Forecast 7-day firm discharge need (GWh)'));
ylabel(ax, lab(S, '当日铁粉发运量/(kt·d^{-1})', 'Iron shipped (kt d^{-1})'));
styleAxes(ax, S);
rho = spearman(x, y);
if isfinite(rho)
    badge(ax, 0.04, 0.92, sprintf('Spearman \\rho = %.2f', rho), S, S.hero, 'Units', 'normalized', ...
        'HorizontalAlignment', 'left');
end
% 边缘分布
at = axes(fig, 'Position', P([0.15, 0.765, 0.60, 0.11]));
marg(at, x, xl, S, 'x');
ar = axes(fig, 'Position', P([0.765, 0.17, 0.08, 0.58]));
marg(ar, y, yl, S, 'y');
% 色标与图例
tk = 0:ceil(cmax);
drawColorbar(fig, P([0.885, 0.17, 0.022, 0.40]), S.seq, [0, cmax], tk, ...
    arrayfun(@(v) sprintf('10^{%d}', v), tk, 'UniformOutput', false), lab(S, '天数', 'Days'), S, 'vt');
items = struct('kind', {'line', 'dash'}, 'color', {S.hero, S.hero}, ...
    'label', {lab(S, '条件中位数', 'Median'), lab(S, '10%/90% 分位', '10th/90th pct')}, 'alpha', {1, 1}, 'lw', {1.8, 1.0});
drawLegendBox(fig, P([0.15, 0.895, 0.70, 0.08]), items, S, 2, S.fs - 1.2);
finishFigure(fig, S, outBase, isPanel, sprintf(lab(S, '%s，常规工况，全部测试年 × 种子', '%s, normal conditions, all test years and seeds'), ...
    S.methodLabel(main)));
end

function marg(a, v, lim, S, dim)
hold(a, 'on');
e = linspace(lim(1), lim(2), 31);
c = histc(v(:), e);
c = c(1:end - 1)';
c = c / max(max(c), 1);
for k = 1:numel(c)
    if strcmp(dim, 'x')
        patch(a, [e(k), e(k + 1), e(k + 1), e(k)], [0, 0, c(k), c(k)], S.teal, 'EdgeColor', 'w', 'LineWidth', 0.3, ...
            'FaceAlpha', 0.75);
    else
        patch(a, [0, 0, c(k), c(k)], [e(k), e(k + 1), e(k + 1), e(k)], S.teal, 'EdgeColor', 'w', 'LineWidth', 0.3, ...
            'FaceAlpha', 0.75);
    end
end
if strcmp(dim, 'x')
    xlim(a, lim);
    ylim(a, [0, 1.05]);
else
    ylim(a, lim);
    xlim(a, [0, 1.05]);
end
set(a, 'Visible', 'off');
end

function r = spearman(x, y)
r = NaN;
if numel(x) < 3
    return;
end
rx = rankv(x);
ry = rankv(y);
c = corrcoef(rx, ry);
r = c(1, 2);
end

function r = rankv(v)
[~, o] = sort(v(:));
r = zeros(numel(v), 1);
r(o) = 1:numel(v);
end
