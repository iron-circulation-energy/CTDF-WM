function styleAxes(ax, S, gridY, gridX)
%STYLEAXES 二维坐标轴样式：只保留左、下边框，刻度向外，刻度文字灰色、轴标签深色，可选浅灰网格（gridY、gridX）。

if nargin < 3
    gridY = false;
end
if nargin < 4
    gridX = false;
end
set(ax, 'Box', 'off', 'TickDir', 'out', 'XColor', S.axis, 'YColor', S.axis, 'FontName', S.font, 'FontSize', S.fs, ...
    'Layer', 'bottom', 'Color', 'none', 'LineWidth', 0.6, 'TickLength', [0.012, 0.012]);
set(get(ax, 'XLabel'), 'Color', S.ink);
set(get(ax, 'YLabel'), 'Color', S.ink);
set(get(ax, 'Title'), 'Color', S.ink);
set(ax, 'YGrid', onoff(gridY), 'XGrid', onoff(gridX), 'GridColor', S.grid, 'GridAlpha', 1, 'GridLineStyle', '-');
end

function s = onoff(b)
if b
    s = 'on';
else
    s = 'off';
end
end
