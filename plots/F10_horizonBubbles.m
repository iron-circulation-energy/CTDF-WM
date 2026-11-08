function F10_horizonBubbles(e4, S, outBase, target)
%F10_HORIZONBUBBLES 图 4a：预测误差随有效时域的变化（分组箱线 + 抖动散点 + 顶部显著性字母；E4）。
%   每种方法一组浅色底带，组内按有效时域 (1 − γ)^(−1) 排列箱体；箱体为四分位，须线为 5%—95% 分位，
%   散点为逐状态/测试年/种子的 Wasserstein 误差（e4.raw，确定性抖动；无 raw 时以 table 的 W1、W1lo、W1hi 三点代表）；
%   白色菱形为组均值，标记面积与相对价值误差 ValueErr 成正比（Tag 'PredictionDistance'）；
%   顶部字母：中位数自助 95% 区间互不重叠的箱体字母不同（共享字母表示差异不显著）；
%   组右上徽标为最长时域相对最短时域的中位误差倍数；超过闭环周转时间 T_loop 的时域箱体下方加浅色底
%   （首条分隔线 Tag 'MaterialLoopTime'，UserData = T_loop）。纵轴为对数。
%   函数名沿用旧版（气泡图），以保持 paperFigures 与 runExperiments 的调用不变。
if nargin < 4
    target = [];
end
T = e4.table;
R = [];
if isfield(e4, 'raw') && ~isempty(e4.raw)
    R = e4.raw;
    T = summarizePredictionAccuracy(R);
end
mth = tcol(T, 'Method', {});
H = tcol(T, 'Horizon');
w1 = tcol(T, 'W1');
wlo = tcol(T, 'W1lo', w1);
whi = tcol(T, 'W1hi', w1);
ve = tcol(T, 'ValueErr', nan(size(w1)));
Tl = NaN;
if isfield(e4, 'Tloop')
    Tl = e4.Tloop;
end
ordM = [S.methodOrder, setdiff(unique(mth)', S.methodOrder)];
meths = ordM(ismember(ordM, mth));
hz = unique(H(isfinite(H) & H > 0))';
nh = numel(hz);
if isempty(meths) || nh == 0
    return;
end
vmax = max(ve(isfinite(ve) & ve > 0));
if isempty(vmax)
    vmax = 1;
end
gap = 0.9;
pos = @(g, j) (g - 1) * (nh + gap) + j;
[fig, P, isPanel] = panelHost(S, 6.8, 4.4, target);
ax = axes(fig, 'Position', P([0.12, 0.20, 0.84, 0.66]));
hold(ax, 'on');
set(ax, 'YScale', 'log');
allv = [];
box = struct('x', {}, 'v', {}, 'med', {}, 'ci', {}, 'm', {}, 'h', {});
rs = RandStream('twister', 'Seed', 7);
for g = 1:numel(meths)
    m = meths{g};
    for j = 1:nh
        if isempty(R)
            s = strcmp(mth, m) & H == hz(j);
            v = [wlo(s); w1(s); whi(s)];
        else
            s = strcmp(tcol(R, 'Method', {}), m) & tcol(R, 'Horizon') == hz(j);
            v = tcol(R, 'W1');
            v = v(s);
        end
        v = v(isfinite(v) & v > 0);
        if isempty(v)
            continue;
        end
        allv = [allv; v(:)]; %#ok<AGROW>
        med = quantileLin(v, 0.5);
        bm = zeros(200, 1);
        for b = 1:200
            bm(b) = quantileLin(v(randi(rs, numel(v), numel(v), 1)), 0.5);
        end
        box(end + 1) = struct('x', pos(g, j), 'v', v(:), 'med', med, 'ci', quantileLin(bm, [0.025, 0.975]), 'm', m, 'h', hz(j)); %#ok<AGROW>
    end
end
if isempty(box)
    return;
end
yl = [0.6 * min(allv), 2.2 * max(allv)];
for g = 1:numel(meths)
    c = S.methodColor(meths{g});
    patch(ax, pos(g, 1) - 0.6 + [0, nh + 0.2, nh + 0.2, 0], yl([1, 1, 2, 2]), c, 'FaceAlpha', 0.05, 'EdgeColor', 'none');
    if isfinite(Tl)
        jb = find(hz > Tl, 1);
        if ~isempty(jb)
            xb = pos(g, jb) - 0.5;
            patch(ax, [xb, pos(g, nh) + 0.5, pos(g, nh) + 0.5, xb], yl(1) * [1, 1, 1.25, 1.25], S.cream, 'EdgeColor', 'none');
            hL = plot(ax, [xb, xb], yl, ':', 'Color', S.tick, 'LineWidth', 0.6, 'UserData', Tl);
            if g == 1
                hL.Tag = 'MaterialLoopTime';
            end
        end
    end
end
mx = nan(1, numel(box));
my = nan(1, numel(box));
ms = nan(1, numel(box));
for b = 1:numel(box)
    c = S.methodColor(box(b).m);
    v = box(b).v;
    x = box(b).x;
    q = quantileLin(v, [0.05, 0.25, 0.5, 0.75, 0.95]);
    scatter(ax, x + jit(numel(v), 0.36), v, 6, c, 'filled', 'MarkerFaceAlpha', 0.30, 'MarkerEdgeColor', 'none');
    plot(ax, [x, x], q([1, 2]), '-', 'Color', c, 'LineWidth', 1.0);
    plot(ax, [x, x], q([4, 5]), '-', 'Color', c, 'LineWidth', 1.0);
    if q(4) > q(2)
        patch(ax, x + 0.27 * [-1, 1, 1, -1], q([2, 2, 4, 4]), [1, 1, 1], 'FaceAlpha', 0.55, 'EdgeColor', c, 'LineWidth', 1.3);
    end
    plot(ax, x + 0.27 * [-1, 1], q([3, 3]), '-', 'Color', c, 'LineWidth', 1.8);
    mx(b) = x;
    my(b) = mean(v);
    sr = strcmp(mth, box(b).m) & H == box(b).h;
    if any(sr) && isfinite(ve(find(sr, 1)))
        ms(b) = max(120 * ve(find(sr, 1)) / vmax, eps);
    else
        ms(b) = 20;
    end
end
scatter(ax, mx, my, ms, [1, 1, 1], 'd', 'MarkerEdgeColor', S.ink, 'LineWidth', 0.8, 'Tag', 'PredictionDistance');
% 显著性字母：按中位数排序，自助区间重叠的连续箱体共享字母
[~, o] = sort([box.med]);
letters = repmat({''}, 1, numel(box));
L = 'a';
i0 = 1;
while i0 <= numel(o)
    i1 = i0;
    while i1 < numel(o) && box(o(i1 + 1)).ci(1) <= box(o(i0)).ci(2)
        i1 = i1 + 1;
    end
    for t = i0:i1
        if ~contains(letters{o(t)}, L)
            letters{o(t)} = [letters{o(t)}, L];
        end
    end
    L = char(L + 1);
    i0 = i1 + 1;
end
for b = 1:numel(box)
    text(ax, box(b).x, yl(2) / 1.18, letters{b}, 'HorizontalAlignment', 'center', 'FontSize', S.fs - 1, 'Color', S.ink);
end
for g = 1:numel(meths)
    c = S.methodColor(meths{g});
    sb = find(strcmp({box.m}, meths{g}));
    if numel(sb) >= 2 && box(sb(1)).med > 0
        r = box(sb(end)).med / box(sb(1)).med;
        badge(ax, pos(g, nh) + 0.1, yl(2) / 1.65, sprintf('\\times%.1f', r), S, c);
    end
end
xt = [];
xtl = {};
for g = 1:numel(meths)
    for j = 1:nh
        xt(end + 1) = pos(g, j); %#ok<AGROW>
        xtl{end + 1} = sprintf('%g d', hz(j)); %#ok<AGROW>
    end
end
xlim(ax, [0.3, pos(numel(meths), nh) + 0.7]);
ylim(ax, yl);
styleAxes(ax, S, true, false);
set(ax, 'XTick', xt, 'XTickLabel', xtl, 'FontSize', S.fs - 1);
ylabel(ax, lab(S, 'Wasserstein 分布误差（对数）', 'Wasserstein distance (log)'));
grpAx = axes(fig, 'Position', P([0.12, 0.06, 0.84, 0.05]), 'Visible', 'off');
xlim(grpAx, [0.3, pos(numel(meths), nh) + 0.7]);
ylim(grpAx, [0, 1]);
for g = 1:numel(meths)
    text(grpAx, mean([pos(g, 1), pos(g, nh)]), 0.5, strsplit(S.methodLabel(meths{g}), ' '), 'HorizontalAlignment', 'center', ...
        'FontSize', S.fs, 'FontWeight', 'bold', 'Color', S.methodColor(meths{g}));
end
finishFigure(fig, S, outBase, isPanel, lab(S, '字母：中位数自助区间分组；菱形：均值（面积 ∝ 相对价值误差）；徽标：最长/最短时域误差倍数', ...
    'Letters: bootstrap median groups; diamonds: means sized by value error'));
end
