function N07_sustainability(Z, S, outBase, T)
%N07_SUSTAINABILITY 补充图 18：各省风光输入需求与三条燃料路线的资源指标（倾斜地图 + 尖峰 + 环带；natSustain 与 natAssess）。
%   地图按 x' = (lon − 104) + 0.55·(lat − 36)、y' = 0.62·(lat − 36) 倾斜投影，并加浅灰投影；
%   每省一簇尖峰：主尖峰高度为该省最优路线所需的年风光输入 = 稳定供电量 firmTWh / 该路线族往返效率（Z.rte），
%   颜色为路线族（铁基 FeL/FeX/FeT、绿氨 NH3L、绿氢 H2S/H2T），周围细尖峰为同一高度按固定比例缩放的装饰簇；
%   地图下方实心环带为三类路线族的最优省份占比，上方虚线弧注出每 MWh 的风光输入与净耗水（Z.reInput、Z.waterNet），
%   左上标注燃烧直接排放（Z.directCO2）；右下为尖峰高度的分布图例（低—高）。
%   T 为 natAssess 的逐省表 R.T（需 name、winner、firmTWh）；缺省时只绘地图与环带。
if nargin < 4
    T = [];
end
st = natRouteStyle(S);
famCol = [st.color('FeL'); st.color('NH3L'); 0.85 * st.color('H2T') + 0.15 * S.slate];
famLab = {lab(S, '铁基路线', 'Iron'), lab(S, '绿氨', 'Ammonia'), lab(S, '绿氢', 'Hydrogen')};
rte = tcol(Z, 'rte');
reIn = tcol(Z, 'reInput');
wN = tcol(Z, 'waterNet');
dC = tcol(Z, 'directCO2', zeros(3, 1));
tilt = @(lon, lat) deal((lon - 104) + 0.55 * (lat - 36), 0.62 * (lat - 36));
G = loadChinaMap();
fig = styledFigure(S, 7.4, 6.0);
ax = axes(fig, 'Position', [0.02, 0.10, 0.96, 0.80]);
hold(ax, 'on');
for pass = 1:2
    for i = 1:numel(G.provRings)
        for k = 1:numel(G.provRings{i})
            r = G.provRings{i}{k};
            if size(r, 1) < 20 || min(r(:, 2)) < 16
                continue;
            end
            [x, y] = tilt(r(:, 1), r(:, 2));
            if pass == 1
                patch(ax, x + 0.5, y - 0.6, [0.85, 0.87, 0.89], 'EdgeColor', 'none');
            else
                patch(ax, x, y, [0.953, 0.945, 0.925], 'EdgeColor', [0.79, 0.77, 0.73], 'LineWidth', 0.4);
            end
        end
    end
end
share = [0, 0, 0];
hmax = 1;
if ~isempty(T)
    nm = tcol(T, 'name', {});
    win = tcol(T, 'winner', {});
    firm = tcol(T, 'firmTWh', zeros(numel(nm), 1));
    fam = zeros(numel(nm), 1);
    fam(ismember(win, {'FeL', 'FeX', 'FeT'})) = 1;
    fam(strcmp(win, 'NH3L')) = 2;
    fam(ismember(win, {'H2S', 'H2T'})) = 3;
    hgt = zeros(numel(nm), 1);
    for i = 1:numel(nm)
        if fam(i) > 0 && fam(i) <= numel(rte) && rte(fam(i)) > 0
            hgt(i) = firm(i) / rte(fam(i));
        end
    end
    hmax = max([hgt; eps]);
    [~, loc] = ismember(nm, G.provName);
    lat = nan(numel(nm), 1);
    for i = 1:numel(nm)
        if loc(i) > 0
            lat(i) = G.provLabel(loc(i), 2);
        end
    end
    [~, o] = sort(lat, 'descend');
    for i = o(:)'
        if loc(i) == 0 || fam(i) == 0 || ~isfinite(lat(i))
            continue;
        end
        [bx, by] = tilt(G.provLabel(loc(i), 1), G.provLabel(loc(i), 2));
        hh = 9 * hgt(i) / hmax;
        c = famCol(fam(i), :);
        dxy = [-0.9, 0.2; -0.5, -0.4; 0.4, 0.3; 0.8, -0.2; 0.1, 0.5; -0.2, -0.6; 0.6, 0.6];
        fr = [0.45, 0.62, 0.38, 0.55, 0.30, 0.50, 0.28];
        for k = 1:size(dxy, 1)
            h2 = hh * fr(k);
            patch(ax, bx + dxy(k, 1) + [-0.16, 0.16, 0], by + dxy(k, 2) + [0, 0, h2], 0.75 * c + 0.25, 'EdgeColor', 'none', 'FaceAlpha', 0.9);
        end
        patch(ax, bx + [-0.30, 0.30, 0], by + [0, 0, hh], c, 'EdgeColor', 0.45 * c, 'LineWidth', 0.4);
        plot(ax, bx, by, 'o', 'MarkerSize', 2.4, 'MarkerFaceColor', [0.15, 0.15, 0.15], 'MarkerEdgeColor', 'none');
        if hgt(i) >= 0.55 * hmax
            nmS = regexprep(char(nm{i}), '(省|市|壮族自治区|回族自治区|维吾尔自治区|自治区)$', '');
            if strcmpi(S.lang, 'en')
                nmS = char(provEnglish({nmS}));
            end
            text(ax, bx + 0.4, by + hh + 0.2, nmS, 'FontSize', S.fs - 2, 'Color', S.ink);
        end
    end
    share = [mean(fam == 1), mean(fam == 2), mean(fam == 3)];
end
% 环带：路线族占比
cx = 2.0; cy = -1.5; R = 26.5;
t0 = 200;
for f = 1:3
    t1 = t0 + 140 * share(f);
    if share(f) > 0
        th = deg2rad(linspace(t0 + 0.6, t1 - 0.6, 80));
        plot(ax, cx + R * cos(th), cy + 0.55 * R * sin(th), '-', 'Color', famCol(f, :), 'LineWidth', 9);
        tm = deg2rad((t0 + t1) / 2);
        text(ax, cx + R * cos(tm), cy + 0.55 * R * sin(tm), sprintf('%s %.0f%%', famLab{f}, 100 * share(f)), ...
            'HorizontalAlignment', 'center', 'FontSize', S.fs - 1.5, 'FontWeight', 'bold', 'Color', 'w');
    end
    t0 = t1;
end
th = deg2rad(linspace(25, 155, 120));
plot(ax, cx + R * cos(th), cy + 0.55 * R * sin(th), '--', 'Color', S.axis, 'LineWidth', 0.8);
if numel(reIn) >= 3 && numel(wN) >= 3
    text(ax, cx, cy + 0.55 * R + 0.7, sprintf(lab(S, '每 MWh 送出电量：风光输入 %.1f / %.1f / %.1f MWh · 净耗水 %.2f / %.2f / %.2f m^3（铁 / 氨 / 氢）', ...
        'Per MWh delivered: renewable input %.1f / %.1f / %.1f MWh; net water %.2f / %.2f / %.2f m^3 (Fe / NH_3 / H_2)'), ...
        reIn(1), reIn(2), reIn(3), wN(1), wN(2), wN(3)), 'HorizontalAlignment', 'center', 'FontSize', S.fs - 1.5, 'Color', S.tick);
end
text(ax, -24, 13, sprintf(lab(S, '+%.0f kg CO_2\n燃烧直接排放', '+%.0f kg CO_2\ndirect combustion'), 1e3 * max(dC)), ...
    'HorizontalAlignment', 'center', 'FontSize', S.fs + 0.5, 'FontWeight', 'bold', 'Color', S.hero);
axis(ax, 'equal');
xlim(ax, [-30, 34]);
ylim(ax, [-18, 20]);
ax.Visible = 'off';
% 尖峰高度图例（低—高）
al = axes(fig, 'Position', [0.81, 0.11, 0.15, 0.10]);
hold(al, 'on');
g = linspace(0, 1, 100);
dens = exp(-((g - 0.85) / 0.12) .^ 2) + 0.15 * g;
for k = 1:99
    patch(al, g([k, k + 1, k + 1, k]), [0, 0, dens(k + 1), dens(k)], mapColors(S.warm, 0.2 + 0.8 * g(k)), 'EdgeColor', 'none');
end
set(al, 'XTick', [0.05, 0.95], 'XTickLabel', {lab(S, '低', 'Low'), lab(S, '高', 'High')}, 'YTick', [], 'Box', 'off', ...
    'FontSize', S.fs - 1.5, 'XColor', S.axis, 'YColor', 'none');
xlabel(al, sprintf(lab(S, '尖峰高度：年风光输入（最高 %.0f TWh）', 'Spike: renewable input (max %.0f TWh)'), hmax), 'FontSize', S.fs - 1.5);
items = struct('kind', {'patch', 'patch', 'patch'}, 'color', {famCol(1, :), famCol(2, :), famCol(3, :)}, ...
    'label', famLab, 'alpha', {1, 1, 1}, 'lw', {1, 1, 1});
drawLegendBox(fig, [0.03, 0.80, 0.18, 0.12], items, S, 1, S.fs - 1);
addNote(fig, S, '');
saveFigure(fig, outBase);
end
