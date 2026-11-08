function ia = addNanhaiInset(fig, S, pos, names, cols)
%ADDNANHAIINSET 全国图右下角的南海诸岛小图（与主图相同的分级设色与南海断续线），pos 为归一化位置。
ia = axes(fig, 'Position', pos);
drawProvMap(ia, S, [106.5, 123.0, 3.0, 23.5], names, cols, struct('edge', 0.3));
set(ia, 'XColor', [0.55, 0.55, 0.55], 'YColor', [0.55, 0.55, 0.55], 'LineWidth', 0.7);
text(ia, 122.6, 3.6, lab(S, '南海诸岛', 'South China Sea Islands'), 'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', ...
    'FontSize', S.fs - 2, 'Color', [0.35, 0.35, 0.35]);
end
