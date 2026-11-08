function F21_reliabilityCurve(e2, S, outBase, target)
%F21_RELIABILITYCURVE 图 2b：事件断供概率随循环质量的变化（E2）。
%   各方法的均值与 95% 区间带（本文方法赭色、固定策略灰色），深蓝虚线为几何尾计算值；
%   底色：c < M_crit 为缓冲不足区（浅赭），c ≥ M_crit^ε 为风险校准区（浅青）；浅灰竖带为本文方法转折位置的自助 95% 区间；
%   点线依次为平均周转参照 M_LL、临界循环质量 M_crit 与风险校准质量 M_crit^ε。
%   亮点：在 c ≈ M_crit 处以双箭头标出两种方法断供概率之比（“×k 更低”）。
if nargin < 4
    target = [];
end
Sm = e2.summary;
th = e2.capacity;
Mc = th.M_crit;
floorP = 1e-4;
smM = tcol(Sm, 'method', {});
smC = tcol(Sm, 'c');
mu = tcol(Sm, 'eventF_mean');
lo = tcol(Sm, 'eventF_lo', mu);
hi = tcol(Sm, 'eventF_hi', mu);
meths = unique(smM, 'stable');
order = [S.methodOrder, setdiff(meths(:)', S.methodOrder)];
meths = order(ismember(order, meths));
main = 'M1';
if ~any(strcmp(meths, main))
    main = meths{1};
end
% 质量相关部分 q = (P − P_inf)/(1 − P_inf)，与几何尾直接比较（P_inf 见 eventFloor）
Pinf = eventFloor(e2, main);
toQ = @(v) (v - Pinf) / (1 - Pinf);
mu = toQ(mu);
lo = toQ(lo);
hi = toQ(hi);
xl = [min(smC), max(smC)] / Mc;
xl = xl + [-0.03, 0.03] * max(diff(xl), eps);
yl = [floorP, 3];

[fig, P, isPanel] = panelHost(S, 5.2, 3.8, target);
ax = axes(fig, 'Position', P([0.15, 0.18, 0.82, 0.60]));
hold(ax, 'on');
set(ax, 'YScale', 'log');
% 底色分区
patch(ax, [xl(1), 1, 1, xl(1)], yl([1, 1, 2, 2]), 0.07 * S.hero + 0.93, 'EdgeColor', 'none');
if isfinite(th.M_eps)
    xe = th.M_eps / Mc;
    patch(ax, [xe, xl(2), xl(2), xe], yl([1, 1, 2, 2]), 0.08 * S.teal + 0.92, 'EdgeColor', 'none');
end
% 转折位置的自助区间
kn = [];
if isfield(e2, 'knee') && ~isempty(e2.knee)
    kn = e2.knee(strcmp({e2.knee.method}, main));
end
if ~isempty(kn) && all(isfinite(kn(1).twoSegCI)) && diff(kn(1).twoSegCI) / Mc < 0.4 * diff(xl)
    xb = kn(1).twoSegCI / Mc;
    patch(ax, [xb(1), xb(2), xb(2), xb(1)], yl([1, 1, 2, 2]), [0.84, 0.84, 0.84], 'EdgeColor', 'none', 'FaceAlpha', 0.55);
end
% 方法曲线
curves = struct('m', {}, 'x', {}, 'y', {});
for k = numel(meths):-1:1
    r = strcmp(smM, meths{k});
    [x, o] = sort(smC(r) / Mc);
    y = max(mu(r), floorP);
    l = max(lo(r), floorP);
    h = max(hi(r), floorP);
    y = y(o);
    col = S.methodColor(meths{k});
    % q 的天气年区间在下界处被截断为 P_inf 以下，不画区间带（区间见补充表）
    lw = 1.1;
    ms = 3.2;
    if strcmp(meths{k}, main)
        lw = 1.8;
        ms = 4;
    end
    plot(ax, x, y, '-', 'Color', col, 'LineWidth', lw);
    plot(ax, x, y, 'o', 'MarkerSize', ms, 'MarkerFaceColor', col, 'MarkerEdgeColor', 'w', 'LineWidth', 0.5);
    curves(end + 1) = struct('m', meths{k}, 'x', x(:)', 'y', y(:)'); %#ok<AGROW>
end
if isfield(th, 'cFine') && isfield(th, 'PF')
    plot(ax, th.cFine / Mc, max(th.PF, floorP), '--', 'Color', S.slate, 'LineWidth', 1.0);
end
% 参照质量
refs = {th.M_LL / Mc, 'M_{LL}'; 1, 'M_{crit}'; th.M_eps / Mc, 'M_{crit}^{\epsilon}'};
lastX = -inf;
side = 'center';
for k = 1:size(refs, 1)
    xv = refs{k, 1};
    if isfinite(xv) && xv > xl(1) && xv < xl(2)
        plot(ax, [xv, xv], yl, ':', 'Color', [0.45, 0.45, 0.45], 'LineWidth', 0.8);
        side = 'center';
        if xv - lastX < 0.08 * diff(xl)
            side = 'left';                       % 与前一条参照线过近：标签右移
        end
        text(ax, xv, yl(2), refs{k, 2}, 'HorizontalAlignment', side, 'VerticalAlignment', 'bottom', ...
            'FontSize', S.fs - 0.5, 'Color', S.ink);
        if strcmp(side, 'left')
            set(findobj(ax, 'Type', 'text', 'String', refs{k - 1, 2}), 'HorizontalAlignment', 'right');
        end
        lastX = xv;
    end
end
% 亮点：c ≈ M_crit 处两种方法的断供概率之比
iM = find(strcmp({curves.m}, main), 1);
iR = find(strcmp({curves.m}, 'M0'), 1);
if ~isempty(iM) && ~isempty(iR)
    xm = curves(iM).x;
    [~, j] = min(abs(xm - 1));
    yR = interp1(curves(iR).x, curves(iR).y, xm(j), 'linear', NaN);
    yM = curves(iM).y(j);
    if false && isfinite(yR) && yR > 1.5 * yM                        % 两种方法在该处相同，不标倍数
        xa = xm(j);
        plot(ax, [xa, xa], [yM * 1.25, yR / 1.25], '-', 'Color', S.ink, 'LineWidth', 0.8);
        plot(ax, xa, yM * 1.25, 'v', 'MarkerSize', 3.5, 'MarkerFaceColor', S.ink, 'MarkerEdgeColor', 'none');
        plot(ax, xa, yR / 1.25, '^', 'MarkerSize', 3.5, 'MarkerFaceColor', S.ink, 'MarkerEdgeColor', 'none');
        badge(ax, xa + 0.035 * diff(xl), sqrt(yM * yR), sprintf(lab(S, '低 %.0f 倍', '%.0f× lower'), yR / yM), S, S.hero, ...
            'HorizontalAlignment', 'left');
    end
end
xlim(ax, xl);
ylim(ax, yl);
xlabel(ax, lab(S, '循环铁质量 c/M_{crit}', 'Circulating mass, c/M_{crit}'));
ylabel(ax, lab(S, '质量相关的事件断供概率 q', 'Mass-attributable starvation, q'));
text(ax, 0.98, 0.93, sprintf('q = (P - P_\\infty)/(1 - P_\\infty),  P_\\infty = %.2f', Pinf), 'Units', 'normalized', ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', 'FontSize', S.fs - 1.2, 'Color', S.ink);
styleAxes(ax, S, true, false);
set(ax, 'YTick', 10 .^ (-4:0), 'YTickLabel', {'10^{-4}', '10^{-3}', '10^{-2}', '10^{-1}', '1'}, 'YMinorTick', 'off');
text(ax, 0.02, 0.04, lab(S, '缓冲不足', 'Under-buffered'), 'Units', 'normalized', 'FontSize', S.fs - 1, ...
    'Color', 0.7 * S.hero, 'VerticalAlignment', 'bottom');
text(ax, 0.98, 0.04, lab(S, '风险校准', 'Risk-calibrated'), 'Units', 'normalized', 'FontSize', S.fs - 1, ...
    'Color', 0.7 * S.teal, 'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'right');
items = struct('kind', {}, 'color', {}, 'label', {}, 'alpha', {}, 'lw', {});
for k = 1:numel(meths)
    items(end + 1) = struct('kind', 'line', 'color', S.methodColor(meths{k}), 'label', S.methodLabel(meths{k}), ...
        'alpha', 0.2, 'lw', 1.6); %#ok<AGROW>
end
items(end + 1) = struct('kind', 'dash', 'color', S.slate, 'label', lab(S, '几何尾计算值', 'Geometric tail'), 'alpha', 1, 'lw', 1.0);
items(end + 1) = struct('kind', 'patch', 'color', [0.84, 0.84, 0.84], 'label', lab(S, '转折 95% 区间', 'Transition, 95% CI'), ...
    'alpha', 0.8, 'lw', 1);
drawLegendBox(fig, P([0.15, 0.87, 0.84, 0.12]), items, S, 2, S.fs - 1.2);
finishFigure(fig, S, outBase, isPanel, '');
end
