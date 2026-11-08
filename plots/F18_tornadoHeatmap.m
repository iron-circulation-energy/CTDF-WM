function F18_tornadoHeatmap(e6, S, outBase)
%F18_TORNADOHEATMAP 图 F18：单因素敏感性（差值热力图；模板 4 右；E6）。
%   行：敏感性因素（括号内为低 / 高水平）；列：低、高水平下保留资产价值相对基准的变化（亿元）与断供概率的变化（百分点）。
%   颜色按指标分组归一化，正值（青蓝）为有利（保留资产价值增加或断供概率下降），赭色为不利。

T = e6.tornado;
b = e6.base;
nr = height(T);
dRV = ([T.RVlow, T.RVhigh] - b.RV) / 1e8;
dPF = 100 * ([T.pFlow, T.pFhigh] - b.pF);
D = [dRV, dPF];
sRV = max(max(abs(dRV(:))), eps);
sPF = max(max(abs(dPF(:))), eps);
G = [dRV / sRV, -dPF / sPF];
tt = (G + 1) / 2;
cm = flipud(S.div);
rowLab = cell(nr, 1);
for k = 1:nr
    rowLab{k} = sprintf('%s（%s / %s）', T.Label{k}, toStr(T.Low(k)), toStr(T.High(k)));
end
colLab = lab(S, {'保留资产价值\newline低水平', '保留资产价值\newline高水平', '断供概率\newline低水平', '断供概率\newline高水平'}, ...
    {'Retained value\newlinelow', 'Retained value\newlinehigh', 'Starvation\newlinelow', 'Starvation\newlinehigh'});
fig = styledFigure(S, 6.8, 1.4 + 0.42 * nr);
ax = axes(fig, 'Position', [0.30, 0.20, 0.55, 0.74]);
hold(ax, 'on');
for a = 1:nr
    for c = 1:4
        patch(ax, c + [-0.5, 0.5, 0.5, -0.5], a + [-0.5, -0.5, 0.5, 0.5], mapColors(cm, tt(a, c)), ...
            'EdgeColor', 'w', 'LineWidth', 2.5);
        if c <= 2
            s = sprintf('%+.2f', D(a, c));
        else
            s = sprintf('%+.1f pp', D(a, c));
        end
        tc = S.ink;
        if tt(a, c) > 0.82 || tt(a, c) < 0.18
            tc = [1, 1, 1];
        end
        text(ax, c, a, s, 'HorizontalAlignment', 'center', 'Color', tc);
    end
end
plot(ax, [2.5, 2.5], [0.5, nr + 0.5], '-', 'Color', 'w', 'LineWidth', 5);
set(ax, 'YDir', 'reverse', 'YTick', 1:nr, 'YTickLabel', rowLab, 'XTick', 1:4, 'XTickLabel', colLab, ...
    'TickLength', [0, 0]);
xlim(ax, [0.5, 4.5]);
ylim(ax, [0.5, nr + 0.5]);
styleAxes(ax, S);
set(ax, 'TickLength', [0, 0]);
colormap(ax, cm);
clim(ax, [-1, 1]);
axPos = ax.Position;
cb = colorbar(ax);
cb.Position = [0.88, 0.20, 0.018, 0.74];
ax.Position = axPos;
cb.Ticks = [-1, 0, 1];
cb.TickLabels = lab(S, {'不利', '0', '有利'}, {'adverse', '0', 'favourable'});
styleColorbar(cb, S, lab(S, '按指标归一化的变化', 'Normalised change'));
addNote(fig, S, sprintf(lab(S, '基准：保留资产价值 %.2f 亿元，断供概率 %.1f%%', 'Base: retained value %.2f×10^8 CNY, starvation %.1f%%'), b.RV / 1e8, 100 * b.pF));
saveFigure(fig, outBase);
end

function s = toStr(v)
if iscell(v)
    v = v{1};
end
if isnumeric(v)
    s = num2str(v);
else
    s = char(v);
end
end
