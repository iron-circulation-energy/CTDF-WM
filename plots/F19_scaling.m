function F19_scaling(e7, S, outBase, target)
%F19_SCALING Synthetic scaling fixture: M1/M2/M3 forward decision times.

if nargin < 4
    target = [];
end
T = e7.table;
[fig, P, isPanel] = panelHost(S, 5.6, 3.6, target);
ax = axes(fig, 'Position', P([0.30, 0.22, 0.66, 0.60]));
hold(ax, 'on');
h(1) = plot(ax, T.nPlants, T.tM1, '-o', 'Color', S.methodColor('M1'), 'LineWidth', 2.0, 'MarkerSize', 6, ...
    'MarkerFaceColor', S.methodColor('M1'), 'MarkerEdgeColor', 'w');
h(2) = plot(ax, T.nPlants, T.tM2, '-s', 'Color', S.methodColor('M2'), 'LineWidth', 2.0, 'MarkerSize', 6, ...
    'MarkerFaceColor', S.methodColor('M2'), 'MarkerEdgeColor', 'w');
h(3) = plot(ax, T.nPlants, T.tM3, '-^', 'Color', S.methodColor('M3'), 'LineWidth', 2.0, 'MarkerSize', 6, ...
    'MarkerFaceColor', S.methodColor('M3'), 'MarkerEdgeColor', 'w');
set(ax, 'XScale', 'log', 'YScale', 'log', 'XTick', T.nPlants);
styleAxes(ax, S, true, true);
legend(ax, h, {S.methodLabel('M1'), S.methodLabel('M2'),S.methodLabel('M3')}, 'Location', 'northoutside', 'Box', 'off');
xlabel(ax, lab(S, '改造电厂数', 'Retrofitted plants'));
ylabel(ax, lab(S, '单次决策时间/s', 'Decision time (s)'));
if ~isPanel
    annotation(fig,'textbox',[.12,.015,.84,.095],'String', ...
        {lab(S, '合成拓扑与气象；网络结构与正文设置相同，前向计算时间与权重取值无关', 'Synthetic topology and weather; network as in the main setting')}, ...
        'EdgeColor','none','HorizontalAlignment','center','FontName',S.font,'FontSize',S.fs-1.5, ...
        'Color',S.ink,'Interpreter','none');
    saveFigure(fig, outBase);
end
end
