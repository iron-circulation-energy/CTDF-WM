function F24_reliabilityValue(e1, S, outBase, target)
%F24_RELIABILITYVALUE 补充图：保留资产价值随循环铁质量（即改造情景可靠性）的变化（单图）。
%   横轴为循环铁质量；左轴为保留资产价值（原核算与“核心 + 设计、2030 年成本”核算两条线），
%   右轴为改造情景失负荷占负荷的比例；替代方案在每个质量点按该点的失负荷匹配（完全预见调度）。竖线为名义质量。
if nargin < 4
    target = [];
end
T = e1.curve;
if isempty(T)
    error('F24:noCurve', 'E1 reliability curve is empty.');
end
c = T.c / 1e6;
[fig, P, isPanel] = panelHost(S, 5.6, 3.6, target);
ax = axes(fig, 'Position', P([0.14, 0.17, 0.70, 0.74]));
hold(ax, 'on');
yyaxis(ax, 'left');
h(1) = plot(ax, c, T.RV / 1e8, '-o', 'Color', S.hero, 'LineWidth', 1.6, 'MarkerSize', 4.5, ...
    'MarkerFaceColor', S.hero, 'MarkerEdgeColor', 'w');
yC = T.RVdesign2030 / 1e8;
lbC = 'Core + design (2030 costs)';
if isfield(e1, 'acct') && isfield(e1.acct, 'summary') && isfield(e1.acct.summary, 'RV_all2030RailPolicy') ...
        && any(strcmp(T.Properties.VariableNames, 'RVall2030'))
    % 全面核算：铁路边际成本与消纳责任权重两项按名义质量的取值平移（两项取决于输送电量，随质量变化很小）
    sh = (e1.acct.summary.RV_all2030RailPolicy - e1.acct.summary.RV_all2030) / 1e8;
    yC = T.RVall2030 / 1e8 + sh;
    lbC = 'Comprehensive account (2030 costs)';
end
h(2) = plot(ax, c, yC, '--s', 'Color', S.hero, 'LineWidth', 1.2, 'MarkerSize', 4, ...
    'MarkerFaceColor', 'w', 'MarkerEdgeColor', S.hero);
plot(ax, [c(1), c(end)], [0, 0], ':', 'Color', S.axis, 'LineWidth', 0.8);
ylabel(ax, lab(S, '保留资产价值/亿元', 'Retained asset value (100 M CNY)'));
set(ax, 'YColor', S.ink);
yyaxis(ax, 'right');
h(3) = plot(ax, c, 100 * T.eueShare, '-', 'Color', S.teal, 'LineWidth', 1.2);
ylabel(ax, lab(S, '改造情景缺供电量占比/%', 'Retrofit unserved energy (% of load)'));
set(ax, 'YColor', S.teal);
if isfield(e1, 'retro') && isfield(e1.retro, 'c')
    xn = e1.retro.c / 1e6;
    yl = ylim(ax);
    plot(ax, [xn, xn], yl, '-', 'Color', S.axis, 'LineWidth', 0.8);
    text(ax, xn, yl(2), lab(S, ' 名义质量', ' nominal'), 'VerticalAlignment', 'top', 'FontSize', S.fs - 1.5, 'Color', S.tick);
end
xlabel(ax, lab(S, '循环铁质量/Mt', 'Circulating iron (Mt)'));
styleAxes(ax, S, true, false);
legend(ax, h, {lab(S, '原核算', 'Base accounting'), lbC, ...
    lab(S, '改造缺供电量', 'Retrofit unserved energy')}, 'Location', 'best', 'Box', 'off');
finishFigure(fig, S, outBase, isPanel, '');
end
