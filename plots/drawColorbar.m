function ac = drawColorbar(fig, pos, cmap, lims, ticks, tickLabels, label, S, orient)
%DRAWCOLORBAR 细色标（模板样式）：在 pos（图窗归一化）处用独立坐标轴绘制色带，无边框、刻度向外。
%   cmap 为 K×3 色图，lims = [lo hi] 为色带两端对应的数值；ticks 为刻度数值（空时自动 5 个），tickLabels 为刻度文字
%   （空时按 %g）；label 为色标标题；orient 为 'v'（缺省，刻度在右、标题竖排在右）、'vt'（刻度在右、标题在上）
%   或 'h'（刻度在下，标题在上）。
%   与 MATLAB colorbar 不同，本函数不依赖坐标轴的 colormap，可在同一图窗中放多个不同色图的色标。

if nargin < 9 || isempty(orient)
    orient = 'v';
end
if isempty(ticks)
    ticks = linspace(lims(1), lims(2), 5);
end
if isempty(tickLabels)
    tickLabels = arrayfun(@(v) sprintf('%g', v), ticks, 'UniformOutput', false);
end
K = size(cmap, 1);
img = reshape(cmap, [K, 1, 3]);
v = linspace(lims(1), lims(2), K);
ac = axes(fig, 'Position', pos);
if strcmpi(orient, 'h')
    image(ac, v, [0, 1], permute(img, [2, 1, 3]));
    set(ac, 'YDir', 'normal', 'YTick', [], 'XTick', ticks, 'XTickLabel', tickLabels, 'XAxisLocation', 'bottom');
    xlim(ac, lims);
    ylim(ac, [0, 1]);
    if ~isempty(label)
        text(ac, lims(1), 1.25, label, 'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom', ...
            'FontSize', S.fs - 1, 'Color', S.ink, 'FontName', S.font, 'Clipping', 'off');
    end
else
    image(ac, [0, 1], v, img);
    set(ac, 'YDir', 'normal', 'XTick', [], 'YTick', ticks, 'YTickLabel', tickLabels, 'YAxisLocation', 'right');
    ylim(ac, lims);
    xlim(ac, [0, 1]);
    if strcmpi(orient, 'vt')
        text(ac, 0, lims(2) + 0.04 * diff(lims), label, 'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom', ...
            'FontSize', S.fs - 1, 'Color', S.ink, 'FontName', S.font, 'Clipping', 'off');
    else
        yl = ylabel(ac, label);
        set(yl, 'FontSize', S.fs - 0.5, 'Color', S.ink, 'FontName', S.font);
    end
end
set(ac, 'Box', 'off', 'TickDir', 'out', 'TickLength', [0.02, 0.02], 'XColor', S.tick, 'YColor', S.tick, ...
    'FontName', S.font, 'FontSize', S.fs - 1, 'LineWidth', 0.5, 'Layer', 'top');
end
