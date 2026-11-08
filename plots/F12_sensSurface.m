function F12_sensSurface(e6, S, outBase, target, acct)
%F12_SENSSURFACE 图 5b：实际往返效率倍数 × 运价倍数下的保留资产价值（三角网格发散色热图 + 等值线 + 盈亏边界；E6）。
%   往返效率倍数为每一电厂—还原站组合实际往返效率相对基准的倍率，放能与充能两端各承担其平方根（见 applyVariant）。
%   E6 网格（heatN × heatN）经双线性插值到 13 × 13 单元，每个单元沿对角线分为两个三角形，按三角形形心处的 RV 着色
%   （以 0 为中间色，正值深青、负值赭色）；细点线为等值线并标注数值，深红粗线为 RV = 0 的盈亏边界；
%   星号为基准参数；徽标为 RV > 0 的面积占比。函数名沿用旧版（三维曲面），以保持调用不变。
if nargin < 4
    target = [];
end
gR = e6.heat.roundtrip(:)';
gT = e6.heat.transport(:)';
RV = e6.heat.RV / 1e8;
comp = false;
if nargin >= 5 && ~isempty(acct) && isfield(acct, 'summary') && isfield(acct.summary, 'RV_all2030RailPolicy')
    % 全面核算：基础核算的 RV 加上各分项；铁路边际成本一项与运价成正比，随运价倍数缩放，其余分项取基准值
    It = acct.items;
    iRail = strcmp(It.category, '运输口径');
    dRail = sum(It.dRV(iRail)) / 1e8;
    dOther = (acct.summary.RV_all2030RailPolicy - acct.summary.RV_base) / 1e8 - dRail;
    [TTg, ~] = meshgrid(e6.heat.transport(:)', e6.heat.roundtrip(:)');
    RV = RV + dOther + TTg * dRail;
    comp = true;
end
if numel(gR) < 2 || numel(gT) < 2
    return;
end
[TT, RR] = meshgrid(gT, gR);
f = @(t, r) interp2(TT, RR, RV, t, r, 'linear');
nc = 13;
te = linspace(gT(1), gT(end), nc + 1);
re = linspace(gR(1), gR(end), nc + 1);
amax = max(abs(RV(:)));
if ~(amax > 0)
    amax = 1;
end
cm = flipud(S.div);
[fig, P, isPanel] = panelHost(S, 5.6, 4.6, target);
ax = axes(fig, 'Position', P([0.14, 0.30, 0.80, 0.62]));
hold(ax, 'on');
vals = [];
for i = 1:nc
    for j = 1:nc
        x0 = te(i); x1 = te(i + 1); y0 = re(j); y1 = re(j + 1);
        tri = {[x0, y0; x1, y0; x0, y1], [x1, y0; x1, y1; x0, y1]};
        for t = 1:2
            c = mean(tri{t}, 1);
            v = f(c(1), c(2));
            vals(end + 1) = v; %#ok<AGROW>
            patch(ax, tri{t}(:, 1), tri{t}(:, 2), mapColors(cm, 0.5 + 0.5 * v / amax), 'EdgeColor', 'w', 'LineWidth', 0.5);
        end
    end
end
[Tf, Rf] = meshgrid(linspace(gT(1), gT(end), 200), linspace(gR(1), gR(end), 200));
Vf = f(Tf, Rf);
lev = setdiff(round(linspace(-amax, amax, 7), 1, 'significant'), 0);
if numel(lev) >= 1
    [Cm, hc] = contour(ax, Tf, Rf, Vf, lev, ':', 'LineColor', [0.35, 0.35, 0.35], 'LineWidth', 0.5);
    clabel(Cm, hc, 'FontSize', S.fs - 2, 'Color', [0.35, 0.35, 0.35]);
end
if min(Vf(:)) < 0 && max(Vf(:)) > 0
    contour(ax, Tf, Rf, Vf, [0, 0], '-', 'LineColor', [0.48, 0.12, 0.12], 'LineWidth', 1.8);
    text(ax, 0.97, 0.06, 'RV = 0', 'Units', 'normalized', 'HorizontalAlignment', 'right', 'FontSize', S.fs - 0.5, ...
        'FontWeight', 'bold', 'Color', [0.48, 0.12, 0.12]);
end
if gT(1) <= 1 && gT(end) >= 1 && gR(1) <= 1 && gR(end) >= 1
    plot(ax, 1, 1, 'p', 'MarkerSize', 12, 'MarkerFaceColor', S.ink, 'MarkerEdgeColor', 'w');
    text(ax, 1.02, 1.006, lab(S, '基准', 'Base'), 'FontSize', S.fs - 0.5, 'Color', S.ink);
end
xlim(ax, gT([1, end]));
ylim(ax, gR([1, end]));
styleAxes(ax, S);
xlabel(ax, lab(S, '运价倍数', 'Freight rate (\times base)'));
ylabel(ax, lab(S, '实际往返效率倍数', 'Round-trip efficiency (\times base)'));
badge(ax, 0.83, 0.92, sprintf(lab(S, 'RV > 0 占 %.0f%%', 'RV > 0 in %.0f%%'), 100 * mean(vals > 0)), S, S.hero, 'Units', 'normalized');
tv = round(linspace(-amax, amax, 5), 1, 'significant');
cbl = 'Retained value RV (10^8 CNY)';
if comp
    cbl = 'Retained value RV, comprehensive account (10^8 CNY)';
end
drawColorbar(fig, P([0.14, 0.06, 0.60, 0.025]), mapColors(cm, linspace(0, 1, 256)), [-amax, amax], tv, [], cbl, S, 'h');
finishFigure(fig, S, outBase, isPanel, '');
end
