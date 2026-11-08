function F17_retireHeatmap(e1, S, outBase, target)
%F17_RETIREHEATMAP 图 5a：退役替代方案的成本差构成与保留价值（三元热图 + 光晕气泡 + 渐变流向弧 + 分项环带；E1）。
%   三元坐标的三个分量为“退役 − 改造”年化成本差中的年化投资、固定运维与运行成本占比（负分量按 0 计，图注说明）；
%   彩色气泡为各替代方案（氢燃机配盐穴储氢、100 h 长时储能、4 h 电池等），面积 ∝ 保留资产价值 RV（亿元），外加两层光晕；
%   底层三元热图为各方案分项成本 ±25%（对数正态，固定种子）扰动后的位置密度；星号为改造情景自身的年化成本构成，
%   由星号指向各方案的弧线线宽与色深 ∝ 年化节省；外环三段色带标出三个分项方向；红圈为节省最大的方案；
%   右侧注明各方案容量相关部分占比。服务不匹配（RV 为 NaN）的方案以灰色空心圆标出。
if nargin < 4
    target = [];
end
rs = {e1.res};
if isfield(e1, 'resAlts') && ~isempty(e1.resAlts)
    rs = [rs, e1.resAlts];
elseif isfield(e1, 'resAlt') && ~isempty(e1.resAlt)
    rs{end + 1} = e1.resAlt;
end
nr = numel(rs);
D = zeros(nr, 3);
RV = nan(nr, 1);
capShare = nan(nr, 1);
names = cell(nr, 1);
for a = 1:nr
    r = rs{a};
    D(a, :) = [r.Aret.capex - r.Aretro.capex, r.Aret.fixedOM - r.Aretro.fixedOM, r.Aret.op - r.Aretro.op] / 1e8;
    if isfield(r, 'RV')
        RV(a) = r.RV / 1e8;
    end
    if isfield(r, 'capValue') && isfinite(RV(a)) && abs(RV(a)) > 0
        capShare(a) = r.capValue / 1e8 / RV(a);
    end
    names{a} = typeLabel(r, S);
end
ret = rs{1}.Aretro;
star = [ret.capex, ret.fixedOM, ret.op] / 1e8;
pal = [S.teal; S.slate; S.sand; S.sky; S.mute];
h = sqrt(3) / 2;
txy = @(v) [v(:, 1) + v(:, 2) / 2, v(:, 2) * h] ./ max(sum(v, 2), eps);   % v = [投资, 运维, 运行]：投资→右下，运维→顶点，运行→左下
[fig, P, isPanel] = panelHost(S, 6.8, 5.6, target);
ax = axes(fig, 'Position', P([0.02, 0.06, 0.70, 0.88]));
hold(ax, 'on');
axis(ax, 'equal');
xlim(ax, [-0.30, 1.30]);
ylim(ax, [-0.45, 1.12]);
ax.Visible = 'off';
% 敏感性扰动点云与三角网格密度
rsd = RandStream('twister', 'Seed', 11);
cloud = [];
for a = 1:nr
    if all(isfinite(D(a, :)))
        Z = max(D(a, :), 0) .* exp(0.25 * randn(rsd, 800, 3));
        cloud = [cloud; txy(Z)]; %#ok<AGROW>
    end
end
ng = 14;
cnt = [];
tris = {};
for i = 0:ng - 1
    for j = 0:ng - 1 - i
        A = [i, j] / ng;
        B = [i + 1, j] / ng;
        C = [i, j + 1] / ng;
        Dd = [i + 1, j + 1] / ng;
        cand = {[A; B; C]};
        if i + j < ng - 1
            cand{end + 1} = [B; Dd; C]; %#ok<AGROW>
        end
        for t = 1:numel(cand)
            uv = cand{t};                                   % (投资, 运维) 份额
            xy = txy([uv, 1 - sum(uv, 2)]);
            cc = mean(xy, 1);
            if isempty(cloud)
                k = 0;
            else
                k = nnz(sum((cloud - cc) .^ 2, 2) < (0.55 / ng) ^ 2);
            end
            tris{end + 1} = xy; %#ok<AGROW>
            cnt(end + 1) = k; %#ok<AGROW>
        end
    end
end
lc = log1p(cnt);
lmax = max([lc, eps]);
for t = 1:numel(tris)
    if cnt(t) > 0
        c = mapColors(S.warm, 0.12 + 0.88 * lc(t) / lmax);
    else
        c = [0.945, 0.95, 0.955];
    end
    patch(ax, tris{t}(:, 1), tris{t}(:, 2), c, 'EdgeColor', 'w', 'LineWidth', 0.4);
end
% 三角框、刻度与坐标名
plot(ax, [0, 1, 0.5, 0], [0, 0, h, 0], '-', 'Color', S.ink, 'LineWidth', 0.9);
for v = 0.2:0.2:0.8
    p1 = txy([v, 0, 1 - v]); p2 = txy([v, 1 - v, 0]);
    plot(ax, [p1(1), p2(1)], [p1(2), p2(2)], '-', 'Color', [1, 1, 1], 'LineWidth', 0.5);
    p1 = txy([0, v, 1 - v]); p2 = txy([1 - v, v, 0]);
    plot(ax, [p1(1), p2(1)], [p1(2), p2(2)], '-', 'Color', [1, 1, 1], 'LineWidth', 0.5);
end
for v = 0:0.2:1
    p = txy([v, 0, 1 - v]);
    text(ax, p(1), p(2) - 0.04, sprintf('%.0f', 100 * v), 'HorizontalAlignment', 'center', 'FontSize', S.fs - 2, 'Color', S.tick);
end
text(ax, 0.5, -0.12, lab(S, '年化投资占比/% →', 'Investment share (%) →'), 'HorizontalAlignment', 'center', 'FontSize', S.fs - 0.5);
text(ax, 0.86, 0.47, lab(S, '← 固定运维占比/%', '← Fixed O&M share (%)'), 'HorizontalAlignment', 'center', 'Rotation', -60, 'FontSize', S.fs - 0.5);
text(ax, 0.14, 0.47, lab(S, '运行成本占比/% →', 'Operation share (%) →'), 'HorizontalAlignment', 'center', 'Rotation', 60, 'FontSize', S.fs - 0.5);
% 外环分项色带
cx = 0.5; cy = h / 3; Rr = 0.76;
seg = {[200, 330], S.slate, lab(S, '年化投资', 'Investment'); [330, 450], S.sand, lab(S, '固定运维', 'Fixed O&M'); ...
    [90, 200], S.teal, lab(S, '运行成本', 'Operation')};
for s = 1:3
    th = deg2rad(linspace(seg{s, 1}(1) + 3, seg{s, 1}(2) - 3, 80));
    plot(ax, cx + Rr * cos(th), cy + Rr * sin(th), '-', 'Color', 0.25 * seg{s, 2} + 0.75, 'LineWidth', 6);
    tm = deg2rad(mean(seg{s, 1}));
    text(ax, cx + (Rr + 0.08) * cos(tm), cy + (Rr + 0.08) * sin(tm), seg{s, 3}, 'HorizontalAlignment', 'center', ...
        'FontSize', S.fs - 0.5, 'FontWeight', 'bold', 'Color', 0.8 * seg{s, 2});
end
% 改造情景星号与流向弧
ps = txy(star);
rvMax = max([RV(isfinite(RV)); eps]);
for a = 1:nr
    if ~all(isfinite(D(a, :)))
        continue;
    end
    pb = txy(max(D(a, :), 0));
    mid = (ps + pb) / 2 + 0.45 * [-(pb(2) - ps(2)), pb(1) - ps(1)];
    t = linspace(0, 1, 40)';
    Q = (1 - t) .^ 2 .* ps + 2 * (1 - t) .* t .* mid + t .^ 2 .* pb;
    w = 0.6 + 3.0 * max(sum(D(a, :)), 0) / max(max(sum(D, 2)), eps);
    for i = 1:numel(t) - 1
        plot(ax, Q(i:i + 1, 1), Q(i:i + 1, 2), '-', 'Color', mapColors(S.flow, 0.35 + 0.6 * t(i)), ...
            'LineWidth', 0.4 + w * t(i));
    end
end
[~, best] = max(sum(D, 2));
for a = 1:nr
    pb = txy(max(D(a, :), 0));
    c = pal(1 + mod(a - 1, size(pal, 1)), :);
    if ~isfinite(RV(a)) || RV(a) <= 0
        plot(ax, pb(1), pb(2), 'o', 'MarkerSize', 9, 'MarkerEdgeColor', S.mute, 'LineWidth', 1.0);
        text(ax, pb(1) + 0.05, pb(2), [names{a}, lab(S, '（无法匹配）', ' (not matched)')], 'FontSize', S.fs - 1.5, 'Color', S.tick);
        continue;
    end
    sz = 900 * RV(a) / rvMax;
    scatter(ax, pb(1), pb(2), 3.0 * sz, c, 'filled', 'MarkerFaceAlpha', 0.10, 'MarkerEdgeColor', 'none');
    scatter(ax, pb(1), pb(2), 1.8 * sz, c, 'filled', 'MarkerFaceAlpha', 0.18, 'MarkerEdgeColor', 'none');
    scatter(ax, pb(1), pb(2), sz, c, 'filled', 'MarkerEdgeColor', 'w', 'LineWidth', 1.4);
    text(ax, pb(1), pb(2), sprintf('%.1f', RV(a)), 'HorizontalAlignment', 'center', 'FontSize', S.fs - 0.5, ...
        'FontWeight', 'bold', 'Color', 'w');
    dx = 0.12;
    if pb(1) > 0.55
        dx = -0.32;
    end
    text(ax, pb(1) + dx, pb(2) + 0.17, sprintf('%s\n%s %+.2f', names{a}, lab(S, '合计', 'total'), sum(D(a, :))), ...
        'FontSize', S.fs - 1.2, 'Color', S.ink);
    plot(ax, [pb(1), pb(1) + dx + 0.05], [pb(2), pb(2) + 0.14], '-', 'Color', S.tick, 'LineWidth', 0.5);
    if a == best
        plot(ax, pb(1), pb(2), 'o', 'MarkerSize', sqrt(1.6 * sz), 'MarkerEdgeColor', S.hl, 'LineWidth', 1.6);
    end
end
plot(ax, ps(1), ps(2), 'p', 'MarkerSize', 13, 'MarkerFaceColor', S.hero, 'MarkerEdgeColor', 'w');
text(ax, ps(1), ps(2) - 0.07, lab(S, '改造情景', 'Retrofit'), 'HorizontalAlignment', 'center', 'FontSize', S.fs - 1, ...
    'FontWeight', 'bold', 'Color', S.hero);
% 右侧：气泡比例尺与容量占比
al = axes(fig, 'Position', P([0.74, 0.50, 0.24, 0.36]), 'Visible', 'off');
hold(al, 'on');
xlim(al, [0, 1]);
ylim(al, [0, 1]);
text(al, 0, 0.98, lab(S, '气泡面积 = 保留价值 RV/亿元', 'Bubble area = retained value'), 'FontSize', S.fs - 1, 'FontWeight', 'bold');
rr = rvMax * [0.33, 0.66, 1];
for i = 1:3
    yy = 0.78 - 0.26 * (i - 1);
    scatter(al, 0.15, yy, 900 * rr(i) / rvMax, [0.85, 0.87, 0.89], 'filled', 'MarkerEdgeColor', 'w');
    text(al, 0.42, yy, sprintf('%.1f', rr(i)), 'FontSize', S.fs - 1);
end
ac = axes(fig, 'Position', P([0.74, 0.10, 0.24, 0.34]), 'Visible', 'off');
hold(ac, 'on');
xlim(ac, [0, 1]);
ylim(ac, [0, nr + 1]);
set(ac, 'YDir', 'reverse');
text(ac, 0, 0.4, lab(S, '容量相关占比', 'Capacity-related share'), 'FontSize', S.fs - 1, 'FontWeight', 'bold');
for a = 1:nr
    c = pal(1 + mod(a - 1, size(pal, 1)), :);
    text(ac, 0, a + 0.3, names{a}, 'FontSize', S.fs - 1.5, 'Color', c);
    if isfinite(capShare(a))
        text(ac, 1, a + 0.3, sprintf('%.0f%%', 100 * capShare(a)), 'FontSize', S.fs - 1.5, 'HorizontalAlignment', 'right');
    end
end
note = lab(S, '底色：分项 ±25% 扰动的位置密度；弧线宽度 ∝ 年化节省；红圈：节省最大', ...
    'Shading: density of ±25% component perturbations; arc width scales with saving');
if any(D(:) < 0)
    note = [note, lab(S, '；负分项按 0 计入构成', '; negative components set to zero')];
end
finishFigure(fig, S, outBase, isPanel, note);
end

function s = typeLabel(r, S)
s = lab(S, '退役 + 替代容量', 'Retirement + replacement');
if isfield(r, 'type')
    switch r.type
        case 'h2'
            s = lab(S, '氢燃机 + 盐穴储氢', 'Hydrogen turbine + salt cavern');
        case 'battery'
            s = lab(S, '4 h 电池', '4-h battery');
        case 'ldes100'
            s = lab(S, '100 h 长时储能', '100-h storage');
    end
end
end
