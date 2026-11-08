function N04_lcosCurves(R, S, outBase, target)
%N04_LCOSCURVES 图 6b：单位放电成本随季节性储能自治天数的变化与各省位置（竞争边界的机理）。
%   曲线：取 31 省储能服务与电价的中位数（放电、充电利用小时，输入电价，省内铁路里程与周转时间），只改变自治天数 D，
%   计算铁粉省内循环、盐穴储氢、储罐储氢与绿氨的 LCOS；铁路线阴影为储存设施投资从基准到情景 siloHigh 的区间，
%   氢、氨路线阴影为储存投资的文献区间。赭色浅区为铁粉省内循环低于储罐储氢的自治区间（铁占优区）。
%   圆点为各省最优路线的 LCOS（面积 ∝ 候选改造容量），按路线族（铁基、盐穴储氢、储罐储氢、绿氨）着色，
%   并叠加各路线族的二维核密度等值线；细线为中位数服务下各路线的成本曲线，点线与菱形为铁与储罐储氢、绿氨的交点；
%   顶部与右侧为各路线族在自治天数与 LCOS 上的边缘密度。
if nargin < 4
    target = [];
end
T = R.T;
n = R.n;
st = natRouteStyle(S);
hOut = tcol(T, 'hOut');
hIn = tcol(T, 'hIn');
pinv = tcol(T, 'pin');
dL = tcol(T, 'dLocal');
lpD = tcol(T, 'loopDays');
D = tcol(T, 'D');
FeL = tcol(T, 'FeL');
win = tcol(T, 'winner', {});
gw = tcol(T, 'retroGW', ones(size(D)));
svc.hOut = median(hOut);
svc.hIn = median(hIn);
pin = median(pinv);
dl = median(dL);
lp = median(lpD);
Dg = linspace(1, max(10, 1.25 * max(D)), 200);
cFe = zeros(size(Dg));
cFeHi = zeros(size(Dg));
nHi = n;
nHi.fe.siloPerT = siloHigh(n);
cS = zeros(numel(Dg), 3);
cT = zeros(numel(Dg), 3);
cA = zeros(numel(Dg), 3);
hasNH3 = isfield(n, 'nh3');
ar = [NaN, NaN, NaN];
if hasNH3
    ar = [n.nh3.storeRange(1), n.nh3.store, n.nh3.storeRange(2)];
end
sr = [n.h2.storeSaltRange(1), n.h2.storeSalt, n.h2.storeSaltRange(2)];
tr = [n.h2.storeTankRange(1), n.h2.storeTank, n.h2.storeTankRange(2)];
for k = 1:numel(Dg)
    svc.D = Dg(k);
    cFe(k) = natCost('fe', svc, pin, n, dl, lp);
    cFeHi(k) = natCost('fe', svc, pin, nHi, dl, lp);
    for j = 1:3
        cS(k, j) = natCost('h2', svc, pin, n, 0, 0, sr(j));
        cT(k, j) = natCost('h2', svc, pin, n, 0, 0, tr(j));
        if hasNH3
            nA = n;
            nA.nh3.store = ar(j);
            cA(k, j) = natCost('nh3', svc, pin, nA, 0, 0);
        end
    end
end
yl = [0, 1.12 * max([cFe(:); FeL(:); cS(:, 2); cA(:, 2)])];
xl = [0, Dg(end)];

% 各省最优路线的 LCOS 与路线族
fam = {'Fe', 'H2S', 'H2T', 'NH3L'};
famKey = {{'FeL', 'FeX', 'FeT'}, {'H2S'}, {'H2T'}, {'NH3L'}};
famCol = [st.color("FeL"); st.color("H2S"); 0.8 * st.color("H2T"); st.color("NH3L")];
famLab = {lab(S, '铁基路线', 'Iron routes'), st.label("H2S"), st.label("H2T"), st.label("NH3L")};
L = [tcol(T, 'FeL'), tcol(T, 'FeX'), tcol(T, 'FeT'), tcol(T, 'H2S'), tcol(T, 'H2T'), tcol(T, 'NH3L', nan(size(D)))];
best = min(L, [], 2, 'omitnan');
yl = [0, 1.12 * max([cFe(:); best(:); cS(:, 2); cA(:, 2)])];
bv = best(isfinite(best));
nOut = 0;
if ~isempty(bv) && yl(2) > 3 * median(bv)
    yl(2) = 3 * median(bv);                              % 少数储罐储氢省份成本很高，截断纵轴并注明
    nOut = nnz(bv > yl(2));
end
gx = linspace(xl(1), xl(2), 140);
gy = linspace(yl(1), yl(2), 140);
[GX, GY] = meshgrid(gx, gy);
bw = [0.10 * diff(xl), 0.06 * diff(yl)];
[fig, P, isPanel] = panelHost(S, 6.0, 5.0, target);
ax = axes(fig, 'Position', P([0.12, 0.12, 0.64, 0.64]));
hold(ax, 'on');
hc = gobjects(0);
lc = {};
for g = 1:numel(fam)
    s = ismember(win, famKey{g}) & isfinite(D) & isfinite(best);
    if ~any(s)
        continue;
    end
    c = famCol(g, :);
    if nnz(s) >= 3
        Z = zeros(size(GX));
        xs = D(s);
        ys = best(s);
        for k = 1:numel(xs)
            Z = Z + exp(-0.5 * (((GX - xs(k)) / bw(1)) .^ 2 + ((GY - ys(k)) / bw(2)) .^ 2));
        end
        Z = Z / max(Z(:));
        contourf(ax, GX, GY, Z, [0.25, 0.55, 1.01], 'LineStyle', 'none', 'FaceAlpha', 0.12, 'FaceColor', c);
        contour(ax, GX, GY, Z, [0.25, 0.55, 0.85], 'LineColor', c, 'LineWidth', 0.7);
    end
    hc(end + 1) = scatter(ax, D(s), best(s), 16 + 40 * gw(s) / max(gw), c, 'filled', 'MarkerEdgeColor', 'w', 'LineWidth', 0.5); %#ok<AGROW>
    lc{end + 1} = famLab{g}; %#ok<AGROW>
end
plot(ax, Dg, cFe, '-', 'Color', st.color("FeL"), 'LineWidth', 1.0);
plot(ax, Dg, cT(:, 2), '--', 'Color', 0.8 * st.color("H2T"), 'LineWidth', 0.9);
plot(ax, Dg, cS(:, 2), '--', 'Color', st.color("H2S"), 'LineWidth', 0.9);
if hasNH3
    plot(ax, Dg, cA(:, 2), '--', 'Color', st.color("NH3L"), 'LineWidth', 0.9);
end
xb = crossing(Dg, cFe, cT(:, 2)');
if isfinite(xb)
    plot(ax, [xb, xb], yl, ':', 'Color', S.ink, 'LineWidth', 0.8);
    text(ax, xb, yl(1) + 0.04 * diff(yl), sprintf(lab(S, ' 与储罐储氢交点 %.0f d', ' crossover with tank H_2 %.0f d'), xb), ...
        'FontSize', S.fs - 1.5, 'Color', S.ink, 'VerticalAlignment', 'bottom');
end
if hasNH3
    xa = crossing(Dg, cFe, cA(:, 2)');
    if isfinite(xa)
        ya = interp1(Dg, cFe, xa);
        plot(ax, xa, ya, 'd', 'MarkerSize', 7, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', st.color("NH3L"), 'LineWidth', 1.3);
        text(ax, xa, ya - 0.06 * diff(yl), sprintf(lab(S, '与绿氨交点 %.0f d', 'ammonia crossover %.0f d'), xa), ...
            'HorizontalAlignment', 'center', 'FontSize', S.fs - 1.5, 'Color', st.color("NH3L"));
    end
end
xlim(ax, xl);
ylim(ax, yl);
if nOut > 0
    text(ax, 0.98, 0.98, sprintf('%d province(s) above axis', nOut), 'Units', 'normalized', ...
        'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', 'FontSize', S.fs - 1.6, 'Color', S.tick);
end
styleAxes(ax, S, true, false);
xlabel(ax, lab(S, '满功率自治天数 D/d', 'Full-power autonomy D (d)'));
ylabel(ax, lab(S, '最优路线 LCOS/(元·kWh^{-1})', 'Least-cost LCOS (CNY kWh^{-1})'));
% 边缘密度
at = axes(fig, 'Position', P([0.12, 0.78, 0.64, 0.16]), 'Visible', 'off');
hold(at, 'on');
ar2 = axes(fig, 'Position', P([0.78, 0.12, 0.16, 0.64]), 'Visible', 'off');
hold(ar2, 'on');
for g = 1:numel(fam)
    s = ismember(win, famKey{g}) & isfinite(D) & isfinite(best);
    if nnz(s) < 2
        continue;
    end
    c = famCol(g, :);
    fx = kde1(D(s), gx);
    fy = kde1(best(s), gy);
    patch(at, [gx, fliplr(gx)], [fx, zeros(size(fx))], c, 'FaceAlpha', 0.25, 'EdgeColor', 'none');
    plot(at, gx, fx, '-', 'Color', c, 'LineWidth', 0.9);
    patch(ar2, [fy, zeros(size(fy))], [gy, fliplr(gy)], c, 'FaceAlpha', 0.25, 'EdgeColor', 'none');
    plot(ar2, fy, gy, '-', 'Color', c, 'LineWidth', 0.9);
end
xlim(at, xl);
ylim(ar2, yl);
items = struct('kind', {}, 'color', {}, 'label', {}, 'alpha', {}, 'lw', {});
for g = 1:numel(lc)
    k = find(strcmp(famLab, lc{g}), 1);
    items(end + 1) = struct('kind', 'dot', 'color', famCol(k, :), 'label', lc{g}, 'alpha', 1, 'lw', 1); %#ok<AGROW>
end
drawLegendBox(fig, P([0.14, 0.62, 0.30, 0.13]), items, S, 1, S.fs - 1.5);
finishFigure(fig, S, outBase, isPanel, sprintf(lab(S, '点：各省最优路线 LCOS（面积 ∝ 改造容量）；等值线：路线族密度；细线：中位数服务下的成本曲线（放电 %.0f h/a）', ...
    'Dots: provincial least-cost LCOS; contours: route-family density; lines: median-service curves (%.0f h/yr)'), svc.hOut));
end

function xb = crossing(x, a, b)
% 两条成本曲线的首个交点（无交点时为 NaN）
d = a - b;
i = find(d(1:end - 1) .* d(2:end) < 0, 1);
if isempty(i)
    xb = NaN;
else
    xb = x(i) - d(i) * (x(i + 1) - x(i)) / (d(i + 1) - d(i));
end
end

function v = siloHigh(n)
% 情景 siloHigh 中的铁粉储存设施投资（元/t）；未设置时取基准值
v = n.fe.siloPerT;
k = find(strcmp({n.scenarios.name}, 'siloHigh'), 1);
if ~isempty(k)
    sv = n.scenarios(k).set;
    j = find(strcmp(sv(1:2:end), 'fe.siloPerT'), 1);
    if ~isempty(j)
        v = sv{2 * j};
    end
end
end
