function N03_routeMap(R, N, S, outBase, target)
%N03_ROUTEMAP 图 6a：季节性储能路线竞争格局（模板“全国流动网络 + 局部放大 + 热点分级图例”）。
%   各省按基准情景下单位放电成本（LCOS）最低的路线设色，颜色深浅表示领先幅度（与第二名之差，越深越明显）；
%   特高压直流为弧线（送端风光中心 → 受端煤电中心），颜色与线宽随额定容量增大（流线色图），白色衬线保证可读，
%   虚线为在建；送端为实心点、受端为空心点；青色虚线边框为具备盐穴条件（等级 ≤ saltTierMax）的省份。
%   左下为华东—华中局部放大（小省份与密集受端），红色虚线框与连线标出放大范围；右下为南海诸岛小图。
%   图下方：路线图例、特高压容量色标与三项关键数字（铁燃料路线最优省数、改造年轻煤电容量、剩余寿命价值）。
%   完善：地图加浅灰投影；送入“送端铁循环 + 特高压”（FeT）胜出省份的线路按容量着色加粗，其余线路淡化为浅灰；
%   左上为比例尺（1 000 km，按 35°N 经度换算）与指北针。
if nargin < 5
    target = [];
end
T = R.T;
st = natRouteStyle(S);
ext = [73.0, 135.5, 17.5, 54.0];
zext = [111.5, 122.5, 28.3, 34.6];
names = tcol(T, 'name', {});
win = tcol(T, 'winner', {});
mrg = tcol(T, 'margin');
nP = numel(names);
cols = zeros(nP, 3);
mx = max(mrg(isfinite(mrg)));
if isempty(mx) || mx <= 0
    mx = 1;
end
for i = 1:nP
    k = find(strcmp(st.keys, win{i}), 1);
    if isempty(k)
        cols(i, :) = [0.85, 0.85, 0.85];
        continue;
    end
    a = 0.40 + 0.60 * min(1, mrg(i) / mx);
    if ~isfinite(a)
        a = 1;
    end
    cols(i, :) = a * st.colors(k, :) + (1 - a) * [1, 1, 1];
end
saltTier = tcol(T, 'saltTier');
salt = saltTier <= R.n.h2.saltTierMax;

[fig, P, isPanel] = panelHost(S, 7.0, 6.2, target);
ax = axes(fig, 'Position', P([0.0, 0.25, 1.0, 0.75]));
drawProvMap(ax, S, ext, names, cols, struct('labels', false, 'edge', 0.4));
drawShadow(ax, [0.35, -0.35]);
drawSalt(ax, names(salt), S, 1.0);
U = N.uhv;
mw = double(U.mw(:));
mwr = [min(mw), max(mw)];
focus = false(height(U), 1);
for q = 1:height(U)
    focus(q) = U.toIdx(q) >= 1 && U.toIdx(q) <= nP && strcmp(win{U.toIdx(q)}, 'FeT');
end
if ~any(focus)
    focus(:) = true;
end
drawUHV(ax, U, N.prov, S, mwr, 1.0, focus);
% 比例尺与指北针
kmDeg = 1000 / (111.32 * cosd(35));
plot(ax, 75 + [0, kmDeg], [51.2, 51.2], '-', 'Color', S.ink, 'LineWidth', 2);
text(ax, 75 + kmDeg / 2, 51.9, '1 000 km', 'HorizontalAlignment', 'center', 'FontSize', S.fs - 1.8, 'Color', S.ink);
plot(ax, [88.5, 88.5], [49.6, 52.6], '-', 'Color', S.ink, 'LineWidth', 1.0);
patch(ax, 88.5 + [-0.6, 0, 0.6], [52.0, 53.4, 52.0], S.ink, 'EdgeColor', 'none');
text(ax, 88.5, 49.2, 'N', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', 'FontSize', S.fs - 1, 'FontWeight', 'bold');
plot(ax, zext([1, 2, 2, 1, 1]), zext([3, 3, 4, 4, 3]), '--', 'Color', S.hl, 'LineWidth', 1.0);
% 局部放大
ia = axes(fig, 'Position', P([0.005, 0.255, 0.30, 0.185]));
drawProvMap(ia, S, zext, names, cols, struct('labels', true, 'fs', S.fs - 2.2, 'labelColor', [0.1, 0.1, 0.1], 'edge', 0.5));
drawSalt(ia, names(salt), S, 1.0);
drawUHV(ia, U, N.prov, S, mwr, 0.9, focus);
set(ia, 'XColor', S.hl, 'YColor', S.hl, 'LineWidth', 0.9);
text(ia, zext(2) - 0.15, zext(3) + 0.15, lab(S, '华东局部放大', 'East China'), 'FontSize', S.fs - 2, 'Color', S.hl, ...
    'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'right', 'FontWeight', 'bold', 'BackgroundColor', 'w', 'Margin', 0.5);
connect(fig, ax, ia, zext, S);
% 南海诸岛
addNanhaiInset(fig, S, P([0.86, 0.27, 0.12, 0.20]), names, cols);

% ---------------- 图下方：图例、色标与关键数字 ----------------
items = struct('kind', {}, 'color', {}, 'label', {}, 'alpha', {}, 'lw', {});
for k = 1:numel(st.keys)
    if any(strcmp(win, st.keys{k}))
        items(end + 1) = struct('kind', 'patch', 'color', st.colors(k, :), 'label', st.labels{k}, 'alpha', 1, 'lw', 1); %#ok<AGROW>
    end
end
items(end + 1) = struct('kind', 'dash', 'color', S.teal, 'label', lab(S, '具备盐穴条件', 'Salt-cavern province'), 'alpha', 1, 'lw', 1.0);
items(end + 1) = struct('kind', 'line', 'color', [0.66, 0.70, 0.74], 'label', lab(S, '其他特高压直流', 'Other UHV DC lines'), 'alpha', 1, 'lw', 0.6);
drawLegendBox(fig, P([0.01, 0.01, 0.60, 0.20]), items, S, 2, S.fs - 1.8);
gw = mwr / 1e3;
tk = unique(round(linspace(gw(1), gw(2), 3) * 2) / 2);
drawColorbar(fig, P([0.66, 0.025, 0.30, 0.018]), mapColors(S.flow, linspace(0.10, 1, 256)), gw, tk, [], ...
    lab(S, '特高压直流额定容量/GW（线宽同）', 'UHV DC rating (GW); width likewise'), S, 'h');
sc = R.scen;
nFe = scenVal(sc, 'nFe', NaN);
if ~isfinite(nFe)
    nFe = scenVal(sc, 'nFeL', 0) + scenVal(sc, 'nFeX', 0) + scenVal(sc, 'nFeT', 0);
end
key = {sprintf('%d', round(nFe)), lab(S, {'铁燃料路线', '最优省份'}, {'provinces', 'led by iron'}); ...
    sprintf('%.0f GW', scenVal(sc, 'gwFeWin', NaN)), lab(S, {'年轻煤电', '继续服役'}, {'young coal', 'kept in service'}); ...
    sprintf('%s', thousands(scenVal(sc, 'assetBn', NaN))), {sprintf(lab(S, '%d 年剩余价值', '%d residual'), R.n.coal.retireYear), ...
    lab(S, '（亿元）', 'value (10^8 CNY)')}};
ak = axes(fig, 'Position', P([0.63, 0.135, 0.37, 0.10]), 'Visible', 'off');
hold(ak, 'on');
xlim(ak, [0, 3]);
ylim(ak, [0, 1]);
for j = 1:3
    text(ak, j - 0.5, 0.72, key{j, 1}, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
        'FontSize', S.fs + 2.5, 'FontWeight', 'bold', 'Color', S.hero);
    text(ak, j - 0.5, 0.30, mline(key{j, 2}), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
        'FontSize', S.fs - 1.8, 'Color', S.ink);
    if j < 3
        plot(ak, [j, j], [0.05, 0.95], '-', 'Color', S.grid, 'LineWidth', 0.8);
    end
end
finishFigure(fig, S, outBase, isPanel, lab(S, '颜色越深表示与第二名路线的成本差越大', 'Darker shading, larger cost lead over the runner-up'));
end

function drawShadow(ax, off)
% 省界多边形的浅灰投影，置于最底层
G = loadChinaMap();
hold(ax, 'on');
for i = 1:numel(G.provRings)
    for k = 1:numel(G.provRings{i})
        r = G.provRings{i}{k};
        if size(r, 1) > 30
            h = patch(ax, r(:, 1) + off(1), r(:, 2) + off(2), [0.84, 0.86, 0.88], 'EdgeColor', 'none');
            uistack(h, 'bottom');
        end
    end
end
end

function drawSalt(ax, names, S, lw)
G = loadChinaMap();
[~, loc] = ismember(names(:), G.provName(:));
for i = loc(loc > 0)'
    for k = 1:numel(G.provRings{i})
        r = G.provRings{i}{k};
        if size(r, 1) > 30
            plot(ax, r(:, 1), r(:, 2), '--', 'Color', S.teal, 'LineWidth', lw);
        end
    end
end
end

function drawUHV(ax, U, Pv, S, mwr, scale, focus)
hold(ax, 'on');
if nargin < 7
    focus = true(height(U), 1);
end
mw = double(U.mw(:));
status = cellstr(U.status);
[~, o] = sort(mw);
for q = o(:)'
    a = [Pv.reLon(U.fromIdx(q)), Pv.reLat(U.fromIdx(q))];
    b = [Pv.coalLon(U.toIdx(q)), Pv.coalLat(U.toIdx(q))];
    A = bezierArc(a, b, 0.14);
    t = (mw(q) - mwr(1)) / max(diff(mwr), eps);
    c = mapColors(S.flow, 0.10 + 0.90 * t);
    lw = scale * (0.35 + 1.05 * t);
    if ~focus(q)
        c = [0.66, 0.70, 0.74];
        lw = scale * 0.45;
    end
    ls = '-';
    if ~strcmpi(status{q}, 'operating')
        ls = '--';
    end
    plot(ax, A(:, 1), A(:, 2), '-', 'Color', [1, 1, 1], 'LineWidth', lw + 0.6);
    plot(ax, A(:, 1), A(:, 2), ls, 'Color', c, 'LineWidth', lw);
    plot(ax, a(1), a(2), 'o', 'MarkerSize', 2.2 * scale, 'MarkerFaceColor', S.dark, 'MarkerEdgeColor', 'w', 'LineWidth', 0.3);
    plot(ax, b(1), b(2), 'o', 'MarkerSize', 2.2 * scale, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', S.dark, 'LineWidth', 0.5);
end
end

function connect(fig, ax, ia, zext, S)
% 主图放大框与局部放大图之间的连线（图窗归一化坐标）
[x1, y1] = d2f(fig, ax, zext([1, 1]), zext([4, 3]));
p = get(ia, 'Position');
[bx, by] = plotBox(fig, ia);
ov = axes(fig, 'Position', [0, 0, 1, 1], 'Visible', 'off', 'HitTest', 'off');
hold(ov, 'on');
xlim(ov, [0, 1]);
ylim(ov, [0, 1]);
plot(ov, [x1(1), bx(2)], [y1(1), by(2)], '--', 'Color', S.hl, 'LineWidth', 0.6);
plot(ov, [x1(2), bx(2)], [y1(2), by(1)], '--', 'Color', S.hl, 'LineWidth', 0.6);
end

function [fx, fy] = d2f(fig, ax, x, y)
% 数据坐标 → 图窗归一化坐标（考虑 daspect 造成的绘图框收缩与居中）
[bx, by, xl, yl] = plotBox(fig, ax);
fx = bx(1) + (x - xl(1)) / diff(xl) * diff(bx);
fy = by(1) + (y - yl(1)) / diff(yl) * diff(by);
end

function [bx, by, xl, yl] = plotBox(fig, ax)
u = get(fig, 'Units');
set(fig, 'Units', 'inches');
fp = get(fig, 'Position');
set(fig, 'Units', u);
W = fp(3);
H = fp(4);
p = get(ax, 'Position');
xl = xlim(ax);
yl = ylim(ax);
dar = daspect(ax);
dw = diff(xl) / dar(1);
dh = diff(yl) / dar(2);
w = p(3) * W;
h = p(4) * H;
s = min(w / dw, h / dh);
bw = dw * s;
bh = dh * s;
x0 = p(1) * W + (w - bw) / 2;
y0 = p(2) * H + (h - bh) / 2;
bx = [x0, x0 + bw] / W;
by = [y0, y0 + bh] / H;
end

function v = scenVal(sc, f, d)
v = d;
c = tcol(sc, f);
if ~isempty(c)
    v = c(1);
end
end

function s = thousands(v)
if ~isfinite(v)
    s = '—';
    return;
end
s = regexprep(sprintf('%.0f', v), '(\d)(?=(\d{3})+$)', '$1,');
end
