function h = hlBox(ax, x0, y0, w, hgt, S, lw)
%HLBOX 红框高亮（模板 7：月份 × 时刻热力图中的最大值单元格）：在数据坐标 (x0, y0, w, hgt) 处画红色矩形框。
if nargin < 7 || isempty(lw)
    lw = 1.4;
end
h = plot(ax, x0 + [0, w, w, 0, 0], y0 + [0, 0, hgt, hgt, 0], '-', 'Color', S.hl, 'LineWidth', lw, 'Clipping', 'off');
end
