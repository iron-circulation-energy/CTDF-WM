function F23_stressBox(e3, S, outBase, target, opts)
%F23_STRESSBOX 图 3c：各方法低风光回合缺供电量（横向云雨图；E3 drought 工况）。
%   每行一个方法，按均值由低到高自上而下排列：上为渐变填充的半小提琴（核密度 kde1），中为圆角箱（四分位与中位数）
%   与须线（最小—最大），白色菱形为均值，下为各回合散点（测试年 × 种子，确定性抖动）；
%   赭色虚线为本文方法（M1）均值；左侧为方法名与名次徽标，右侧为均值及本文方法相对该方法的降低比例。
%   opts 字段（可选）：scenario（缺省 'drought'）、metric（缺省 'shedMWh'）、scale（缺省 1e-3，MWh → GWh）、label。
if nargin < 4
    target = [];
end
if nargin < 5
    opts = struct();
end
sc = getf(opts, 'scenario', 'drought');
met = getf(opts, 'metric', 'shedMWh');
scale = getf(opts, 'scale', 1e-3);
xl = getf(opts, 'label', lab(S, '每个低风光回合的缺供电量/GWh', 'Unserved energy per drought episode (GWh)'));
E = e3.episodes;
eS = tcol(E, 'scenario', {});
eM = tcol(E, 'method', {});
vAll = scale * tcol(E, met);
keep = strcmpi(eS, sc);
meths = S.methodOrder(ismember(S.methodOrder, eM(keep)));
n = numel(meths);
if n == 0
    return;
end
V = cell(1, n);
mu = nan(1, n);
for k = 1:n
    v = vAll(keep & strcmp(eM, meths{k}));
    V{k} = v(isfinite(v(:)));
    if ~isempty(V{k})
        mu(k) = mean(V{k});
    end
end
isM1 = strcmp(meths, 'M1');
[rkAll, tiedAll] = tieRank(mu);
[~, ord] = sortrows([rkAll(:), ~isM1(:)]);              % 并列时本文方法在前
ord = ord(:)';
ord = ord(isfinite(mu(ord)));
n = numel(ord);
if n == 0
    return;
end
iRef = find(strcmp(meths, 'M1'), 1);
ref = NaN;
if ~isempty(iRef)
    ref = mu(iRef);
end
xmax = 1.08 * max([cellfun(@(v) max([v(:); 0]), V), eps]);
g = linspace(0, xmax, 300);
[fig, P, isPanel] = panelHost(S, 6.8, 0.75 + 0.78 * n, target);
ax = axes(fig, 'Position', P([0.24, 0.14, 0.50, 0.78]));
hold(ax, 'on');
xlim(ax, [0, xmax]);
ylim(ax, [-0.55, n - 0.30]);
for r = 1:n
    k = ord(r);
    y0 = n - r;
    c = S.methodColor(meths{k});
    v = V{k};
    if strcmp(meths{k}, 'M1')
        patch(ax, [0, xmax, xmax, 0], y0 + [-0.40, -0.40, 0.58, 0.58], S.hero, 'FaceAlpha', 0.06, 'EdgeColor', 'none');
    end
    if numel(v) >= 2 && max(v) > min(v)
        f = kde1(v, g);
        f = 0.44 * f / max(f);
        kg = f > 0.01 * max(f);
        gg = g(kg);
        ff = f(kg);
        xs = [gg, fliplr(gg)];
        ys = [y0 + 0.06 + ff, (y0 + 0.06) * ones(size(gg))];
        t = (xs(:) - min(gg)) / max(max(gg) - min(gg), eps);
        cv = (1 - t) * (0.25 * c + 0.75) + t * c;
        patch(ax, 'XData', xs, 'YData', ys, 'FaceVertexCData', cv, 'FaceColor', 'interp', 'EdgeColor', 'none', 'FaceAlpha', 0.95);
        plot(ax, gg, y0 + 0.06 + ff, '-', 'Color', 0.8 * c, 'LineWidth', 0.9);
    end
    qv = quantileLin(v, [0.25, 0.5, 0.75]);
    plot(ax, [min(v), max(v)], [y0, y0], '-', 'Color', 0.75 * c, 'LineWidth', 0.9);
    if qv(3) > qv(1)
        rectangle(ax, 'Position', [qv(1), y0 - 0.045, qv(3) - qv(1), 0.09], 'Curvature', [0.3, 1], ...
            'FaceColor', 'w', 'EdgeColor', 0.75 * c, 'LineWidth', 1.2);
    end
    plot(ax, [qv(2), qv(2)], y0 + [-0.045, 0.045], '-', 'Color', 0.75 * c, 'LineWidth', 1.8);
    scatter(ax, v, y0 - 0.21 + jit(numel(v), 0.14), 14, c, 'filled', 'MarkerFaceAlpha', 0.75, ...
        'MarkerEdgeColor', 'w', 'LineWidth', 0.4);
    plot(ax, mu(k), y0, 'd', 'MarkerSize', 5.5, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', 0.6 * c, 'LineWidth', 1.2);
    fw = 'normal';
    tc = S.ink;
    if strcmp(meths{k}, 'M1')
        fw = 'bold';
        tc = S.hero;
    end
    text(ax, -0.03 * xmax, y0 + 0.08, S.methodLabel(meths{k}), 'HorizontalAlignment', 'right', 'FontSize', S.fs, ...
        'FontWeight', fw, 'Color', tc, 'Clipping', 'off');
    badge(ax, -0.06 * xmax, y0 - 0.24, [sprintf('#%d', rkAll(k)), repmat('=', 1, double(tiedAll(k)))], S, c, 'Clipping', 'off', 'FontSize', S.fs - 2);
    text(ax, 1.02 * xmax, y0 + 0.10, sprintf('%.1f', mu(k)), 'FontSize', S.fs, 'FontWeight', 'bold', 'Color', S.ink, ...
        'Clipping', 'off');
    if strcmp(meths{k}, 'M1')
        s2 = lab(S, '最低', 'lowest');
        if tiedAll(k)
            s2 = lab(S, '最低（并列）', 'lowest (tied)');
        end
    elseif isfinite(ref) && abs(mu(k) - ref) <= 1e-3 * abs(ref)
        s2 = lab(S, '与本文相同', 'same as CTDF-WM');
    elseif isfinite(ref) && mu(k) > 0
        s2 = sprintf(lab(S, '本文低 %.0f%%', 'CTDF-WM %.0f%% lower'), 100 * (1 - ref / mu(k)));
    else
        s2 = '';
    end
    text(ax, 1.02 * xmax, y0 - 0.16, s2, 'FontSize', S.fs - 1.5, 'Color', S.hero, 'Clipping', 'off');
end
if isfinite(ref)
    plot(ax, [ref, ref], [-0.55, n - 0.30], '--', 'Color', S.hero, 'LineWidth', 0.8);
end
styleAxes(ax, S, false, true);
ax.YAxis.Visible = 'off';
xlabel(ax, xl);
finishFigure(fig, S, outBase, isPanel, lab(S, '半小提琴：密度；圆角箱：四分位；菱形：均值；点：回合（测试年 × 种子）', ...
    'Half violin: density; box: quartiles; diamond: mean; dots: episodes'));
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = d;
end
end
