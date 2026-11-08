function F26_accountWaterfall(e1, S, outBase, target)
%F26_ACCOUNTWATERFALL 图 F26（正文图 5d）：改造相对退役的年化成本差由基准核算逐项累加到全面核算（单图瀑布）。
%   首行为基准比较（替代方案完全预见），其后依次为拆除推迟、新建并网（双方对称）、延寿投资、2030 年电解与还原成本、
%   储氢缓冲设计与各副产品，末行为全部计入后的合计；正值表示改造更省。替代方案按滚动 3 天预见调度时的基准与合计
%   以空心菱形叠加在首末两行。还原氢耗情景（工艺情景）属于敏感性，不进入瀑布。
if nargin < 4
    target = [];
end
if ~isfield(e1, 'acct') || isempty(e1.acct)
    error('F26:noAccount', 'E1 comprehensive account is not available.');
end
A = e1.acct;
I = A.items(~ismember(A.items.category, {'工艺情景', '敏感性'}), :);   % 工艺情景与敏感性不进入瀑布
en = containers.Map( ...
    {'拆除费用推迟', '新建并网接入（双方对称）', '延寿改造投资', '2030 年电解与还原投资', '储氢缓冲与还原厂按平均通量配置', ...
    '富余时段售氢', '电解副产氧气', '电解余热供热', '同步机组转动惯量'}, ...
    {'Deferred decommissioning', 'New grid connections', 'Life extension', '2030 electrolysis and reduction', ...
    'Hydrogen buffer for reduction', 'Hydrogen sales', 'By-product oxygen', 'Electrolysis heat', 'Synchronous inertia'});
zh = {'基准核算'};
eng = {'Base account'};
v = A.summary.base / 1e8;
for k = 1:height(I)
    zh{end + 1} = I.item{k}; %#ok<AGROW>
    if isKey(en, I.item{k})
        eng{end + 1} = en(I.item{k}); %#ok<AGROW>
    else
        eng{end + 1} = I.item{k}; %#ok<AGROW>
    end
    v(end + 1) = I.dAnnual(k) / 1e8; %#ok<AGROW>
end
zh{end + 1} = '全面核算合计';
eng{end + 1} = 'Comprehensive total';
tot = A.summary.base / 1e8 + sum(v(2:end));
n = numel(v) + 1;
[fig, P, isPanel] = panelHost(S, 5.6, 4.2, target);
ax = axes(fig, 'Position', P([0.47, 0.10, 0.50, 0.86]));
hold(ax, 'on');
cGain = S.hero;
cLoss = [0.55, 0.60, 0.66];
cTot = S.ink;
cum = 0;
x = zeros(n, 2);
for k = 1:n
    if k == 1
        a = 0; b = v(1); c = cTot;
    elseif k == n
        a = 0; b = tot; c = cTot;
    else
        a = cum; b = cum + v(k);
        c = cGain;
        if v(k) < 0, c = cLoss; end
    end
    patch(ax, [a, b, b, a], k + [-0.34, -0.34, 0.34, 0.34], c, 'EdgeColor', 'none');
    x(k, :) = [a, b];
    if k < n
        cum = cum + v(k) * (k > 1) + v(1) * (k == 1);
    end
    if k > 1 && k < n
        plot(ax, [b, b], k + [0.34, 0.66], ':', 'Color', S.axis, 'LineWidth', 0.6);
    end
end
yl = [0.4, n + 0.6];
xr = [min([x(:); 0]), max([x(:); 0])];
pad = 0.18 * max(diff(xr), eps);
for k = 1:n
    val = v(min(k, numel(v)));
    if k == n, val = tot; end
    xe = max(x(k, :));
    ha = 'left';
    if val < 0 && k ~= 1 && k ~= n
        xe = min(x(k, :)); ha = 'right';
    elseif (k == 1 || k == n) && val < 0
        xe = min(x(k, :)); ha = 'right';
    end
    off = 0.02 * diff(xr);
    if strcmp(ha, 'right'), off = -off; end
    text(ax, xe + off, k, sprintf('%+.1f', val), 'HorizontalAlignment', ha, 'VerticalAlignment', 'middle', ...
        'FontSize', S.fs - 1.2, 'Color', S.ink);
end
h = gobjects(0);
if isfield(e1, 'acctForesight') && ~isempty(e1.acctForesight)
    Af = e1.acctForesight;
    totF = Af.summary.base / 1e8 + sum(Af.items.dAnnual(~ismember(Af.items.category, {'工艺情景', '敏感性'}))) / 1e8;
    h = plot(ax, [Af.summary.base / 1e8, totF], [1, n], 'd', 'MarkerSize', 6, 'MarkerEdgeColor', S.ink, ...
        'MarkerFaceColor', 'w', 'LineWidth', 1.0, 'LineStyle', 'none');
    xr = [min([xr, Af.summary.base / 1e8, totF]), max([xr, Af.summary.base / 1e8, totF])];
end
plot(ax, [0, 0], yl, '-', 'Color', S.axis, 'LineWidth', 0.8);
set(ax, 'YDir', 'reverse', 'YTick', 1:n, 'YTickLabel', ifEn(S, eng, zh), 'TickLength', [0, 0]);
ylim(ax, yl);
xlim(ax, xr + [-pad, pad]);
styleAxes(ax, S, false, true);
xlabel(ax, lab(S, '年化成本差（退役 − 改造）/亿元', 'Retirement minus retrofit cost (10^8 CNY yr^{-1})'));
if ~isempty(h)
    legend(ax, h, lab(S, '替代方案滚动 3 天预见', 'Alternative, 3-day foresight'), 'Location', 'southwest', 'Box', 'off');
end
finishFigure(fig, S, outBase, isPanel, '');
end

function c = ifEn(S, eng, zh)
if strcmpi(S.lang, 'en')
    c = eng;
else
    c = zh;
end
end
