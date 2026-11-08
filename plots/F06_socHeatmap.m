function F06_socHeatmap(tr, p, S, outBase, yrLabel)
%F06_SOCHEATMAP 补充图 5：测试年全网荷电状态与各节点库存裕度（模板“热力图 + 顶部曲线 + 红框”）。
%   热力图：行为电厂（铁裕度 μ^Fe_i / 满发日燃铁量）与还原站（锈裕度 μ^Ox_j / 日还原能力），单位为“日数”，
%   列为评估期各周（周均值）；0 为中间色，负值（赭色）表示预测裕度不足；红框标出全表最小值所在单元格。
%   顶部：周均荷电状态（面积 + 折线）与预测铁裕度不足周（▼）。tr：runEpisode 的 trace；yrLabel：横轴说明中的年份文字。

if nargin < 5
    yrLabel = lab(S, '测试年', 'Test year');
end
ev = (tr.warmup + 1):numel(tr.soc);
nP = size(tr.muFe, 1);
Z = [tr.muFe(:, ev) ./ p.plant.dailyFull(:); tr.muOx(:, ev) ./ p.station.rhoMax(:)];
nW = floor(numel(ev) / 7);
if nW < 2
    return;
end
k7 = 1:7 * nW;
nr = size(Z, 1);
Zw = reshape(mean(reshape(Z(:, k7), nr, 7, nW), 2), nr, nW);
socW = 100 * mean(reshape(tr.soc(ev(k7)), 7, nW), 1);
evF = any(reshape(any(tr.muFe(:, ev(k7)) < 0, 1), 7, nW), 1);
rowNames = [nodeLabels(p, S, p.plant.names, ''); nodeLabels(p, S, p.station.names, lab(S, '（锈）', ' (rust)'))];
vmin = min(min(Zw(:)), -1);
vmax = max(max(Zw(:)), 1);
cm = flipud(S.div);
fig = styledFigure(S, 7.0, 1.9 + 0.30 * nr);
ax = axes(fig, 'Position', [0.19, 0.14, 0.69, 0.58]);
hold(ax, 'on');
for r = 1:nr
    for w = 1:nW
        patch(ax, w + [-0.5, 0.5, 0.5, -0.5], r + [-0.5, -0.5, 0.5, 0.5], mapColors(cm, twoSlope(Zw(r, w), vmin, vmax)), ...
            'EdgeColor', 'w', 'LineWidth', 0.5);
    end
end
plot(ax, [0.5, nW + 0.5], [nP + 0.5, nP + 0.5], '-', 'Color', 'w', 'LineWidth', 2.5);
[zMin, iMin] = min(Zw(:));
[rMin, wMin] = ind2sub(size(Zw), iMin);
hlBox(ax, wMin - 0.5, rMin - 0.5, 1, 1, S, 1.4);
text(ax, wMin + 0.7, rMin, sprintf('%.1f d', zMin), 'Color', S.hl, 'FontSize', S.fs - 1.2, 'FontWeight', 'bold', ...
    'VerticalAlignment', 'middle');
set(ax, 'YDir', 'reverse');
xlim(ax, [0.5, nW + 0.5]);
ylim(ax, [0.5, nr + 0.5]);
xlabel(ax, sprintf(lab(S, '%s周序号', 'Week of %s'), regexprep(char(yrLabel), '\s*年$', '')));
styleAxes(ax, S);
set(ax, 'YTick', 1:nr, 'YTickLabel', rowNames, 'TickLength', [0, 0], 'YColor', S.tick, 'FontSize', S.fs - 0.5);
tv = unique([ceil(vmin), 0, floor(vmax / 2), floor(vmax)]);
drawColorbar(fig, [0.905, 0.14, 0.018, 0.48], mapColors(cm, twoSlope(linspace(vmin, vmax, 256), vmin, vmax)), ...
    [vmin, vmax], tv, arrayfun(@num2str, tv, 'UniformOutput', false), lab(S, '裕度/日', 'Margin (d)'), S, 'vt');
% 顶部：荷电状态
at = axes(fig, 'Position', [0.19, 0.76, 0.69, 0.17]);
hold(at, 'on');
yTop = min(100, max(socW) + 18);
yBot = max(0, min(socW) - 10);
softFill(at, 1:nW, yBot * ones(1, nW), socW, S.teal, 0.18);
plot(at, 1:nW, socW, '-o', 'Color', S.teal, 'LineWidth', 1.2, 'MarkerSize', 2.6, 'MarkerFaceColor', S.teal, 'MarkerEdgeColor', 'w');
if any(evF)
    plot(at, find(evF), yTop * ones(1, nnz(evF)), 'v', 'MarkerSize', 4, 'MarkerFaceColor', S.hl, 'MarkerEdgeColor', 'none');
end
xlim(at, [0.5, nW + 0.5]);
ylim(at, [yBot, yTop + 6]);
ylabel(at, 'SOC (%)');
styleAxes(at, S, true);
set(at, 'XTick', [], 'XColor', 'none');
drawLegendBox(fig, [0.48, 0.945, 0.50, 0.05], struct('kind', {'tri', 'box'}, 'color', {S.hl, S.hl}, ...
    'label', {lab(S, '预测铁裕度不足周', 'Negative-margin weeks'), lab(S, '最小裕度', 'Minimum margin')}, ...
    'alpha', {1, 1}, 'lw', {1, 1.4}), S, 2, S.fs - 1.4);
addNote(fig, S, '');
saveFigure(fig, outBase);
end

function rowNames = nodeLabels(p, S, ids, suffix)
rowNames = ids(:);
if isfield(p, 'site')
    sid = {p.site.id};
    for k = 1:numel(rowNames)
        j = find(strcmp(sid, rowNames{k}), 1);
        if ~isempty(j)
            rowNames{k} = lab(S, p.site(j).short, siteEnglish(p.site(j).id, p.site(j).short));
        end
    end
end
rowNames = strcat(rowNames, suffix);
end
