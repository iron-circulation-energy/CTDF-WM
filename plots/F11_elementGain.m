function F11_elementGain(e5, S, outBase, target)
%F11_ELEMENTGAIN 图 4b：CTDF-WM 各要素带来的提升与显著性（火山图，图内竖色带为各要素平均提升；E5）。
%   每个点为“要素 × 指标”：横轴为提升 (对照值 − CTDF-WM 值)/|对照值|（截断到 [−60%, 100%]），对照模型仅在该要素上不同；
%   纵轴为 −log10 P，P 为配对 t 检验（运行指标 pF、ShedMWh、Cost 按 e5.episodes 的年份 × 种子 × 工况配对；
%   预测指标 ConsErrT、NegFrac、W1 按 e5.raw 的种子配对；样本不足时 P 记为 NaN，点落在横轴上）。
%   虚线为 P = 0.05 与提升 10%；右上浅红区为显著提升区；点大小 ∝ 提升；红圈为断供风险提升最大的要素；
%   竖色带为各要素在全部可用指标上的平均提升。CTDF-WM 的指标取值列于图注；某指标对 CTDF-WM 或对照不可用时标为 NA。
if nargin < 4
    target = [];
end
% 逐状态预测记录（最终 γ），先对种子取平均，再按状态配对；四个对照模型与 CTDF-WM 的决策完全相同，故只比较预测指标
PR = e5.predictionRaw;
gm = max(PR.gamma);
PR = PR(abs(PR.gamma - gm) < 1e-12, :);
nmAll = {'full', 'noNull', 'noTerminal', 'gauss', 'noCurr'};
enName = containers.Map(nmAll, {'CTDF-WM', 'Velocity projection', 'Terminal projection', 'Dirichlet source', ...
    'Horizon curriculum'});
mt = {'ConsErrT', 'Mass error'; 'NegFrac', 'Negative samples'; 'W1', 'W_1 distance'; ...
    'ValueErr', 'Value error'; 'RiskErr', 'Risk error'};
mt = mt(ismember(mt(:, 1), PR.Properties.VariableNames), :);
meth = cellstr(PR.Method);
st = PR.state;
us = unique(st);
names = nmAll(ismember(nmAll, meth));
if ~any(strcmp(names, 'full'))
    return;
end
rows = setdiff(names, {'full'}, 'stable');
nr = numel(rows);
nc = size(mt, 1);
A = struct();                                            % A.(metric)(method, state)
for b = 1:nc
    M = nan(numel(names), numel(us));
    v = PR.(mt{b, 1});
    for a = 1:numel(names)
        for q = 1:numel(us)
            sel = strcmp(meth, names{a}) & st == us(q) & isfinite(v);
            if any(sel), M(a, q) = mean(v(sel)); end
        end
    end
    A.(mt{b, 1}) = M;
end
iF = find(strcmp(names, 'full'), 1);
G = nan(nr, nc);
Pv = nan(nr, nc);
for b = 1:nc
    M = A.(mt{b, 1});
    b0 = mean(M(iF, :), 'omitnan');
    for a = 1:nr
        ia = find(strcmp(names, rows{a}), 1);
        v = mean(M(ia, :), 'omitnan');
        if isfinite(v) && isfinite(b0) && abs(v) > eps
            G(a, b) = max(-0.6, min(1, (v - b0) / abs(v)));
        end
        d = M(ia, :) - M(iF, :);
        d = d(isfinite(d));
        if numel(d) >= 2 && std(d) > 0
            t = mean(d) / (std(d) / sqrt(numel(d)));
            df = numel(d) - 1;
            Pv(a, b) = betainc(df / (df + t ^ 2), df / 2, 0.5);
        end
    end
end
rowLab = cellfun(@(n) enName(n), rows, 'UniformOutput', false);
pal = [S.hero; S.slate; S.teal; S.sand; S.sky; S.mute];
mk = {'o', 's', '^', 'd', 'v', 'p'};                     % 形状区分指标，颜色区分要素
Y = -log10(Pv);
Y(~isfinite(Y)) = 0;
ycap = 20;                                               % 守恒类指标的 P 值极小，纵轴截断于 20 并以空心标出
capped = Y > ycap;
Y = min(Y, ycap);
ymax = ycap * 1.08;
thr = -log10(0.05);
[fig, P, isPanel] = panelHost(S, 6.4, 4.8, target);
ax = axes(fig, 'Position', P([0.13, 0.14, 0.84, 0.80]));
hold(ax, 'on');
patch(ax, [-0.65, 1.05, 1.05, -0.65], [0, 0, thr, thr], [0.95, 0.955, 0.96], 'EdgeColor', 'none');
patch(ax, [0, 1.05, 1.05, 0], [thr, thr, ymax, ymax], [0.985, 0.925, 0.905], 'EdgeColor', 'none');
plot(ax, [-0.65, 1.05], [thr, thr], '--', 'Color', S.ink, 'LineWidth', 0.7);
plot(ax, [0, 0], [0, ymax], '-', 'Color', S.axis, 'LineWidth', 0.6);
for a = 1:nr
    c = pal(1 + mod(a - 1, size(pal, 1)), :);
    for b = 1:nc
        if ~isfinite(G(a, b))
            continue;
        end
        m = mk{1 + mod(b - 1, numel(mk))};
        if Y(a, b) > thr
            fc = c;
            if capped(a, b), fc = 'w'; end
            scatter(ax, G(a, b), Y(a, b), 60, c, m, 'filled', 'MarkerFaceColor', fc, 'MarkerEdgeColor', c, 'LineWidth', 1.2);
        else
            scatter(ax, G(a, b), Y(a, b), 34, [0.70, 0.74, 0.78], m, 'filled', 'MarkerEdgeColor', 'w', 'LineWidth', 0.4);
        end
    end
end
xlim(ax, [-0.65, 1.05]);
ylim(ax, [0, ymax]);
styleAxes(ax, S);
set(ax, 'XTick', -0.5:0.25:1, 'XTickLabel', arrayfun(@(v) sprintf('%.0f%%', 100 * v), -0.5:0.25:1, 'UniformOutput', false), ...
    'YTick', 0:5:20, 'YTickLabel', {'0', '5', '10', '15', '\geq20'});
xlabel(ax, lab(S, '要素带来的提升', 'Improvement from the element'));
ylabel(ax, '-log_{10} P');
text(ax, -0.62, thr, 'P = 0.05', 'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom', ...
    'FontSize', S.fs - 1.5, 'Color', S.ink);
% 图例：左上为要素（颜色），其下为指标（形状）
items = struct('kind', {}, 'color', {}, 'label', {}, 'alpha', {}, 'lw', {});
for a = 1:nr
    items(end + 1) = struct('kind', 'dot', 'color', pal(1 + mod(a - 1, size(pal, 1)), :), 'label', rowLab{a}, ...
        'alpha', 1, 'lw', 1); %#ok<AGROW>
end
drawLegendBox(fig, P([0.15, 0.70, 0.36, 0.22]), items, S, 1, S.fs - 1.6);
al = axes(fig, 'Position', P([0.15, 0.42, 0.36, 0.26]), 'Visible', 'off');
hold(al, 'on');
xlim(al, [0, 1]);
shown = find(any(isfinite(G), 1));                      % 只列出有数值的指标
ylim(al, [0.5, max(numel(shown), 1) + 0.5]);
set(al, 'YDir', 'reverse');
for r = 1:numel(shown)
    b = shown(r);
    plot(al, 0.06, r, mk{1 + mod(b - 1, numel(mk))}, 'MarkerSize', 6, 'MarkerFaceColor', [0.45, 0.45, 0.45], ...
        'MarkerEdgeColor', [0.45, 0.45, 0.45]);
    text(al, 0.14, r, mt{b, 2}, 'FontSize', S.fs - 1.6, 'Color', S.ink, 'VerticalAlignment', 'middle');
end
finishFigure(fig, S, outBase, isPanel, sprintf('Paired over %d states at \\gamma = %.2f; grey: P \\geq 0.05; open: P < 10^{-20}', ...
    numel(us), gm));
end

function p = pairedP(T, key, a, b, f, by)
%PAIREDP 配对 t 检验的双侧 P 值（不依赖统计工具箱）：按 by 列对齐 key = a 与 key = b 两组的 f 列。
p = NaN;
if isempty(T)
    return;
end
k = tcol(T, key, {});
v = tcol(T, f);
if isempty(k) || isempty(v)
    return;
end
ia = find(strcmp(k, a));
ib = find(strcmp(k, b));
if isempty(ia) || isempty(ib)
    return;
end
keyOf = @(i) strjoin(cellfun(@(c) toStr(tcol(T, c, {}), i), by, 'UniformOutput', false), '|');
ka = arrayfun(keyOf, ia, 'UniformOutput', false);
kb = arrayfun(keyOf, ib, 'UniformOutput', false);
[~, xa, xb] = intersect(ka, kb, 'stable');
d = v(ib(xb)) - v(ia(xa));
d = d(isfinite(d));
n = numel(d);
if n < 2 || std(d) == 0
    return;
end
t = mean(d) / (std(d) / sqrt(n));
df = n - 1;
p = betainc(df / (df + t ^ 2), df / 2, 0.5);
end

function s = toStr(c, i)
if isempty(c)
    s = '';
elseif iscell(c)
    s = char(string(c{i}));
else
    s = sprintf('%g', c(i));
end
end
