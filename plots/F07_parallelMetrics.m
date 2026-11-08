function F07_parallelMetrics(e3, S, outBase)
%F07_PARALLELMETRICS 图 F07：常规工况下本文方法与对比方法的多指标对比（平行坐标；模板 9 右下）。
%   每个实例（测试年 × 种子）内对各方法按指标做组内归一化：得分 = (最差 − 值)/(最差 − 最好)，最优为 1（各指标均为
%   越小越好；同一实例内取值全部相同时记 1）。细线为单个实例，粗线为组均值，阴影为 25%—75% 分位带。

E = e3.episodes;
E = E(strcmp(E.scenario, 'normal'), :);
if isempty(E)
    return;
end
mets = {'cost', lab(S, '运行成本', 'Cost'); 'pF', lab(S, '断供概率', 'Starvation'); 'shedMWh', lab(S, '缺供电量', 'Unserved energy'); ...
    'curRate', lab(S, '弃电率', 'Curtailment'); 'rustBlockMWh', lab(S, '锈阻塞弃电', 'Rust-blocked curtailment'); ...
    'localFe', lab(S, '库存不足节点日', 'Short node-days'); 'maxConsRel', lab(S, '守恒误差', 'Mass error'); ...
    'decTime', lab(S, '决策时间', 'Decision time')};
names = unique(E.method, 'stable');
main = 'M1';
if ~any(strcmp(names, main))
    main = names{1};
end
inst = unique([E.year, E.seed], 'rows');
nM = size(mets, 1);
Me = zeros(0, nM);
Ot = zeros(0, nM);
for i = 1:size(inst, 1)
    R = E(E.year == inst(i, 1) & E.seed == inst(i, 2), :);
    sc = zeros(height(R), nM);
    for k = 1:nM
        v = R.(mets{k, 1});
        lo = min(v);
        hi = max(v);
        if hi - lo <= 1e-12 * max(1, abs(hi))
            sc(:, k) = 1;
        else
            sc(:, k) = (hi - v) / (hi - lo);
        end
    end
    isMain = strcmp(R.method, main);
    Me = [Me; sc(isMain, :)]; %#ok<AGROW>
    Ot = [Ot; sc(~isMain, :)]; %#ok<AGROW>
end
x = 1:nM;
fig = styledFigure(S, 7.0, 3.9);
ax = axes(fig, 'Position', [0.09, 0.22, 0.88, 0.62]);
hold(ax, 'on');
for xi = x
    plot(ax, [xi, xi], [0, 1], '-', 'Color', [0.84, 0.84, 0.84], 'LineWidth', 0.7);
end
cO = S.slate;
cM = S.methodColor(main);
for r = 1:size(Ot, 1)
    plot(ax, x, Ot(r, :), '-', 'Color', 0.18 * cO + 0.82, 'LineWidth', 0.4);
end
for r = 1:size(Me, 1)
    plot(ax, x, Me(r, :), '-', 'Color', 0.30 * cM + 0.70, 'LineWidth', 0.5);
end
h = gobjects(1, 2);
grpD = {Ot, cO, sprintf(lab(S, '对比方法（%s）', 'Comparison methods, %s'), strjoin(setdiff(names, {main}, 'stable'), lab(S, '、', ', '))); Me, cM, S.methodLabel(main)};
for g = 1:2
    D = grpD{g, 1};
    if isempty(D)
        continue;
    end
    q1 = zeros(1, nM);
    q3 = q1;
    for k = 1:nM
        qq = quantileLin(D(:, k), [0.25, 0.75]);
        q1(k) = qq(1);
        q3(k) = qq(2);
    end
    fill(ax, [x, fliplr(x)], [q1, fliplr(q3)], grpD{g, 2}, 'FaceAlpha', 0.18, 'EdgeColor', 'none');
    h(g) = plot(ax, x, mean(D, 1), '-o', 'Color', grpD{g, 2}, 'LineWidth', 2.2, 'MarkerSize', 5, ...
        'MarkerFaceColor', grpD{g, 2});
end
ok = isgraphics(h);
legend(ax, h(ok), grpD(ok, 3), 'Location', 'northoutside', 'Orientation', 'horizontal', 'Box', 'off');
set(ax, 'XTick', x, 'XTickLabel', mets(:, 2), 'XTickLabelRotation', 25);
xlim(ax, [0.8, nM + 0.2]);
ylim(ax, [-0.03, 1.05]);
styleAxes(ax, S, true);
ylabel(ax, lab(S, '逐实例组内归一化得分（最优 = 1）', 'Normalised score, best = 1'));
addNote(fig, S, sprintf(lab(S, '常规工况；%d 个实例（测试年 × 种子）', 'Normal conditions; %d test-year and seed instances'), size(inst, 1)));
saveFigure(fig, outBase);
end
