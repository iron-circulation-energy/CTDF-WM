function N08_mcRobustness(M, S, outBase)
%N08_MCROBUSTNESS 补充图 19：路线排序对联合抽样的稳健性（省级玫瑰图；natMonteCarlo）。
%   每省一瓣：自内圈向外的长度为该省在全部抽样中由铁燃料路线（FeL/FeX/FeT）最优的比例，颜色为基准最优路线；
%   各瓣按基准路线分组、组内按比例降序排列；红色虚线圈为 90%，浅灰圈为 50%；比例 ≥ 90% 的省份外侧标红色星号（稳健领先）；
%   圆心为各抽样中铁燃料路线最优省数的中位数及 5%—95% 区间。
st = natRouteStyle(S);
P = M.prov;
pI = tcol(P, 'pIron');
lb = tcol(P, 'short', {});
bw = tcol(P, 'baseWinner', {});
if strcmpi(S.lang, 'en')
    lb = provEnglish(lb);
end
n = numel(pI);
if n == 0
    return;
end
gi = zeros(n, 1);
for i = 1:n
    k = find(strcmp(st.keys, bw{i}), 1);
    if isempty(k)
        k = numel(st.keys) + 1;
    end
    gi(i) = k;
end
[~, o] = sortrows([gi, -pI(:)]);
r0 = 20;
th = pi / 2 - 2 * pi * (0:n - 1)' / n;
w = 2 * pi / n * 0.82;
fig = styledFigure(S, 6.8, 6.2);
ax = axes(fig, 'Position', [0.03, 0.06, 0.70, 0.86]);
hold(ax, 'on');
axis(ax, 'equal');
ax.Visible = 'off';
for rr = [50, 90]
    t = linspace(0, 2 * pi, 300);
    if rr == 90
        plot(ax, (r0 + rr) * cos(t), (r0 + rr) * sin(t), ':', 'Color', S.hl, 'LineWidth', 0.9);
    else
        plot(ax, (r0 + rr) * cos(t), (r0 + rr) * sin(t), '-', 'Color', S.grid, 'LineWidth', 0.8);
    end
    text(ax, -(r0 + rr) * 0.10, (r0 + rr) * 0.995, sprintf('%d%%', rr), 'FontSize', S.fs - 2, 'Color', S.tick, ...
        'HorizontalAlignment', 'right');
end
for j = 1:n
    i = o(j);
    a = th(j);
    L = 100 * pI(i);
    c = [0.75, 0.75, 0.75];
    if gi(i) <= numel(st.keys)
        c = st.colors(gi(i), :);
    end
    tt = linspace(a - w / 2, a + w / 2, 12);
    xs = [r0 * cos(tt), fliplr((r0 + L) * cos(tt))];
    ys = [r0 * sin(tt), fliplr((r0 + L) * sin(tt))];
    patch(ax, xs, ys, c, 'EdgeColor', 'w', 'LineWidth', 0.6, 'FaceAlpha', 0.92);
    rl = r0 + 112;
    text(ax, rl * cos(a), rl * sin(a), lb{i}, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
        'FontSize', S.fs - 1.5, 'Color', S.ink);
    if pI(i) >= 0.9
        plot(ax, (r0 + L + 5) * cos(a), (r0 + L + 5) * sin(a), 'p', 'MarkerSize', 6, 'MarkerFaceColor', S.hl, 'MarkerEdgeColor', 'none');
    end
end
q = M.nFeQ(:)';
if numel(q) >= 3
    text(ax, 0, 4, lab(S, '铁燃料路线最优省数', 'Provinces led by iron'), 'HorizontalAlignment', 'center', 'FontSize', S.fs - 1.2, ...
        'FontWeight', 'bold', 'Color', S.ink);
    text(ax, 0, -4, sprintf('%g（%g–%g）', q(2), q(1), q(3)), 'HorizontalAlignment', 'center', 'FontSize', S.fs + 0.5, ...
        'FontWeight', 'bold', 'Color', S.hero);
end
lim = r0 + 125;
xlim(ax, [-lim, lim]);
ylim(ax, [-lim, lim]);
items = struct('kind', {}, 'color', {}, 'label', {}, 'alpha', {}, 'lw', {});
for k = 1:numel(st.keys)
    if any(strcmp(bw, st.keys{k}))
        items(end + 1) = struct('kind', 'patch', 'color', st.colors(k, :), 'label', [lab(S, '基准：', 'Base: '), st.labels{k}], ...
            'alpha', 1, 'lw', 1); %#ok<AGROW>
    end
end
items(end + 1) = struct('kind', 'tri', 'color', S.hl, 'label', lab(S, '≥ 90% 抽样稳健领先', 'Iron-led in ≥ 90% of draws'), 'alpha', 1, 'lw', 1);
drawLegendBox(fig, [0.74, 0.40, 0.25, 0.30], items, S, 1, S.fs - 1.5);
D = M.draws;
rf = tcol(D, 'retrofitFrac');
ls = tcol(D, 'loss');
kp = tcol(D, 'kappa');
sp = tcol(D, 'siloPerT');
addNote(fig, S, sprintf(lab(S, '%d 组抽样：改造投资 %.0f%%—%.0f%%，每循环损耗 %.1f%%—%.1f%%，还原氢耗 %.2f—%.2f，储存设施 %.0f—%.0f 元/t', ...
    '%d draws: retrofit %.0f–%.0f%%, loss %.1f–%.1f%% per cycle, kappa %.2f–%.2f, storage %.0f–%.0f CNY t^{-1}'), ...
    height(D), 100 * min(rf), 100 * max(rf), 100 * min(ls), 100 * max(ls), min(kp), max(kp), min(sp), max(sp)));
saveFigure(fig, outBase);
end
