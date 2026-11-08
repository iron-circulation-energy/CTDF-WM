function F15_gradVarSurface(model, S, outBase)
%F15_GRADVARSURFACE 图 F15：γ 课程各阶段内微批梯度方差 Tr Cov 随训练步的变化（三维曲面；模板 7；学习诊断）。
%   纵深为 γ 阶段，横轴为阶段内训练步，高度与颜色为 log10 Tr Cov；图下方注明各阶段末目标网络与后继测度真值（验证状态）
%   的 W1 距离。阶段内记录步不齐时以 NaN 留空。

dg = model.diag;
G = dg.gradVar;
if isempty(G)
    return;
end
st = unique(G(:, 1))';
sp = unique(G(:, 2))';
Z = nan(numel(st), numel(sp));
for r = 1:size(G, 1)
    Z(st == G(r, 1), sp == G(r, 2)) = log10(max(G(r, 3), realmin));
end
fig = styledFigure(S, 6.2, 4.8);
ax = axes(fig, 'Position', [0.08, 0.10, 0.70, 0.84]);
hold(ax, 'on');
is3 = numel(st) >= 2 && numel(sp) >= 2;
if is3
    [X, Y] = meshgrid(sp, 1:numel(st));
    surf(ax, X, Y, Z, 'EdgeColor', [1, 1, 1] * 0.92, 'EdgeAlpha', 0.3, 'FaceColor', 'interp');
    for k = 1:numel(st)
        plot3(ax, sp, k * ones(size(sp)), Z(k, :) + 0.01, '-', 'Color', S.accent, 'LineWidth', 1.0);
    end
    view(ax, 132, 28);
else
    for k = 1:numel(st)
        plot(ax, sp, Z(k, :), '-o', 'Color', S.accent, 'DisplayName', sprintf('γ = %.2f', dg.stageGamma(st(k))));
    end
end
colormap(ax, S.seq);
zl = [min(Z(:), [], 'omitnan'), max(Z(:), [], 'omitnan')];
if zl(2) > zl(1)
    clim(ax, zl);
end
xlabel(ax, lab(S, '阶段内训练步', 'Step within stage'));
if is3
    set(ax, 'YTick', 1:numel(st), 'YTickLabel', arrayfun(@(g) sprintf('γ = %.2f', g), dg.stageGamma(st), ...
        'UniformOutput', false));
    zlabel(ax, 'log_{10} Tr Cov');
    style3d(ax, S);
else
    ylabel(ax, 'log_{10} Tr Cov');
    styleAxes(ax, S, true);
    legend(ax, 'Location', 'best', 'Box', 'off');
end
axPos = ax.Position;
cb = colorbar(ax);
cb.Position = [0.86, 0.30, 0.022, 0.42];
ax.Position = axPos;
styleColorbar(cb, S, 'log_{10} Tr Cov');
w = dg.horizonW1(:)';
txt = strjoin(arrayfun(@(g, v) sprintf('γ=%.2f：%.3g', g, v), dg.stageGamma(:)', w, 'UniformOutput', false), '，');
addNote(fig, S, [lab(S, '各阶段末缩放切片距离（验证状态诊断）', 'End-of-stage sliced distance on validation states'), txt]);
saveFigure(fig, outBase);
end
