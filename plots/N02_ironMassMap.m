function N02_ironMassMap(R, S, outBase)
%N02_IRONMASSMAP 图 N02：临界循环铁质量。分级设色为每吉瓦改造容量所需的循环铁量（kt/GW，序列峰值库存 + 在途量），
%   实心圆面积 ∝ 铁基路线获胜省份按获胜路线所需的循环铁量（Mt，MtWin），空心圆为其余省份就地铁循环口径的参考值（MtSP），
%   标注获胜省份中铁量最大的 8 个；左下角给出获胜省份合计及其与 2019 年全国粗钢产量之比，并附全部省份就地参考总量。

T = R.T;
ext = [73.0, 135.5, 17.5, 54.0];
v = T.tPerMW;                                       % t/MW = kt/GW
cl = [0, ceil(max(v) / 100) * 100];
if cl(2) <= 0
    cl(2) = 1;
end
cols = mapColors(S.seq, v / cl(2));
fig = styledFigure(S, 7.0, 5.3);
ax = axes(fig, 'Position', [0.01, 0.13, 0.98, 0.86]);
drawProvMap(ax, S, ext, T.name, cols);
G = loadChinaMap();
[~, loc] = ismember(string(T.name), string(G.provName(:)));
xy = G.provLabel(loc, :);
M = T.MtWin;
Mref = T.MtSP;
k = 220 / max(max([M; Mref]), eps);                  % 最大圆圈面积 220 pt²
ref = ~(M > 0) & Mref > 0;
scatter(ax, xy(ref, 1), xy(ref, 2), 6 + Mref(ref) * k, S.accent, 'MarkerEdgeColor', S.accent, 'LineWidth', 0.5, ...
    'MarkerEdgeAlpha', 0.45);
has = M > 0;
scatter(ax, xy(has, 1), xy(has, 2), 6 + M(has) * k, S.accent, 'filled', 'MarkerFaceAlpha', 0.45, ...
    'MarkerEdgeColor', S.accent, 'LineWidth', 0.6);
[~, o] = sort(M, 'descend');
for q = o(1:min(8, numel(o)))'
    if M(q) <= 0
        continue;
    end
    text(ax, xy(q, 1) + 0.9, xy(q, 2) + 0.7, sprintf('%s %.0f Mt', T.short(q), M(q)), 'FontSize', S.fs - 1.5, ...
        'Color', S.ink);
end
b = R.scen(1, :);
text(ax, 74.5, 25.0, sprintf(lab(S, '铁基路线获胜省份合计 %.0f Mt\n= 2019 年全国粗钢产量的 %.0f%%\n（事件缓冲估计 %.0f Mt；全部省份就地参考 %.0f Mt）', ...
    'Iron-led provinces %.0f Mt\n= %.0f%% of 2019 crude steel\nevent-buffer estimate %.0f Mt; all-province local reference %.0f Mt'), ...
    b.MtTotal, 100 * b.steelShare, b.MtThmTotal, b.MtRefAll), 'FontSize', S.fs - 0.5, 'Color', S.ink, 'VerticalAlignment', 'top');
colormap(ax, S.seq);
clim(ax, cl);
axPos = ax.Position;
cb = colorbar(ax, 'southoutside');
cb.Position = [0.08, 0.105, 0.30, 0.018];
ax.Position = axPos;
styleColorbar(cb, S, lab(S, '单位改造容量的循环铁量/(kt·GW^{-1})', 'Circulating iron per retrofit GW (kt GW^{-1})'));
addNanhaiInset(fig, S, [0.81, 0.15, 0.13, 0.22], T.name, cols);
addNote(fig, S, sprintf(lab(S, '改造容量取 %d 年及以后投运的煤电与本省稳定供电需求的较小者；实心圆为获胜路线铁量，空心圆为就地参考', ...
    'Retrofit capacity: lesser of units commissioned from %d and provincial service; filled, winning-route iron; open, local reference'), R.n.coal.yearMin));
saveFigure(fig, outBase);
end
