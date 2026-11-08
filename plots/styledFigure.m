function fig = styledFigure(S, w, h)
%STYLEDFIGURE 按 plotStyle 规范新建不可见图窗（宽 w、高 h，英寸），设置默认字体、字号、线宽与坐标轴样式。

fig = figure('Visible', 'off', 'Units', 'inches', 'Position', [1, 1, w, h], 'Color', 'w', 'InvertHardcopy', 'off', ...
    'PaperUnits', 'inches', 'PaperSize', [w, h], 'PaperPosition', [0, 0, w, h]);
set(fig, 'DefaultAxesFontName', S.font, 'DefaultAxesFontSize', S.fs, 'DefaultTextFontName', S.font, ...
    'DefaultTextFontSize', S.fs, 'DefaultTextColor', S.ink, 'DefaultLineLineWidth', 1.0, ...
    'DefaultAxesLineWidth', 0.6, 'DefaultAxesBox', 'off', 'DefaultAxesTickDir', 'out', ...
    'DefaultAxesTickLength', [0.012, 0.012], 'DefaultAxesXColor', S.axis, 'DefaultAxesYColor', S.axis, ...
    'DefaultAxesZColor', S.axis, 'DefaultAxesGridColor', S.grid, 'DefaultAxesGridAlpha', 1, ...
    'DefaultAxesGridLineStyle', '-');
E = struct('baseFs', S.fs, 'fs', 18, 'font', 'Times New Roman', 'weight', 'bold');
if isfield(S, 'exportFs') && ~isempty(S.exportFs), E.fs = S.exportFs; end
if isfield(S, 'exportFont') && ~isempty(S.exportFont), E.font = S.exportFont; end
setappdata(fig, 'CTDF_export', E);
try
    set(fig, 'DefaultLegendFontName', S.font, 'DefaultLegendFontSize', S.fs - 0.5, 'DefaultLegendBox', 'off');
catch
    % 部分环境不支持图例默认属性
end
end
