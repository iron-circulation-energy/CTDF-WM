function F16_corrMatrix(e3, S, outBase)
%F16_CORRMATRIX 图 F16：本文方法运行中关键日变量的相关结构（相关矩阵 + 平均连接聚类树；模板 9 左；E3）。
%   上三角：Pearson r（常规与连续低风光工况的全部日）；对角：两类工况的核密度；下三角：散点（每类至多 800 点）；
%   变量顺序与顶部聚类树由距离 1 − |r| 的平均连接层次聚类给出；标准差为 0 的变量不参与。

D = e3.daily;
meths = unique({D.method}, 'stable');
main = 'M1';
if ~any(strcmp(meths, main))
    main = meths{1};
end
grp = {'normal', lab(S, '常规工况', 'Normal'), S.slate; 'drought', lab(S, '连续低风光工况', 'Drought'), S.accent};
vars = lab(S, {'西部风光出力', '负荷', '系统 SOC', '最小铁裕度', '铁粉发运', '铁锈回运', '弃电率', '掺氨电量'}, ...
    {'Renewables', 'Load', 'SOC', 'Min iron margin', 'Iron shipped', 'Rust returned', 'Curtailment', 'Ammonia'});
X = cell(1, 2);
for g = 1:2
    Dg = D(strcmp({D.method}, main) & strcmp({D.scenario}, grp{g, 1}));
    if isempty(Dg)
        X{g} = zeros(0, numel(vars));
        continue;
    end
    getv = @(f) double(cell2mat(arrayfun(@(r) r.d.(f), Dg, 'UniformOutput', false)));
    RE = getv('RE');
    X{g} = [RE' / 1e3, getv('load')' / 1e3, getv('soc')', getv('minMuFe')' / 1e3, getv('shipFe')' / 1e3, ...
        getv('shipOx')' / 1e3, (getv('cur') ./ max(RE, 1e-9))', getv('nh3')' / 1e3];
end
A = [X{1}; X{2}];
if size(A, 1) < 10
    return;
end
keep = std(A, 0, 1) > 1e-12;
vars = vars(keep);
A = A(:, keep);
X = cellfun(@(M) M(:, keep), X, 'UniformOutput', false);
n = numel(vars);
Rm = corrcoef(A);
[order, links] = avgLinkage(1 - abs(Rm));
fig = styledFigure(S, 7.0, 7.4);
x0 = 0.16;
y0 = 0.13;
gw = 0.80;
gh = 0.66;
cw = gw / n;
ch = gh / n;
axd = axes(fig, 'Position', [x0, y0 + gh + 0.01, gw, 0.13]);
hold(axd, 'on');
pos = zeros(1, 2 * n - 1);
pos(order) = 1:n;
hgt = zeros(1, 2 * n - 1);
for k = 1:size(links, 1)
    a = links(k, 1);
    b = links(k, 2);
    c = n + k;
    pos(c) = (pos(a) + pos(b)) / 2;
    hgt(c) = links(k, 3);
    plot(axd, [pos(a), pos(a), pos(b), pos(b)], [hgt(a), hgt(c), hgt(c), hgt(b)], '-', 'Color', [0.18, 0.50, 0.48], ...
        'LineWidth', 1.4);
end
xlim(axd, [0.5, n + 0.5]);
ylim(axd, [0, max(hgt) * 1.05 + eps]);
axis(axd, 'off');
rs = RandStream('twister', 'Seed', 3);
for a = 1:n
    i = order(a);
    for b = 1:n
        j = order(b);
        ax = axes(fig, 'Position', [x0 + (b - 1) * cw + 0.003, y0 + (n - a) * ch + 0.003, cw - 0.006, ch - 0.006]);
        hold(ax, 'on');
        set(ax, 'XTick', [], 'YTick', [], 'Box', 'off', 'XColor', 'none', 'YColor', 'none');
        if a < b
            set(ax, 'Color', mapColors(flipud(S.div), (Rm(i, j) + 1) / 2));
            tc = S.ink;
            if abs(Rm(i, j)) > 0.6
                tc = [1, 1, 1];
            end
            text(ax, 0.5, 0.5, sprintf('%.2f', Rm(i, j)), 'Units', 'normalized', 'HorizontalAlignment', 'center', ...
                'Color', tc, 'FontSize', S.fs);
        else
            set(ax, 'Color', [0.95, 0.95, 0.95]);
            for g = 1:2
                M = X{g};
                if isempty(M)
                    continue;
                end
                if a == b
                    gx = linspace(min(A(:, i)), max(A(:, i)), 100);
                    f = kde1(M(:, i), gx);
                    fill(ax, [gx, fliplr(gx)], [f, zeros(size(f))], grp{g, 3}, 'FaceAlpha', 0.25, 'EdgeColor', 'none');
                    plot(ax, gx, f, '-', 'Color', grp{g, 3}, 'LineWidth', 1.0);
                else
                    k = randperm(rs, size(M, 1), min(800, size(M, 1)));
                    scatter(ax, M(k, j), M(k, i), 2, grp{g, 3}, 'filled', 'MarkerFaceAlpha', 0.45, ...
                        'MarkerEdgeColor', 'none');
                end
            end
            axis(ax, 'tight');
        end
        if b == 1
            text(ax, -0.06, 0.5, vars{i}, 'Units', 'normalized', 'HorizontalAlignment', 'right', 'FontSize', S.fs);
        end
        if a == n
            text(ax, 0.5, -0.08, vars{j}, 'Units', 'normalized', 'HorizontalAlignment', 'right', 'Rotation', 35, ...
                'FontSize', S.fs);
        end
    end
end
cax = axes(fig, 'Position', [x0, 0.03, 0.30, 0.012], 'Visible', 'off');
colormap(cax, flipud(S.div));
clim(cax, [-1, 1]);
cb = colorbar(cax, 'southoutside');
cb.Position = [x0, 0.035, 0.30, 0.012];
styleColorbar(cb, S, 'Pearson r');
for g = 1:2
    annotation(fig, 'textbox', [0.58 + 0.17 * (g - 1), 0.025, 0.17, 0.03], 'String', ['● ', grp{g, 2}], ...
        'Color', grp{g, 3}, 'EdgeColor', 'none', 'FontName', S.font, 'FontSize', S.fs);
end
addNote(fig, S, S.methodLabel(main));
saveFigure(fig, outBase);
end

function [order, links] = avgLinkage(Dm)
% 平均连接层次聚类（n 较小，直接实现）：links 每行 [簇 a, 簇 b, 合并高度]，新簇编号 n + 行号；order 为叶序
n = size(Dm, 1);
members = num2cell(1:n);
active = 1:n;
links = zeros(n - 1, 3);
kids = zeros(2 * n - 1, 2);
for k = 1:n - 1
    best = inf;
    pa = 0;
    pb = 0;
    for u = 1:numel(active)
        for v = u + 1:numel(active)
            a = active(u);
            b = active(v);
            dd = mean(mean(Dm(members{a}, members{b})));
            if dd < best
                best = dd;
                pa = a;
                pb = b;
            end
        end
    end
    c = n + k;
    members{c} = [members{pa}, members{pb}];
    kids(c, :) = [pa, pb];
    links(k, :) = [pa, pb, best];
    active = [setdiff(active, [pa, pb]), c];
end
order = leaves(2 * n - 1, kids, n);
end

function o = leaves(c, kids, n)
if c <= n
    o = c;
else
    o = [leaves(kids(c, 1), kids, n), leaves(kids(c, 2), kids, n)];
end
end
