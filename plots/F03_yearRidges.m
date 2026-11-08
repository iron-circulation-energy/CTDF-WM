function F03_yearRidges(W, p, S, outBase)
%F03_YEARRIDGES 图 F03：逐年风光日电量相对季节基准的分布（山脊图；模板 5 左下）。
%   比值 r = (EW + ES)/(capW·24·cfW(doy) + capS·24·cfS(doy))（与 classifyRegime 口径一致），每行一个气象年，
%   白色竖线为中位数，虚线为低风光阈值 regLow 与富余阈值 regHigh，右侧为该年低风光日占比；右缘标注训练/验证/测试划分。

w = p.weather;
Y = numel(W);
yl = arrayfun(@(y) sprintf(lab(S, '第%d年', 'Year %d'), y), 1:Y, 'UniformOutput', false);
if isfield(w, 'era5') && strcmpi(w.source, 'csv') && numel(w.era5.years) >= Y
    yl = arrayfun(@(y) sprintf('%d', y), w.era5.years(1:Y), 'UniformOutput', false);
end
doy = 1:365;
cfW = w.cfW0 + w.cfWamp * cos(2 * pi * (doy - w.cfWpeak) / 365);
cfS = w.cfS0 + w.cfSamp * cos(2 * pi * (doy - w.cfSpeak) / 365);
base = p.re.capW * 24 * cfW + p.re.capS * 24 * cfS;
x = linspace(0, 2.3, 400);
step = 0.62;
fig = styledFigure(S, 5.8, min(9.5, 1.5 + 0.21 * Y));
ax = axes(fig, 'Position', [0.12, 0.08, 0.70, 0.86]);
hold(ax, 'on');
for i = 1:Y
    r = (W(i).EW(1:365) + W(i).ES(1:365)) ./ base;
    k = kde1(r, x);
    k = k / max(max(k), eps) * 1.15;
    b0 = -(i - 1) * step;
    col = mapColors(S.year, (i - 1) / max(Y - 1, 1));
    fill(ax, [x, fliplr(x)], [b0 + k, b0 * ones(size(x))], col, 'EdgeColor', 'none', 'FaceAlpha', 0.95);
    plot(ax, x, b0 + k, '-', 'Color', 'w', 'LineWidth', 0.8);
    plot(ax, x([1, end]), [b0, b0], '-', 'Color', [0.73, 0.73, 0.73], 'LineWidth', 0.5);
    md = median(r);
    plot(ax, [md, md], [b0, b0 + interp1(x, k, md)], '-', 'Color', 'w', 'LineWidth', 1.1);
    text(ax, -0.04, b0 + 0.12, yl{i}, 'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', ...
        'FontSize', S.fs - 1.2, 'Color', [0.33, 0.33, 0.33]);
    text(ax, 2.33, b0 + 0.12, sprintf('%.1f%%', 100 * mean(r < w.regLow)), 'VerticalAlignment', 'bottom', ...
        'FontSize', S.fs - 1.5, 'Color', [0.48, 0.48, 0.48]);
end
yBot = -(Y - 1) * step - 0.3;
for v = [w.regLow, w.regHigh]
    plot(ax, [v, v], [yBot, 1.5], '--', 'Color', [0.43, 0.43, 0.43], 'LineWidth', 0.7);
end
text(ax, w.regLow, 1.6, sprintf(lab(S, '低风光阈值 %.1f', 'low threshold %.1f'), w.regLow), 'HorizontalAlignment', 'center', ...
    'FontSize', S.fs - 1, 'Color', [0.43, 0.43, 0.43]);
text(ax, w.regHigh, 1.6, sprintf(lab(S, '富余阈值 %.1f', 'surplus threshold %.1f'), w.regHigh), 'HorizontalAlignment', 'center', ...
    'FontSize', S.fs - 1, 'Color', [0.43, 0.43, 0.43]);
text(ax, 2.33, 1.05, sprintf(lab(S, '低风光\n日占比', 'low-renewable\nday share')), 'VerticalAlignment', 'bottom', 'FontSize', S.fs - 1.5, ...
    'Color', [0.48, 0.48, 0.48]);
sets = {w.train, lab(S, '训练', 'train'); w.val, lab(S, '验证', 'validation'); w.test, lab(S, '测试', 'test')};
for k = 1:3
    ys = sets{k, 1};
    if isempty(ys)
        continue;
    end
    y0 = -(min(ys) - 1) * step + 0.5;
    y1 = -(max(ys) - 1) * step + 0.08;
    plot(ax, [2.60, 2.60], [y1, y0], '-', 'Color', [0.6, 0.6, 0.6], 'LineWidth', 0.9, 'Clipping', 'off');
    text(ax, 2.63, (y0 + y1) / 2, sets{k, 2}, 'FontSize', S.fs - 0.5, 'Color', [0.33, 0.33, 0.33], ...
        'Clipping', 'off');
end
xlim(ax, [-0.02, 2.3]);
ylim(ax, [yBot, 1.9]);
styleAxes(ax, S);
ax.YAxis.Visible = 'off';
xlabel(ax, lab(S, '风光日电量 / 季节基准（白线为中位数）', 'Daily renewable energy / seasonal baseline'));
addNote(fig, S, '');
saveFigure(fig, outBase);
end
