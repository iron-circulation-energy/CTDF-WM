function F02_resourceSurface(mh, W, p, S, outBase)
%F02_RESOURCESURFACE 补充图 2：风电容量因子的月份 × 时刻分布（模板“月份 × 时刻热力图 + 右侧月均值 + 红框 + 下方日内曲线”）。
%   mh：12×24 训练年月份 × 时刻平均容量因子（0—1，prepareRealData 由 ERA5 逐时数据计算，保存在 fit_report.mat）；
%   为空时由模型表示（训练年日电量 × 典型日形状，hourlyProfiles）计算。
%   底色为月份 × 时刻容量因子（%），红框标出最大值单元，深色框标出最小值单元；
%   同一坐标区以右侧副轴叠加冬季（12—2 月）与夏季（6—8 月）日内曲线：细线为逐训练年，阴影为 25%—75% 分位，
%   白衬粗线为均值。函数名沿用旧版（三维曲面），调用不变。

src = lab(S, 'ERA5 训练年逐时数据', 'ERA5 hourly data, training years');
if isempty(mh)
    w = p.weather;
    mo = month(datetime(2001, 1, 1) + caldays(0:364));
    acc = zeros(12, 24);
    cnt = zeros(12, 1);
    for y = w.train(:)'
        RE = hourlyProfiles(W(y).EW(1:365), zeros(1, 365), W(y).EL(1:365), W(y).doy(1:365), w);
        for q = 1:12
            sel = mo == q;
            acc(q, :) = acc(q, :) + sum(RE(:, sel), 2)';
            cnt(q) = cnt(q) + nnz(sel);
        end
    end
    mh = acc ./ cnt / p.re.capW;
    src = lab(S, '训练年日电量 × 模型典型日形状', 'training-year daily energy × typical-day shape');
end
Z = 100 * mh;
lo = min(Z(:));
hi = max(Z(:));
if hi - lo < 1e-9
    hi = lo + 1;
end
mon = lab(S, {'1月', '2月', '3月', '4月', '5月', '6月', '7月', '8月', '9月', '10月', '11月', '12月'}, ...
    {'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'});
% 逐训练年的冬、夏季日内曲线（W 可用时）
yrW = [];
yrS = [];
try
    w = p.weather;
    mo = month(datetime(2001, 1, 1) + caldays(0:364));
    for y = w.train(:)'
        RE = hourlyProfiles(W(y).EW(1:365), zeros(1, 365), W(y).EL(1:365), W(y).doy(1:365), w);
        yrW(end + 1, :) = 100 * mean(RE(:, ismember(mo, [12, 1, 2])), 2)' / p.re.capW; %#ok<AGROW>
        yrS(end + 1, :) = 100 * mean(RE(:, ismember(mo, [6, 7, 8])), 2)' / p.re.capW; %#ok<AGROW>
    end
catch
    yrW = [];
    yrS = [];
end
fig = styledFigure(S, 6.8, 4.8);
ax = axes(fig, 'Position', [0.10, 0.12, 0.66, 0.74]);
hold(ax, 'on');
for m = 1:12
    for h = 0:23
        c = mapColors(S.seq, (Z(m, h + 1) - lo) / (hi - lo));
        patch(ax, h + [-0.5, 0.5, 0.5, -0.5], m + [-0.5, -0.5, 0.5, 0.5], c, 'EdgeColor', 'w', 'LineWidth', 0.4);
    end
end
[~, iMax] = max(Z(:));
[mMax, hMax] = ind2sub(size(Z), iMax);
[~, iMin] = min(Z(:));
[mMin, hMin] = ind2sub(size(Z), iMin);
hlBox(ax, hMax - 1 - 0.5, mMax - 0.5, 1, 1, S, 1.4);
plot(ax, hMin - 1 + [-0.5, 0.5, 0.5, -0.5, -0.5], mMin + [-0.5, -0.5, 0.5, 0.5, -0.5], '-', 'Color', S.dark, 'LineWidth', 1.2);
set(ax, 'YDir', 'reverse');
xlim(ax, [-0.5, 23.5]);
ylim(ax, [0.5, 12.5]);
styleAxes(ax, S);
set(ax, 'XTick', 0:3:21, 'YTick', 1:12, 'YTickLabel', mon, 'TickLength', [0, 0], 'YColor', S.tick);
xlabel(ax, lab(S, '时刻/h', 'Hour of day'));
% 叠加：日内曲线（右侧副轴）
ao = axes(fig, 'Position', get(ax, 'Position'), 'Color', 'none', 'YAxisLocation', 'right', 'XAxisLocation', 'top');
hold(ao, 'on');
hh = 0:23;
win = mean(Z([12, 1, 2], :), 1);
sum_ = mean(Z(6:8, :), 1);
curves = {win, yrW, [0.09, 0.19, 0.29], lab(S, '冬季日内曲线', 'Winter'); sum_, yrS, S.hero, lab(S, '夏季日内曲线', 'Summer')};
ytop = 1.35 * max([win, sum_, yrW(:)', yrS(:)']);
for k = 1:2
    c = curves{k, 3};
    Yk = curves{k, 2};
    if size(Yk, 1) >= 2
        for r = 1:size(Yk, 1)
            plot(ao, hh, Yk(r, :), '-', 'Color', [c, 0.35], 'LineWidth', 0.4);
        end
        q = quantileLinRows(Yk);
        fill(ao, [hh, fliplr(hh)], [q(1, :), fliplr(q(2, :))], c, 'FaceAlpha', 0.20, 'EdgeColor', 'none');
    end
    plot(ao, hh, curves{k, 1}, '-', 'Color', [1, 1, 1], 'LineWidth', 3.2);
    plot(ao, hh, curves{k, 1}, '-o', 'Color', c, 'LineWidth', 1.6, 'MarkerSize', 2.8, 'MarkerFaceColor', c, 'MarkerEdgeColor', 'w');
end
xlim(ao, [-0.5, 23.5]);
ylim(ao, [0, ytop]);
set(ao, 'XTick', [], 'Box', 'off', 'TickDir', 'out', 'FontName', S.font, 'FontSize', S.fs - 0.5, 'YColor', S.ink, 'XColor', 'none');
ylabel(ao, lab(S, '日内容量因子/%（曲线）', 'Diurnal CF (%) (curves)'));
drawLegendBox(fig, [0.10, 0.88, 0.66, 0.06], struct('kind', {'line', 'line', 'box', 'box'}, ...
    'color', {curves{1, 3}, curves{2, 3}, S.hl, S.dark}, 'label', {curves{1, 4}, curves{2, 4}, lab(S, '最大单元', 'Maximum'), ...
    lab(S, '最小单元', 'Minimum')}, 'alpha', {1, 1, 1, 1}, 'lw', {1.6, 1.6, 1.4, 1.2}), S, 4, S.fs - 1.2);
tk = unique(round(linspace(lo, hi, 5)));
tk = tk(tk >= lo & tk <= hi);
drawColorbar(fig, [0.88, 0.12, 0.022, 0.74], S.seq, [lo, hi], tk, [], lab(S, '月×时容量因子/%（底色）', 'Month × hour CF (%)'), S, 'v');
addNote(fig, S, [lab(S, '细线：逐训练年；阴影：25%—75%；数据：', 'Thin: training years; band: 25–75%; data: '), src]);
saveFigure(fig, outBase);
end

function q = quantileLinRows(Y)
q = zeros(2, size(Y, 2));
for j = 1:size(Y, 2)
    q(:, j) = quantileLin(Y(:, j), [0.25, 0.75]);
end
end
