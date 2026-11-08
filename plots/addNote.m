function addNote(fig, S, txt)
%ADDNOTE 在图窗右下角标注说明文字（如数据性质、近似位置）；S.note（冒烟算例提示）非空时一并标注。
%   文字按 TeX 解释（可写 P_F、W_1 等下标），说明中不要出现未转义的 \ 与 ^。

parts = {};
if nargin >= 3 && ~isempty(txt)
    parts{end + 1} = txt;
end
if ~isempty(S.note)
    parts{end + 1} = S.note;
end
if isempty(parts)
    return;
end
annotation(fig, 'textbox', [0.30, 0.0, 0.695, 0.035], 'String', strjoin(parts, lab(S, '；', '; ')), 'EdgeColor', 'none', ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', 'Color', [0.69, 0.23, 0.18], ...
    'FontName', S.font, 'FontSize', S.fs - 1.5, 'Interpreter', 'tex', 'FitBoxToText', 'off');
end
