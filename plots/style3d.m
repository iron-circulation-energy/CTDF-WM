function style3d(ax, S)
%STYLE3D 三维坐标轴样式：透明背景、浅灰网格与轴线、灰色刻度文字、深色轴标签。

set(ax, 'Box', 'off', 'Color', 'none', 'XGrid', 'on', 'YGrid', 'on', 'ZGrid', 'on', 'GridColor', S.grid, ...
    'GridAlpha', 1, 'XColor', S.axis, 'YColor', S.axis, 'ZColor', S.axis, 'FontName', S.font, ...
    'FontSize', S.fs - 0.5, 'LineWidth', 0.6, 'TickDir', 'out');
set(get(ax, 'XLabel'), 'Color', S.ink);
set(get(ax, 'YLabel'), 'Color', S.ink);
set(get(ax, 'ZLabel'), 'Color', S.ink);
end
