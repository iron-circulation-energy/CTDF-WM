function F20_stateVector(ctx, x0, x1, S, outBase)
%F20_STATEVECTOR 图 F20（可选，方法示意）：物料状态向量 x 的分量布局与一日推进。
%   柱为推进后 x_{k+1} 的各分量（铁为青蓝、锈为赭色、虚拟储备为灰色），阶梯线为推进前 x_k；
%   竖虚线分隔库存组与各线路的在途管道格。

idx = ctx.idx;
topo = ctx.topo;
n = idx.n;
col = zeros(n, 3);
for k = 1:n
    switch idx.matOf(k)
        case 1
            col(k, :) = S.slate;
        case 2
            col(k, :) = S.accent;
        otherwise
            col(k, :) = [0.62, 0.62, 0.62];
    end
end
bnd = [idx.IFe(1), idx.IOx(1), idx.SFe(1), idx.SOx(1)];
if topo.nH > 0
    bnd = [bnd, idx.HFe(1), idx.HOx(1)];
end
for e = 1:topo.nE
    bnd(end + 1) = idx.q{e}(1); %#ok<AGROW>
end
bnd(end + 1) = idx.V;
fig = styledFigure(S, 7.0, 3.0);
ax = axes(fig, 'Position', [0.08, 0.18, 0.90, 0.74]);
hold(ax, 'on');
b = bar(ax, 1:n, x1(:) / 1e3, 1.0, 'FaceColor', 'flat', 'EdgeColor', 'none');
b.CData = col;
stairs(ax, (1:n + 1) - 0.5, [x0(:); x0(end)] / 1e3, '-', 'Color', S.ink, 'LineWidth', 0.8);
yl = ylim(ax);
for q = bnd
    plot(ax, [q - 0.5, q - 0.5], yl, ':', 'Color', [0.6, 0.6, 0.6], 'LineWidth', 0.6);
end
xlim(ax, [0.5, n + 0.5]);
styleAxes(ax, S, true);
ylabel(ax, lab(S, '物料/kt', 'Material (kt)'));
xlabel(ax, lab(S, '状态分量（库存 | 各线路在途管道格 q_{e,1..τ_e} | 虚拟储备 V）', 'State component: inventories | transit cells q_{e,1..τ_e} | reserve V'));
h = [patch(ax, NaN, NaN, S.slate, 'EdgeColor', 'none'), patch(ax, NaN, NaN, S.accent, 'EdgeColor', 'none'), ...
    plot(ax, nan, nan, '-', 'Color', S.ink)];
legend(ax, h, lab(S, {'铁（x_{k+1}）', '锈（x_{k+1}）', '推进前 x_k'}, {'Iron, x_{k+1}', 'Rust, x_{k+1}', 'Before update, x_k'}), 'Location', 'northeast', 'Box', 'off');
addNote(fig, S, '');
saveFigure(fig, outBase);
end
