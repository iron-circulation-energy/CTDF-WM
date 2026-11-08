function al = drawLegendBox(fig, pos, items, S, ncol, fs)
%DRAWLEGENDBOX 手绘图例（模板样式，无边框）：在 pos（图窗归一化）内按 ncol 列排列图例项。
%   items 为结构体数组，字段：
%     kind   'line'、'dash'、'dot'（圆点）、'tri'（下三角）、'diamond'（空心菱形）、'patch'（色块）、'band'（色带 + 中线）、
%            'ring'（空心圆）、'box'（红框）
%     color  RGB；label 文字；可选 lw（线宽）、ms（点大小）、alpha（色块透明度）。
%   与 MATLAB legend 不同，位置与间距完全确定，跨版本一致。

if nargin < 5 || isempty(ncol)
    ncol = 1;
end
if nargin < 6 || isempty(fs)
    fs = S.fs - 1;
end
n = numel(items);
nrow = ceil(n / ncol);
al = axes(fig, 'Position', pos, 'Visible', 'off');
hold(al, 'on');
xlim(al, [0, ncol]);
ylim(al, [0, nrow]);
set(al, 'YDir', 'reverse');
sw = 0.16;                                       % 符号宽度（列宽的比例）
for k = 1:n
    it = items(k);
    c = floor((k - 1) / nrow);
    r = mod(k - 1, nrow) + 0.5;
    x0 = c + 0.02;
    lw = getf(it, 'lw', 1.4);
    switch it.kind
        case 'line'
            plot(al, x0 + [0, sw], [r, r], '-', 'Color', it.color, 'LineWidth', lw);
        case 'dash'
            plot(al, x0 + [0, sw], [r, r], '--', 'Color', it.color, 'LineWidth', lw);
        case 'dot'
            plot(al, x0 + sw / 2, r, 'o', 'MarkerSize', getf(it, 'ms', 4.5), 'MarkerFaceColor', it.color, ...
                'MarkerEdgeColor', 'w', 'LineWidth', 0.5);
        case 'tri'
            plot(al, x0 + sw / 2, r, 'v', 'MarkerSize', getf(it, 'ms', 4.5), 'MarkerFaceColor', it.color, ...
                'MarkerEdgeColor', 'none');
        case 'ring'
            plot(al, x0 + sw / 2, r, 'o', 'MarkerSize', getf(it, 'ms', 4.5), 'MarkerFaceColor', 'w', ...
                'MarkerEdgeColor', it.color, 'LineWidth', 1.0);
        case 'diamond'
            plot(al, x0 + sw / 2, r, 'd', 'MarkerSize', getf(it, 'ms', 5), 'MarkerFaceColor', 'w', ...
                'MarkerEdgeColor', it.color, 'LineWidth', 1.0);
        case 'patch'
            patch(al, x0 + [0, sw, sw, 0], r + [-0.28, -0.28, 0.28, 0.28], it.color, 'EdgeColor', 'none', ...
                'FaceAlpha', getf(it, 'alpha', 1));
        case 'band'
            patch(al, x0 + [0, sw, sw, 0], r + [-0.26, -0.26, 0.26, 0.26], it.color, 'EdgeColor', 'none', ...
                'FaceAlpha', getf(it, 'alpha', 0.22));
            plot(al, x0 + [0, sw], [r, r], '-', 'Color', it.color, 'LineWidth', lw);
        case 'box'
            plot(al, x0 + [0, sw, sw, 0, 0], r + [-0.26, -0.26, 0.26, 0.26, -0.26], '-', 'Color', it.color, ...
                'LineWidth', lw);
    end
    text(al, x0 + sw + 0.03, r, it.label, 'FontName', S.font, 'FontSize', fs, 'Color', S.ink, ...
        'VerticalAlignment', 'middle', 'HorizontalAlignment', 'left');
end
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = d;
end
end
