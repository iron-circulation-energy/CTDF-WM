function h = badge(ax, x, y, txt, S, col, varargin)
%BADGE 关键数字徽标：浅色底、彩色细边框的文字框（模板中的均值与名次标注、图内结论）。
%   h = badge(ax, x, y, txt, S, col, 名称-值...)，col 为文字与边框颜色；其余参数传给 text（如 'Units','normalized'）。
if nargin < 6 || isempty(col)
    col = S.hero;
end
h = text(ax, x, y, txt, 'Color', col, 'FontName', S.font, 'FontSize', S.fs - 0.5, 'FontWeight', 'bold', ...
    'BackgroundColor', 0.10 * col + 0.90 * [1, 1, 1], 'EdgeColor', 0.55 * col + 0.45 * [1, 1, 1], ...
    'LineWidth', 0.6, 'Margin', 1.5, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', varargin{:});
end
