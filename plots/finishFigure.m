function finishFigure(fig, S, outBase, isPanel, note)
%FINISHFIGURE 单图加注记并保存；正文面板由 paperFigures 统一保存。
if isPanel
    return;
end
if nargin >= 5 && ~isempty(note)
    addNote(fig, S, note);
else
    addNote(fig, S, '');
end
saveFigure(fig, outBase);
end
