function F01_corridorMap(flow, p, S, outBase)
%F01_CORRIDORMAP 图 F01：研究区域与铁—锈年物流（地图 + 流线 + 节点气泡；模板 1）。
%   左：全走廊（还原站—枢纽干线）；右：枢纽—电厂节点群放大；左下角为全国位置示意（含南海断续线）。
%   每条线路画 nY 条细弧线，对应 nY 个测试年（弧度依次递增），颜色为该年的年物流量（百万 t，对数色标）；
%   铁粉流线较粗、铁锈回运流线较细且弯向另一侧。节点气泡面积 ∝ 容量（还原站 p̄^red、电厂 p̄），枢纽为固定大小。
%   flow：结构体，字段 F（nE×nY，各线路各测试年的年物流量，t/年）、years（测试年标签）、method。
%   需要 p.site（节点名称与坐标，haoji 算例）；缺少坐标时不作图。p.siteLines（可选）为铁路、河流的示意走向。

if ~isfield(p, 'site') || isempty(flow) || ~isfield(flow, 'F')
    return;
end
ids = {p.site.id};
names = p.net.nodes(:, 1);
nN = numel(names);
pos = nan(nN, 2);
short = names;
labPos = zeros(nN, 2);
for i = 1:nN
    k = find(strcmp(ids, names{i}), 1);
    if ~isempty(k)
        pos(i, :) = [p.site(k).lon, p.site(k).lat];
        short{i} = lab(S, p.site(k).short, siteEnglish(p.site(k).id, p.site(k).short));
        labPos(i, :) = p.site(k).lab;
    end
end
if any(~isfinite(pos(:)))
    warning('F01_corridorMap:coord', 'p.site 缺少部分节点坐标，跳过地图。');
    return;
end
typ = p.net.nodes(:, 2);
isR = strcmp(typ, 'R');
isH = strcmp(typ, 'H');
isP = strcmp(typ, 'P');
capN = zeros(nN, 1);
capN(isR) = p.station.pRedMax(:);
capN(isP) = p.plant.pmax(:);
L = p.net.lines;
from = cellfun(@(s) find(strcmp(names, s)), L(:, 1));
to = cellfun(@(s) find(strcmp(names, s)), L(:, 2));
isFe = strcmp(L(:, 3), 'Fe');
F = flow.F / 1e6;                                   % 百万 t/年
nY = size(F, 2);
pf = F(F > 0);
if isempty(pf)
    return;
end
cl = [10 ^ floor(log10(min(pf))), 10 ^ ceil(log10(max(pf)))];
tcol = @(v) mapColors(S.flow, (log10(max(v, cl(1))) - log10(cl(1))) / diff(log10(cl)));
colT = struct('R', S.teal, 'H', S.sand, 'P', S.accent);

% 范围：主图覆盖全部节点，放大图覆盖枢纽与电厂
ext = [min(pos(:, 1)) - 4.5, max(pos(:, 1)) + 3.6, min(pos(:, 2)) - 0.8, max(pos(:, 2)) + 1.8];
q = isH | isP;
zext = [min(pos(q, 1)) - 0.5, max(pos(q, 1)) + 0.57, min(pos(q, 2)) - 0.36, max(pos(q, 2)) + 0.40];
fig = styledFigure(S, 7.0, 5.3);
ax = axes(fig, 'Position', [0.0, 0.17, 0.52, 0.81]);
az = axes(fig, 'Position', [0.53, 0.17, 0.47, 0.81]);
drawChinaMap(ax, S, ext);
drawChinaMap(az, S, zext);
for a = [ax, az]
    drawSiteLines(a, p);
end
% 流线
for e = 1:size(L, 1)
    if ~isFe(e)
        continue;
    end
    a = from(e);
    b = to(e);
    eo = find(from == b & to == a & ~isFe, 1);        % 对应的铁锈回运线路
    trunk = isR(a) || isR(b);
    tgt = ax;
    base = 0.14;
    w = 1.3;
    if ~trunk
        tgt = az;
        base = 0.32;
        w = 1.6;
    end
    for k = 1:nY
        if F(e, k) > 0
            P1 = bezierArc(pos(a, :), pos(b, :), base + 0.022 * (k - 1));
            plot(tgt, P1(:, 1), P1(:, 2), '-', 'Color', blend(tcol(F(e, k)), 0.85, S.land), 'LineWidth', w);
        end
        if ~isempty(eo) && F(eo, k) > 0
            P2 = bezierArc(pos(b, :), pos(a, :), base + 0.022 * (k - 1));
            plot(tgt, P2(:, 1), P2(:, 2), '-', 'Color', blend(tcol(F(eo, k)), 0.6, S.land), 'LineWidth', 0.55 * w);
        end
    end
end
% 节点
drawNodes(ax, find(isR | isH), pos, capN, typ, colT, 0.07);
drawNodes(az, find(isH | isP), pos, capN, typ, colT, 0.11);
for i = find(isR)'
    labelNode(ax, S, pos(i, :), labPos(i, :), short{i}, capN(i));
end
for i = find(isH | isP)'
    labelNode(az, S, pos(i, :), labPos(i, :), short{i}, capN(i));
end
rectangle(ax, 'Position', [zext(1), zext(3), zext(2) - zext(1), zext(4) - zext(3)], 'EdgeColor', S.accent, ...
    'LineWidth', 0.9);
text(ax, zext(2) + 0.15, zext(3) + 0.2, lab(S, '右图范围', 'zoom area'), 'FontSize', S.fs - 1, 'Color', S.accent);
% 全国位置示意（含南海断续线）
ia = axes(fig, 'Position', [0.005, 0.175, 0.15, 0.19]);
drawChinaMap(ia, S, [73, 135.5, 3, 54], struct('edge', 0.25, 'labels', false, 'land', [0.87, 0.89, 0.91]));
rectangle(ia, 'Position', [ext(1), ext(3), ext(2) - ext(1), ext(4) - ext(3)], 'EdgeColor', S.accent, ...
    'LineWidth', 0.8);
% 图例与色标
hold(ax, 'on');
h = gobjects(0);
h(end + 1) = plot(ax, nan, nan, '-', 'Color', [0.80, 0.29, 0.19], 'LineWidth', 1.5);
h(end + 1) = plot(ax, nan, nan, '-', 'Color', blend([0.80, 0.29, 0.19], 0.6, S.land), 'LineWidth', 0.8);
lbl = {sprintf(lab(S, '铁粉流线（每条 = 一个测试年，共 %d 年）', 'Iron flow, one arc per test year, %d years'), nY), lab(S, '铁锈回运流线', 'Rust return flow')};
if isfield(p, 'siteLines')
    for k = 1:numel(p.siteLines)
        [c, ls, lw] = lineStyleOf(p.siteLines(k).style);
        h(end + 1) = plot(ax, nan, nan, ls, 'Color', c, 'LineWidth', lw); %#ok<AGROW>
        lbl{end + 1} = lab(S, p.siteLines(k).name, siteEnglish(p.siteLines(k).style, p.siteLines(k).name)); %#ok<AGROW>
    end
end
tn = {'R', lab(S, '还原站（新能源侧）', 'Reduction station'); 'H', lab(S, '铁水联运枢纽', 'Rail–water hub'); ...
    'P', lab(S, '改造煤电机组（面积 ∝ 容量）', 'Retrofitted plant, area scales with capacity')};
for k = 1:3
    h(end + 1) = plot(ax, nan, nan, 'o', 'MarkerSize', 7, 'MarkerFaceColor', colT.(tn{k, 1}), ...
        'MarkerEdgeColor', 'w'); %#ok<AGROW>
    lbl{end + 1} = tn{k, 2}; %#ok<AGROW>
end
lg = legend(ax, h, lbl, 'NumColumns', 3, 'Box', 'off', 'FontSize', S.fs - 1);
lg.Units = 'normalized';
lg.Position = [0.005, 0.005, 0.66, 0.12];
colormap(az, S.flow);
clim(az, log10(cl));
azPos = az.Position;
cb = colorbar(az, 'southoutside');
cb.Position = [0.70, 0.11, 0.27, 0.018];
az.Position = azPos;
tk = log10(cl(1)):1:log10(cl(2));
cb.Ticks = tk;
cb.TickLabels = arrayfun(@(v) num2str(10 ^ v), tk, 'UniformOutput', false);
styleColorbar(cb, S, lab(S, '年物流量/百万 t（对数）', 'Annual flow (Mt)'));
addNote(fig, S, sprintf(lab(S, '%s 测试期运行结果；铁路与河流为示意走向；底图：标准地图（审图号见图注）', ...
    '%s, test years; rail and river paths schematic; standard base map'), S.methodLabel(flow.method)));
saveFigure(fig, outBase);
end

function c = blend(c, a, bg)
% 以背景色预混合实现半透明效果（线对象不使用 RGBA 颜色）
c = a * c(:)' + (1 - a) * bg(:)';
end

function drawNodes(ax, idx, pos, capN, typ, colT, k0)
hold(ax, 'on');
for i = idx(:)'
    c = colT.(typ{i});
    cap = capN(i);
    if cap <= 0
        cap = 700;
    end
    s = 28 + cap * k0;
    scatter(ax, pos(i, 1), pos(i, 2), 2.8 * s, c, 'filled', 'MarkerFaceAlpha', 0.18, 'MarkerEdgeColor', 'none');
    scatter(ax, pos(i, 1), pos(i, 2), s, c, 'filled', 'MarkerEdgeColor', 'w', 'LineWidth', 1.1);
    scatter(ax, pos(i, 1), pos(i, 2), 5, 'w', 'filled');
end
end

function labelNode(ax, S, xy, d, name, cap)
if all(d == 0)
    d = [0.4, 0.3];
end
txt = name;
if cap > 0
    txt = sprintf('%s\n%s MW', name, thousands(cap));
end
ha = 'center';
if d(1) > 0
    ha = 'left';
elseif d(1) < 0
    ha = 'right';
end
plot(ax, [xy(1), xy(1) + d(1)], [xy(2), xy(2) + d(2)], '-', 'Color', [0.63, 0.63, 0.63], 'LineWidth', 0.5);
text(ax, xy(1) + d(1), xy(2) + d(2), txt, 'HorizontalAlignment', ha, 'VerticalAlignment', 'middle', ...
    'FontSize', S.fs - 0.8, 'Color', S.ink);
end

function s = thousands(v)
s = regexprep(sprintf('%.0f', v), '(\d)(?=(\d{3})+$)', '$1,');
end

function drawSiteLines(ax, p)
if ~isfield(p, 'siteLines')
    return;
end
for k = 1:numel(p.siteLines)
    [c, ls, lw] = lineStyleOf(p.siteLines(k).style);
    plot(ax, p.siteLines(k).lon, p.siteLines(k).lat, ls, 'Color', c, 'LineWidth', lw);
end
end

function [c, ls, lw] = lineStyleOf(style)
switch style
    case 'river'
        c = [0.55, 0.71, 0.82];
        ls = '-';
        lw = 1.6;
    otherwise
        c = [0.49, 0.49, 0.49];
        ls = '--';
        lw = 1.0;
end
end
