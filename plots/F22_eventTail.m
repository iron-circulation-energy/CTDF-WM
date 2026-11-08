function F22_eventTail(cap, S, outBase, target)
%F22_EVENTTAIL 图 2c：低风光事件平面与断供概率（双轴融合；容量检查 checkEventRisk）。
%   主轴（左）：横轴为事件开始时的超额缓冲（以日净耗铁 δ^D 的天数计），纵轴为低风光事件持续天数；
%     散点为与 checkEventRisk 相同几何分布 P(D = d) = (1 − q)q^(d−1) 的合成事件（固定种子），缓冲在检查网格范围内均匀；
%     红点为持续天数不小于断供阈值 D* = ⌊缓冲⌋ + 1 的事件（断供），蓝点为缓冲覆盖的事件，虚线为分界；
%   副轴（右，对数）：各缓冲档的经验断供概率（浅红柱，须线为 Wilson 95% 区间）与几何尾 q^k（黑线）；
%   徽标为每多一日缓冲的风险降幅 1 − q。q 由 table.Ptheory 相邻档之比恢复。
if nargin < 4
    target = [];
end
T = cap.eventRisk.table;
k = tcol(T, 'ExcessUnits');
Pt = tcol(T, 'Ptheory');
Pe = tcol(T, 'Pemp');
cl = tcol(T, 'CILo', Pe);
ch = tcol(T, 'CIHi', Pe);
ok = Pt > 0 & Pt < 1;
q = NaN;
if nnz(ok) >= 2
    kk = k(ok);
    pp = Pt(ok);
    q = exp((log(pp(end)) - log(pp(1))) / max(kk(end) - kk(1), eps));
end
if ~isfinite(q) || q <= 0 || q >= 1
    q = 0.5;
end
kmax = max(k) + 0.5;
rs = RandStream('twister', 'Seed', 20261031);
N = 1500;
b = kmax * rand(rs, N, 1);
Dint = 1 + floor(log(max(rand(rs, N, 1), realmin)) / log(q));
starve = Dint >= floor(b) + 1;
Dshow = Dint + 0.8 * (rand(rs, N, 1) - 0.5);
ytop = max(quantileLin(Dshow, 0.995), kmax + 1);
floorP = 1e-4;
[fig, P, isPanel] = panelHost(S, 5.4, 4.2, target);
ax = axes(fig, 'Position', P([0.13, 0.15, 0.70, 0.70]));
hold(ax, 'on');
yyaxis(ax, 'left');
patch(ax, [0, kmax, kmax, 0], [0, 0, kmax, 0], [0.93, 0.95, 0.965], 'EdgeColor', 'none');
patch(ax, [0, kmax, kmax, 0], [0, kmax, ytop, ytop], [0.97, 0.90, 0.88], 'EdgeColor', 'none');
plot(ax, [0, kmax], [0, kmax], '--', 'Color', S.ink, 'LineWidth', 0.8);
scatter(ax, b(~starve), Dshow(~starve), 5, S.sky, 'filled', 'MarkerFaceAlpha', 0.65, 'MarkerEdgeColor', 'none');
scatter(ax, b(starve), Dshow(starve), 9, S.hl, 'filled', 'MarkerFaceAlpha', 0.85, 'MarkerEdgeColor', 'w', 'LineWidth', 0.2);
text(ax, 0.04 * kmax, 0.94 * ytop, lab(S, '事件长于缓冲 → 断供', 'Event outlasts buffer → starvation'), ...
    'FontSize', S.fs - 0.5, 'FontWeight', 'bold', 'Color', 0.8 * S.hl);
text(ax, 0.60 * kmax, 0.08 * ytop, lab(S, '缓冲覆盖事件', 'Buffer covers event'), 'FontSize', S.fs - 0.5, ...
    'FontWeight', 'bold', 'Color', S.slate);
ylim(ax, [0, ytop]);
ylabel(ax, lab(S, '低风光事件持续天数/d', 'Low-renewable spell (d)'));
ax.YAxis(1).Color = S.ink;
yyaxis(ax, 'right');
for i = 1:numel(k)
    if Pe(i) > 0
        patch(ax, k(i) + 0.43 * [-1, 1, 1, -1], [floorP, floorP, Pe(i), Pe(i)], S.hl, 'FaceAlpha', 0.07, ...
            'EdgeColor', S.hl, 'LineWidth', 0.6);
        plot(ax, [k(i), k(i)], [max(cl(i), floorP), max(ch(i), floorP)], '-', 'Color', 0.7 * S.hl, 'LineWidth', 0.8);
        if Pe(i) >= 0.01
            s = sprintf('%.0f%%', 100 * Pe(i));
        else
            s = '<1%';
        end
        text(ax, k(i), Pe(i) * 1.35, s, 'HorizontalAlignment', 'center', 'FontSize', S.fs - 2, 'Color', 0.8 * S.hl);
    end
end
okp = Pt > 0;
plot(ax, k(okp), max(Pt(okp), floorP), '-o', 'Color', S.ink, 'LineWidth', 1.0, 'MarkerSize', 3, 'MarkerFaceColor', S.ink);
set(ax, 'YScale', 'log');
ylim(ax, [floorP, 8]);
ylabel(ax, lab(S, '断供概率（柱：抽样；线：几何尾）', 'Starvation probability (bars sampled, line q^k)'));
ax.YAxis(2).Color = 0.8 * S.hl;
xlim(ax, [0, kmax]);
xlabel(ax, lab(S, '事件开始时的超额缓冲/（δ^D 天数）', 'Excess buffer at onset (days of \delta^D)'));
set(ax, 'Box', 'off', 'TickDir', 'out', 'FontName', S.font, 'FontSize', S.fs - 0.5);
badge(ax, 0.82, 1.06, sprintf(lab(S, '每多一日缓冲 风险 −%.0f%%', 'Each buffer day −%.0f%% risk'), 100 * (1 - q)), ...
    S, S.hl, 'Units', 'normalized');
finishFigure(fig, S, outBase, isPanel, lab(S, '散点为与容量检查相同几何分布的合成事件', 'Dots: synthetic events from the same geometric law'));
end
