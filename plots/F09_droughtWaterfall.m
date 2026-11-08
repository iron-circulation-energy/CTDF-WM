function F09_droughtWaterfall(e3, p, S, outBase, target)
%F09_DROUGHTWATERFALL 图 3a：持续低风光事件时间轴（库存曲线与缓冲剩余融合于同一行带；E3 drought 工况）。
%   每个方法一行：底色为缓冲剩余（%，(库存 − 安全库存)/(事件前平均库存 − 安全库存)，负值赭红），
%       行内白衬曲线为电厂铁库存合计（各行共用同一纵向比例），点线为安全库存合计 Σ I̲^Fe_i；
%       空心圆与文字标出各方法的风险预警时刻（episodes.injectedWarningLeadDays 均值）；赭色虚线框为低风光窗口；
%       红框标出库存低于安全库存的连续日段；
%       右侧为事件窗口内全部电厂保持在安全库存以上的天数（episodes.injectedSafeDays 的均值；缺失时由轨迹计算），
%       本文方法下方的徽标为其相对随机 MPC 的差值。
%   函数名沿用旧版（三维瀑布图），以保持 paperFigures 与 runExperiments 的调用不变。
if nargin < 5
    target = [];
end
tr = e3.traces;
sel = find(strcmpi({tr.scenario}, 'drought'));
if isempty(sel)
    return;
end
safety = sum(p.plant.safetyFe) / 1e3;
dDays = 14;
methods = {};
X = {};
F = {};
for j = sel(:)'
    t = tr(j).trace;
    ex = tr(j).ext;
    st = t.warmup + 1;
    if isfield(ex, 'start')
        st = ex.start;
        dDays = ex.days;
    end
    x = (1:size(t.IFe, 2)) - st;
    methods{end + 1} = tr(j).method; %#ok<AGROW>
    X{end + 1} = x; %#ok<AGROW>
    F{end + 1} = sum(t.IFe, 1) / 1e3; %#ok<AGROW>
end
order = [S.methodOrder, setdiff(methods, S.methodOrder)];
[~, ord] = ismember(order(ismember(order, methods)), methods);
methods = methods(ord);
X = X(ord);
F = F(ord);
n = numel(methods);
xr = [-10, max(30, dDays + 16)];
days = xr(1):xr(2);
M = nan(n, numel(days));
for j = 1:n
    M(j, :) = interp1(X{j}, F{j}, days, 'linear', NaN);
end
pre = mean(mean(M(:, days < 0), 2, 'omitnan'), 'omitnan');
rel = 100 * (M - safety) / max(pre - safety, eps);          % 缓冲剩余：事件前缓冲 = 100%，安全库存 = 0
E = [];
if isfield(e3, 'episodes')
    E = e3.episodes;
end
safeDays = nan(1, n);
lead = nan(1, n);
for j = 1:n
    safeDays(j) = epMean(E, methods{j}, 'injectedSafeDays');
    lead(j) = epMean(E, methods{j}, 'injectedWarningLeadDays');
    if ~isfinite(safeDays(j))
        w = days >= 0 & days < dDays + 7;
        safeDays(j) = nnz(M(j, w) >= safety);
    end
end

[fig, P, isPanel] = panelHost(S, 6.8, 0.9 + 0.62 * n, target);
ax = axes(fig, 'Position', P([0.25, 0.13, 0.58, 0.70]));
hold(ax, 'on');
vmin = max(min(min(rel(:)), -10), -100);
vmax = min(max(max(rel(:)), 50), 150);
cm = flipud(S.div);
ylo = min(M(:));
yhi = max([M(:); safety]);
yr = max(yhi - ylo, eps);
yy = @(v, y0) y0 - 0.38 + 0.76 * (v - ylo) / yr;           % 库存映射到行带内
labs = cellfun(@(m) S.methodLabel(m), methods, 'UniformOutput', false);
for j = 1:n
    y0 = n - j;
    C = zeros(1, numel(days), 3);
    for d = 1:numel(days)
        v = rel(j, d);
        if ~isfinite(v)
            C(1, d, :) = S.grid;
        else
            C(1, d, :) = mapColors(cm, twoSlope(min(max(v, vmin), vmax), vmin, vmax));
        end
    end
    image(ax, 'XData', days, 'YData', y0 + [-0.21, 0.21], 'CData', repmat(C, 2, 1));
    c = S.methodColor(methods{j});
    lw = 1.1;
    if strcmp(methods{j}, 'M1')
        lw = 1.9;
    end
    plot(ax, days, yy(M(j, :), y0), '-', 'Color', [1, 1, 1], 'LineWidth', lw + 1.6);
    plot(ax, days, yy(M(j, :), y0), '-', 'Color', c, 'LineWidth', lw);
    plot(ax, xr + [-0.5, 0.5], yy(safety, y0) * [1, 1], ':', 'Color', S.ink, 'LineWidth', 0.6);
    [L, s0] = runs(rel(j, :) < 0);
    for q = 1:numel(L)
        hlBox(ax, days(s0(q)) - 0.5, y0 - 0.42, L(q), 0.84, S, 1.3);
    end
    if isfinite(lead(j)) && lead(j) > 0 && -lead(j) >= xr(1)
        xf = -lead(j);
        plot(ax, xf, yy(interp1(days, M(j, :), xf), y0), 'o', 'MarkerSize', 4.5, 'MarkerFaceColor', 'w', ...
            'MarkerEdgeColor', c, 'LineWidth', 1.2);
        text(ax, xf, y0 + 0.46, sprintf(lab(S, '预警 −%.0f d', 'flag −%.0f d'), lead(j)), 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'bottom', 'FontSize', S.fs - 2, 'Color', S.tick);
    end
    fw = 'normal';
    if strcmp(methods{j}, 'M1')
        fw = 'bold';
    end
    text(ax, xr(1) - 1.2, y0, labs{j}, 'HorizontalAlignment', 'right', 'FontSize', S.fs - 0.5, 'FontWeight', fw, ...
        'Color', c, 'Clipping', 'off');
end
plot(ax, [-0.5, dDays - 0.5, dDays - 0.5, -0.5, -0.5], [-0.5, -0.5, n - 0.5, n - 0.5, -0.5], '--', 'Color', S.hero, ...
    'LineWidth', 1.0);
text(ax, (dDays - 1) / 2, n - 0.42, sprintf(lab(S, '连续低风光 %d 天', '%d-day drought'), dDays), ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', S.fs - 0.5, 'FontWeight', 'bold', 'Color', S.hero);
xlim(ax, xr + [-0.5, 0.5]);
ylim(ax, [-0.55, n - 0.25]);
xlabel(ax, lab(S, '相对低风光开始的天数/d', 'Days from drought onset'));
styleAxes(ax, S);
ax.YAxis.Visible = 'off';
% 右侧：安全天数条形
jH = find(strcmp(methods, 'M1'), 1);
jM = find(strcmp(methods, 'M2'), 1);
at = axes(fig, 'Position', P([0.855, 0.13, 0.12, 0.70]));
hold(at, 'on');
for j = 1:n
    mj = M(j, isfinite(M(j, :)));
    if ~isempty(mj) && all(mj >= safety)                % 全程未低于安全库存：不计安全天数，标注说明
        text(at, 0, n - j, ' never below', 'FontSize', S.fs - 1.6, 'Color', S.tick, 'VerticalAlignment', 'middle');
        continue;
    end
    if isfinite(safeDays(j))
        barh(at, n - j, safeDays(j), 0.5, 'FaceColor', S.methodColor(methods{j}), 'EdgeColor', 'none');
        text(at, safeDays(j), n - j, sprintf(' %.0f', safeDays(j)), 'FontSize', S.fs - 1.2, 'Color', S.ink, ...
            'VerticalAlignment', 'middle');
    end
end
ylim(at, [-0.55, n - 0.25]);
xlim(at, [0, 1.35 * max([safeDays(isfinite(safeDays)), 1])]);
styleAxes(at, S);
at.YAxis.Visible = 'off';
xlabel(at, lab(S, '安全天数', 'Safe days'));
if ~isempty(jH) && ~isempty(jM) && isfinite(safeDays(jH)) && isfinite(safeDays(jM))
    badge(at, 0.55, 1.04, sprintf(lab(S, '%+.0f d 相对 MPC', '%+.0f d vs MPC'), safeDays(jH) - safeDays(jM)), S, S.hero, ...
        'Units', 'normalized', 'FontSize', S.fs - 1.5);
end
tv = unique([ceil(vmin / 50) * 50, 0, 50, 100]);
tv = tv(tv >= vmin & tv <= vmax);
drawColorbar(fig, P([0.25, 0.905, 0.20, 0.022]), mapColors(cm, twoSlope(linspace(vmin, vmax, 256), vmin, vmax)), ...
    [vmin, vmax], tv, [], lab(S, '缓冲剩余/%（底色）', 'Buffer left (%)'), S, 'h');
items = struct('kind', {'line', 'dash', 'box'}, 'color', {S.ink, S.ink, S.hl}, ...
    'label', {lab(S, '白衬曲线：电厂铁库存合计', 'Plant iron inventory'), lab(S, '点线：安全库存', 'Safety stock'), ...
    lab(S, '低于安全库存', 'Below safety stock')}, 'alpha', {1, 1, 1}, 'lw', {1.2, 0.8, 1.1});
drawLegendBox(fig, P([0.47, 0.865, 0.52, 0.10]), items, S, 2, S.fs - 1.5);
finishFigure(fig, S, outBase, isPanel, '');
end

function v = epMean(E, m, f)
v = NaN;
if isempty(E)
    return;
end
col = tcol(E, f);
if isempty(col)
    return;
end
mm = tcol(E, 'method', {});
sc = tcol(E, 'scenario', {});
s = strcmp(mm, m) & strcmpi(sc, 'drought') & isfinite(col);
if any(s)
    v = mean(col(s));
end
end

function [L, s0] = runs(b)
b = [false, b(:)', false];
d = diff(b);
s0 = find(d == 1);
L = find(d == -1) - s0;
end
