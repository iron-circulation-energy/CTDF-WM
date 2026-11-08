function N06_scenarioWinners(R, S, outBase, target)
%N06_SCENARIOWINNERS 图 6c：各情景下各省最优路线（模板“类别热力图 + 顶部折线 + 边缘条形”），检验竞争边界对
%   充电电价、风光超配、盐穴条件、特高压、还原氢耗、设备投资、改造投资、损耗、电源结构与储能服务口径的稳健性。
%   行为情景（第 1 行为基准，红框标出），列为省份（按基准自治天数从长到短）；
%   顶部折线与面积为各省最优路线与基准相同的情景比例；右侧条形为各情景中铁燃料路线（FeL、FeX、FeT）最优的省数。
%   单图（补充材料）与正文面板采用同一布局。
if nargin < 4
    target = [];
end
T = R.T;
st = natRouteStyle(S);
W = R.winners;
if ~iscell(W)
    W = cellstr(W);
end
[nP, nS] = size(W);
D = tcol(T, 'D');
[~, o] = sort(D, 'descend');
idx = zeros(nP, nS);
for k = 1:numel(st.keys)
    idx(strcmp(W, st.keys{k})) = k;
end
idx = idx(o, :);
Wo = W(o, :);
same = mean(strcmp(Wo, repmat(Wo(:, 1), 1, nS)), 2);
isFe = strcmp(Wo, 'FeL') | strcmp(Wo, 'FeX') | strcmp(Wo, 'FeT');
nFe = sum(isFe, 1);
provLab = tcol(T, 'short', tcol(T, 'name', {}));
provLab = provLab(o);
scenLab = tcol(R.scen, 'label', {});
scenName = tcol(R.scen, 'name', {});
if strcmpi(S.lang, 'en')
    provLab = provEnglish(provLab);
    scenLab = scenarioEnglish(scenName, scenLab);
end
cmapCat = [0.92, 0.92, 0.92; st.colors];

[fig, P, isPanel] = panelHost(S, 7.2, 3.6, target);
ax = axes(fig, 'Position', P([0.25, 0.29, 0.63, 0.50]));
hold(ax, 'on');
for r = 1:nS
    for c = 1:nP
        patch(ax, c + [-0.5, 0.5, 0.5, -0.5], r + [-0.5, -0.5, 0.5, 0.5], cmapCat(idx(c, r) + 1, :), ...
            'EdgeColor', 'w', 'LineWidth', 0.5);
    end
end
hlBox(ax, 0.5, 0.5, nP, 1, S, 1.2);
set(ax, 'YDir', 'reverse');
xlim(ax, [0.5, nP + 0.5]);
ylim(ax, [0.5, nS + 0.5]);
set(ax, 'XTick', [], 'YTick', 1:nS, 'YTickLabel', scenLab, 'TickLength', [0, 0], 'FontName', S.font, ...
    'FontSize', S.fs - 1.6, 'XColor', 'none', 'YColor', S.ink, 'Box', 'off', 'Color', 'none');
for c = 1:nP
    text(ax, c, nS + 0.75, provLab{c}, 'Rotation', 90, 'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle', ...
        'FontSize', S.fs - 1.8, 'Color', S.ink, 'Clipping', 'off');
end
% 顶部：同基准比例
at = axes(fig, 'Position', P([0.25, 0.81, 0.63, 0.14]));
hold(at, 'on');
xs = 1:nP;
softFill(at, xs, zeros(1, nP), 100 * same', S.teal, 0.20);
plot(at, xs, 100 * same, '-', 'Color', S.teal, 'LineWidth', 1.1);
plot(at, xs, 100 * same, 'o', 'MarkerSize', 2.6, 'MarkerFaceColor', S.teal, 'MarkerEdgeColor', 'w', 'LineWidth', 0.3);
xlim(at, [0.5, nP + 0.5]);
ylim(at, [0, 108]);
styleAxes(at, S, true, false);
text(at, -0.02 * nP, 50, mline(lab(S, {'与基准相同', '的情景/%'}, {'Scenarios with', 'base route (%)'})), 'HorizontalAlignment', 'right', ...
    'VerticalAlignment', 'middle', 'FontSize', S.fs - 1.6, 'Color', S.ink, 'Clipping', 'off');
set(at, 'XTick', [], 'XColor', 'none', 'YTick', [0, 50, 100], 'FontSize', S.fs - 1.4);
text(at, nP + 0.5, 108, sprintf(lab(S, '中位数 %.0f%%', 'median %.0f%%'), 100 * median(same)), 'HorizontalAlignment', 'right', ...
    'VerticalAlignment', 'bottom', 'FontSize', S.fs - 1.4, 'Color', S.teal, 'FontWeight', 'bold', 'Clipping', 'off');
% 右侧：各情景铁燃料路线最优省数
ar = axes(fig, 'Position', P([0.895, 0.29, 0.085, 0.50]));
hold(ar, 'on');
for r = 1:nS
    c = st.color('FeL');
    if r == 1
        c = S.hl;
    end
    patch(ar, [0, nFe(r), nFe(r), 0], r + [-0.34, -0.34, 0.34, 0.34], c, 'EdgeColor', 'none', 'FaceAlpha', 0.85);
    text(ar, nFe(r), r, sprintf(' %d', nFe(r)), 'VerticalAlignment', 'middle', 'FontSize', S.fs - 2, 'Color', S.ink);
end
plot(ar, nFe(1) * [1, 1], [0.5, nS + 0.5], ':', 'Color', S.hl, 'LineWidth', 0.7);
set(ar, 'YDir', 'reverse');
ylim(ar, [0.5, nS + 0.5]);
xlim(ar, [0, max(nFe) * 1.35 + 1]);
set(ar, 'Visible', 'off');
text(ar, 0, 0.1, lab(S, '铁路线最优省数', 'Iron-led provinces'), 'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom', ...
    'FontSize', S.fs - 1.6, 'Color', S.ink, 'Clipping', 'off');
% 图例
items = struct('kind', {}, 'color', {}, 'label', {}, 'alpha', {}, 'lw', {});
for k = 1:numel(st.keys)
    if any(idx(:) == k)
        items(end + 1) = struct('kind', 'patch', 'color', st.colors(k, :), 'label', st.labels{k}, 'alpha', 1, 'lw', 1); %#ok<AGROW>
    end
end
items(end + 1) = struct('kind', 'box', 'color', S.hl, 'label', lab(S, '基准情景', 'Base case'), 'alpha', 1, 'lw', 1.2);
drawLegendBox(fig, P([0.02, 0.0, 0.97, 0.10]), items, S, 3, S.fs - 1.6);
finishFigure(fig, S, outBase, isPanel, '');
end

function out = scenarioEnglish(names, fallback)
% 情景英文名称（与补充表 7 一致）
k = {'base', 'fullRE', 'freeSurplus', 'reLow', 'lambda125', 'lambda150', 'saltConservative', 'saltOptimistic', ...
    'uhvConstruction', 'kappa161', 'cheapTech', 'h2Service', 'young2010', 'siloHigh', 'etaEl70', ...
    'retrofit5', 'retrofit30', 'loss1pct', 'mix2024', 'pv2035', 'nh3Cheap', 'nh3Blend50', 'nh3Blend35'};
v = {'Base', 'Full renewables', 'Free surplus', 'Low renewable cost', 'Oversizing 1.25', 'Oversizing 1.5', ...
    'Salt conservative', 'Salt optimistic', 'UHV under construction', 'High hydrogen demand', 'Cheap equipment', ...
    'Hydrogen service', 'Young 2010', 'High silo cost', 'Electrolysis 0.70', ...
    'Retrofit 5%', 'Retrofit 30%', 'Loss 1% per cycle', '2024 wind–solar mix', '2035 solar-led mix', 'Cheap ammonia', ...
    'Ammonia blend ≤ 50%', 'Ammonia blend ≤ 35%'};
out = fallback;
for i = 1:numel(names)
    j = find(strcmp(k, names{i}), 1);
    if ~isempty(j)
        out{i} = v{j};
    end
end
end
