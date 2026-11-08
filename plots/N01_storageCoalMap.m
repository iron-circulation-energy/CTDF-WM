function N01_storageCoalMap(R, N, S, outBase)
%N01_STORAGECOALMAP 图 N01：各省季节性储能需求（满功率自治天数 D，分级设色）与燃煤电厂分布（气泡，面积 ∝ 装机）。
%   D 由 ERA5 多年逐日风光与负荷经序列峰值法得到（natStorage，按铁粉路线往返效率）；
%   实心气泡为 n.coal.yearMin 年及以后投运的搁浅风险电厂，空心灰圈为更早投运的电厂（GPPD v1.3.0，约 2019 年）。

T = R.T;
ext = [73.0, 135.5, 17.5, 54.0];
v = T.D;
cl = [floor(min(v) / 5) * 5, ceil(max(v) / 5) * 5];
if diff(cl) <= 0
    cl = cl + [-5, 5];
end
cols = mapColors(S.seq, (v - cl(1)) / diff(cl));
fig = styledFigure(S, 7.0, 5.3);
ax = axes(fig, 'Position', [0.01, 0.13, 0.98, 0.86]);
drawProvMap(ax, S, ext, T.name, cols, struct('labels', true, 'labelColor', [0.25, 0.25, 0.25]));
C = N.coal;
old = ~C.young;
y = C.young & C.provIdx > 0;
k = 1 / 45;                                         % 气泡面积（pt²）= 4 + 装机/45
scatter(ax, C.lon(old), C.lat(old), 4 + C.mw(old) * k, [0.45, 0.45, 0.45], 'LineWidth', 0.4);
scatter(ax, C.lon(y), C.lat(y), 4 + C.mw(y) * k, S.accent, 'filled', 'MarkerFaceAlpha', 0.55, ...
    'MarkerEdgeColor', [1, 1, 1], 'LineWidth', 0.3);
% 气泡图例（左下角空白处）
x0 = 75.5;
y0 = 21.0;
ref = [1000, 3000, 5000];
for q = 1:3
    scatter(ax, x0 + (q - 1) * 3.0, y0, 4 + ref(q) * k, S.accent, 'filled', 'MarkerFaceAlpha', 0.55, ...
        'MarkerEdgeColor', [1, 1, 1]);
    text(ax, x0 + (q - 1) * 3.0, y0 - 1.6, sprintf('%d', ref(q)), 'HorizontalAlignment', 'center', ...
        'FontSize', S.fs - 2, 'Color', S.tick);
end
text(ax, x0 - 1.0, y0 + 1.9, sprintf(lab(S, '煤电装机/MW（实心：%d 年后投运）', 'Coal capacity (MW), filled: commissioned ≥ %d'), R.n.coal.yearMin), ...
    'FontSize', S.fs - 1.5, 'Color', S.ink);
colormap(ax, S.seq);
clim(ax, cl);
axPos = ax.Position;
cb = colorbar(ax, 'southoutside');
cb.Position = [0.08, 0.105, 0.30, 0.018];
ax.Position = axPos;
styleColorbar(cb, S, lab(S, '季节性储能满功率自治天数 D/d', 'Full-power autonomy, D (d)'));
addNanhaiInset(fig, S, [0.81, 0.15, 0.13, 0.22], T.name, cols);
addNote(fig, S, sprintf(lab(S, 'ERA5 %d—%d 年逐日风光与气温；风光配比为 2019 年装机；电厂：GPPD v1.3.0', ...
    'ERA5 %d–%d; 2019 wind–solar mix; plants from GPPD v1.3.0'), R.years(1), R.years(end)));
saveFigure(fig, outBase);
end
