function F05_criticalRidges(e2, S, outBase, target)
%F05_CRITICALRIDGES 图 2a：不同循环铁质量下逐日最小电厂铁裕度的分布（双样本山脊图；模板“逐月山脊：实心年 vs 描边年”；E2）。
%   每行一个循环质量 c（c/M_crit 约 0.25—2.3 的网格点，必含最接近 M_0、M_crit(ε)、M_crit 与名义质量的行，至多 6 行，自上而下质量增大）；
%   实心山脊为本文方法 CTDF-WM（颜色由赭到青表示质量由不足到充裕），白线为均值；
%   描边山脊为固定联合策略（深灰线），短竖线为其均值；红色加深区为 CTDF-WM 裕度为负的日数（断供暴露）。
%   M_0 至 M_crit(ε) 之间的各行加米色底带（几何尾转折区），三个锚点行在左侧标注；右侧三列为事件断供频率：CTDF-WM、固定策略与几何尾计算值。
if nargin < 4
    target = [];
end
if ~isfield(e2, 'daily') || isempty(e2.daily)
    return;
end
meths = unique({e2.daily.method}, 'stable');
mHero = 'M1';
if ~any(strcmp(meths, mHero))
    mHero = meths{1};
end
mRef = 'M0';
if ~any(strcmp(meths, mRef))
    mRef = '';
end
th = e2.capacity;
Mc = th.M_crit;
cg = e2.cGrid(:)';
x01 = cg / Mc;
cNom = NaN;
if isfield(e2, 'cNominal')
    cNom = e2.cNominal;
end
aM = [tget(th, 'M_0'), tget(th, 'M_eps'), Mc, cNom];
aLab = {'M_0', 'M_{crit}(\epsilon)', 'M_{crit}', 'c_{nom}'};
anc = [];
for k = 1:numel(aM)
    if isfinite(aM(k))
        [~, j] = min(abs(cg - aM(k)));
        anc(end + 1) = j; %#ok<AGROW>
    end
end
anc = unique(anc);
cand = union(find(x01 >= 0.25 & x01 <= 2.3), anc);
if numel(cand) < 3
    cand = 1:numel(cg);
end
if numel(cand) > 6
    rest = setdiff(cand, anc);
    nf = max(0, 6 - numel(anc));
    if nf > 0 && ~isempty(rest)
        rest = rest(unique(round(linspace(1, numel(rest), min(nf, numel(rest))))));
    else
        rest = [];
    end
    cand = sort([anc, rest(:)']);
end
cs = cg(cand);
rowTag = repmat({''}, 1, numel(cs));
for k = 1:numel(aM)
    if isfinite(aM(k))
        [~, j] = min(abs(cs - aM(k)));
        rowTag{j} = strtrim([rowTag{j}, ' ', aLab{k}]);
    end
end
n = numel(cs);
V = cell(2, n);
for i = 1:n
    V{1, i} = getDaily(e2.daily, mHero, cs(i));
    if ~isempty(mRef)
        V{2, i} = getDaily(e2.daily, mRef, cs(i));
    end
end
allv = [V{:}];
if isempty(allv)
    return;
end
qq = quantileLin(allv, [0.003, 0.997]);
x = linspace(qq(1) - 0.08 * diff(qq), qq(2) + 0.08 * diff(qq), 400);
cols = mapColors(S.div, linspace(0.86, 0.12, n));
[~, iCrit] = min(abs(cs / Mc - 1));
Sm = e2.summary;
smM = tcol(Sm, 'method', {});
smC = tcol(Sm, 'c');
smE = tcol(Sm, 'eventF_mean');
pickE = @(m, c) firstOr(smE(strcmp(smM, m) & abs(smC - c) <= 1e-9 * max(1, c)), NaN);

[fig, P, isPanel] = panelHost(S, 6.4, 1.5 + 0.62 * n, target);
ax = axes(fig, 'Position', P([0.13, 0.13, 0.57, 0.72]));
hold(ax, 'on');
step = 1.0;
hk = 1.45;
iLo = iCrit;
iHi = iCrit;
if isfinite(aM(1))
    [~, iLo] = min(abs(cs - aM(1)));
    iHi = iLo;
    if isfinite(aM(2))
        [~, iHi] = min(abs(cs - aM(2)));
    end
end
patch(ax, x([1, end, end, 1]), [-(iHi - 1) * step - 0.10, -(iHi - 1) * step - 0.10, -(iLo - 1) * step + 0.90, ...
    -(iLo - 1) * step + 0.90], S.cream, 'EdgeColor', 'none');
for i = 1:n
    b0 = -(i - 1) * step;
    plot(ax, x([1, end]), [b0, b0], '-', 'Color', [0.80, 0.80, 0.80], 'LineWidth', 0.5);
    if ~isempty(V{2, i})
        k2 = kde1(V{2, i}, x);
        k2 = k2 / max(max(k2), eps) * hk * 0.82;
    end
    % 本文方法：实心山脊
    v = V{1, i};
    if ~isempty(v)
        k1 = kde1(v, x);
        k1 = k1 / max(max(k1), eps) * hk;
        fill(ax, [x, fliplr(x)], [b0 + k1, b0 * ones(size(x))], cols(i, :), 'EdgeColor', 'none', 'FaceAlpha', 0.92);
        neg = x <= 0;
        if any(neg) && any(k1(neg) > 0.01)
            xn = x(neg);
            fill(ax, [xn, fliplr(xn)], [b0 + k1(neg), b0 * ones(size(xn))], S.hl, 'EdgeColor', 'none', 'FaceAlpha', 0.45);
        end
        plot(ax, x, b0 + k1, '-', 'Color', 'w', 'LineWidth', 0.8);
        mu = mean(v);
        plot(ax, [mu, mu], [b0, b0 + interp1(x, k1, mu)], '-', 'Color', 'w', 'LineWidth', 1.5);
    end
    if ~isempty(V{2, i})
        plot(ax, x, b0 + k2, '-', 'Color', [0.22, 0.22, 0.22], 'LineWidth', 0.75);
        mu2 = mean(V{2, i});
        plot(ax, [mu2, mu2], [b0, b0 + interp1(x, k2, mu2)], '-', 'Color', [0.22, 0.22, 0.22], 'LineWidth', 1.0);
    end
    fw = 'normal';
    tc = S.tick;
    if ~isempty(rowTag{i})
        fw = 'bold';
        tc = S.ink;
    end
    text(ax, x(1) - 0.02 * diff(x([1, end])), b0 + 0.22, sprintf('%.2f', cs(i) / Mc), 'HorizontalAlignment', 'right', ...
        'VerticalAlignment', 'bottom', 'FontWeight', fw, 'Color', tc, 'FontSize', S.fs);
    if ~isempty(rowTag{i})
        text(ax, x(1) - 0.02 * diff(x([1, end])), b0 + 0.18, rowTag{i}, 'HorizontalAlignment', 'right', ...
            'VerticalAlignment', 'top', 'Color', S.hero, 'FontSize', S.fs - 1, 'FontWeight', 'bold');
    end
end
ytop = hk + 0.35;
ybot = -(n - 1) * step - 0.25;
if x(1) < 0 && x(end) > 0
    plot(ax, [0, 0], [ybot, ytop - 0.15], '--', 'Color', [0.30, 0.30, 0.30], 'LineWidth', 0.7);
    text(ax, 0, ytop - 0.1, lab(S, ' 零裕度', ' zero margin'), 'FontSize', S.fs - 1, 'Color', [0.30, 0.30, 0.30], ...
        'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'left');
end
text(ax, x(1) - 0.02 * diff(x([1, end])), ytop - 0.1, 'c/M_{crit}', 'HorizontalAlignment', 'right', ...
    'VerticalAlignment', 'bottom', 'FontSize', S.fs - 0.5, 'Color', S.ink);
xlim(ax, x([1, end]));
ylim(ax, [ybot, ytop + 0.2]);
xlabel(ax, lab(S, '逐日最小电厂铁裕度 min_i \mu_i^{Fe}/kt', 'Daily minimum plant iron margin, min_i \mu_i^{Fe} (kt)'));
styleAxes(ax, S);
set(ax, 'YColor', 'none', 'YTick', []);

% 右侧：事件断供频率表
at = axes(fig, 'Position', P([0.72, 0.13, 0.28, 0.72]), 'Visible', 'off');
hold(at, 'on');
xlim(at, [0, 3]);
ylim(at, [ybot, ytop + 0.2]);
hdr = {lab(S, '本文', 'CTDF'), lab(S, '固定', 'Fixed'), lab(S, '理论', 'Theory')};
Pinf = eventFloor(e2, mHero);
hcol = {S.hero, [0.35, 0.35, 0.35], S.slate};
for j = 1:3
    text(at, j - 0.5, ytop - 0.05, hdr{j}, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
        'FontSize', S.fs - 1.2, 'Color', hcol{j}, 'FontWeight', 'bold');
end
text(at, 1.5, ytop + 0.32, lab(S, '事件断供频率', 'Event starvation'), 'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'bottom', 'FontSize', S.fs - 0.8, 'Color', S.ink);
plot(at, [0.05, 2.95], (ytop - 0.12) * [1, 1], '-', 'Color', S.axis, 'LineWidth', 0.5);
for i = 1:n
    b0 = -(i - 1) * step + 0.35;
    vals = [pickE(mHero, cs(i)), NaN, NaN];
    if ~isempty(mRef)
        vals(2) = pickE(mRef, cs(i));
    end
    if isfield(th, 'cFine') && isfield(th, 'PF')
        vals(3) = Pinf + (1 - Pinf) * interp1(th.cFine, th.PF, cs(i), 'linear', NaN);   % 电厂侧部分 + 几何尾
    end
    for j = 1:3
        fw = 'normal';
        if j == 1
            fw = 'bold';
        end
        text(at, j - 0.5, b0, pct(vals(j)), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
            'FontSize', S.fs - 0.8, 'Color', hcol{j}, 'FontWeight', fw);
    end
end

% 图例
items = struct('kind', {'patch', 'line', 'patch'}, 'color', {S.hero, [0.22, 0.22, 0.22], S.hl}, ...
    'label', {S.methodLabel(mHero), lab(S, '固定联合策略', 'Fixed policy'), lab(S, '裕度 < 0 的日数', 'Days with negative margin')}, ...
    'alpha', {0.92, 1, 0.45}, 'lw', {1.4, 0.9, 1.4});
if isempty(mRef)
    items = items([1, 3]);
end
drawLegendBox(fig, P([0.13, 0.885, 0.62, 0.075]), items, S, numel(items), S.fs - 1);
finishFigure(fig, S, outBase, isPanel, '');
end

function v = getDaily(daily, m, c)
v = [];
for k = 1:numel(daily)
    if strcmp(daily(k).method, m) && abs(daily(k).c - c) <= 1e-9 * max(1, c)
        v = [v, double(daily(k).minMuFe(:)') / 1e3]; %#ok<AGROW>
    end
end
end

function v = firstOr(x, d)
if isempty(x)
    v = d;
else
    v = x(1);
end
end

function s = pct(v)
if ~isfinite(v)
    s = '—';
elseif v < 0.001
    s = '<0.1%';
elseif v < 0.1
    s = sprintf('%.1f%%', 100 * v);
else
    s = sprintf('%.0f%%', 100 * v);
end
end

function v = tget(s, f)
v = NaN;
if isstruct(s) && isfield(s, f) && ~isempty(s.(f))
    v = double(s.(f)(1));
end
end
