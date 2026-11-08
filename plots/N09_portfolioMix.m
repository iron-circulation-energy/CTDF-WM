function N09_portfolioMix(R, S, outBase, target)
%N09_PORTFOLIOMIX 图 N09：省级长时储能最优组合（natPortfolio）在燃料路线关键假设下的构成。
%   每列为一个组合情景（R.Tport 的字段，基准在左），行为省份（按基准自治天数从长到短，与 N06 一致）；
%   横条为各路线承担的放电量份额（铁、氨、盐穴氢、储罐氢），列顶标出全国按电量加权的铁份额与铁进入组合的省数。
%   情景只改变一项假设（铁还原氢耗、氨设备成本、氨掺烧上限），不叠加。
if nargin < 4
    target = [];
end
if ~isfield(R, 'Tport') || isempty(fieldnames(R.Tport))
    warning('N09:noPortfolio', '未找到组合优化结果（R.Tport），跳过 N09。');
    return;
end
st = natRouteStyle(S);
nm = fieldnames(R.Tport);
nm = [nm(strcmp(nm, 'base')); nm(~strcmp(nm, 'base'))];
nS = numel(nm);
T0 = R.T;
D = tcol(T0, 'D');
[~, o] = sort(D, 'descend');
nP = numel(o);
provLab = tcol(T0, 'short', tcol(T0, 'name', {}));
provLab = provLab(o);
if strcmpi(S.lang, 'en')
    provLab = provEnglish(provLab);
end
cols = [st.color('FeL'); st.color('NH3L'); st.color('H2S'); st.color('H2T')];
labs = {lab(S, '铁粉—铁锈循环', 'Iron–rust loop'), lab(S, '绿氨', 'Green ammonia'), ...
    lab(S, '盐穴储氢', 'Salt-cavern hydrogen'), lab(S, '储罐储氢', 'Tank hydrogen')};
[fig, P, isPanel] = panelHost(S, 7.2, 4.4, target);
x0 = 0.12;
wAll = 0.86;
gap = 0.012;
w = (wAll - gap * (nS - 1)) / nS;
for k = 1:nS
    Tk = R.Tport.(nm{k});
    sh = [Tk.shareFe, Tk.shareNH3, Tk.shareH2S, Tk.shareH2T];
    sh = sh(o, :);
    ok = Tk.portOK(o);
    ax = axes(fig, 'Position', P([x0 + (k - 1) * (w + gap), 0.17, w, 0.62]));
    hold(ax, 'on');
    for i = 1:nP
        c0 = 0;
        for j = 1:4
            if sh(i, j) > 0
                patch(ax, c0 + [0, sh(i, j), sh(i, j), 0], i + [-0.38, -0.38, 0.38, 0.38], cols(j, :), ...
                    'EdgeColor', 'none');
                c0 = c0 + sh(i, j);
            end
        end
        if ~ok(i)
            text(ax, 0.5, i, '–', 'HorizontalAlignment', 'center', 'FontSize', S.fs - 2, 'Color', S.axis);
        end
    end
    set(ax, 'YDir', 'reverse');
    ylim(ax, [0.4, nP + 0.6]);
    xlim(ax, [0, 1]);
    styleAxes(ax, S, false, false);
    set(ax, 'XTick', [0, 0.5, 1], 'XTickLabel', {'0', '50', '100'}, 'FontSize', S.fs - 2, 'TickLength', [0, 0]);
    if k == 1
        set(ax, 'YTick', 1:nP, 'YTickLabel', provLab, 'FontSize', S.fs - 2.2);
    else
        set(ax, 'YTick', [], 'YColor', 'none');
    end
    wE = Tk.portEoutTWh(Tk.portOK);
    fe = sum(Tk.shareFe(Tk.portOK) .* wE) / max(sum(wE), eps);
    nFe = nnz(Tk.portOK & Tk.shareFe >= 0.05);
    ttl = scenLabel(R, nm{k}, S);
    text(ax, 0.5, -1.5 - 1.6 * mod(k + 1, 2), ttl, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', S.fs - 1.4, ...
        'FontWeight', 'bold', 'Color', S.ink, 'Clipping', 'off');
    text(ax, 0.5, -0.1, sprintf('iron %.0f%%, %d', 100 * fe, nFe), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', S.fs - 1.8, ...
        'Color', st.color('FeL'), 'Clipping', 'off');
    if k == 1
        hlBox(ax, 0, 0.4, 1, nP + 0.2, S, 1.0);
    end
end
ah = axes(fig, 'Position', P([x0, 0.105, wAll, 0.01]), 'Visible', 'off');
text(ah, 0.5, 0, lab(S, '放电量份额（%）', 'Share of discharged energy (%)'), 'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'top', 'FontSize', S.fs - 1.6, 'Color', S.ink);
items = struct('kind', {}, 'color', {}, 'label', {}, 'alpha', {}, 'lw', {});
for j = 1:4
    items(end + 1) = struct('kind', 'patch', 'color', cols(j, :), 'label', labs{j}, 'alpha', 1, 'lw', 1); %#ok<AGROW>
end
drawLegendBox(fig, P([x0, 0.0, wAll, 0.075]), items, S, 2, S.fs - 1.6);
finishFigure(fig, S, outBase, isPanel, '');
end

function s = scenLabel(R, name, S)
k = {'base', 'kappa161', 'nh3Cheap', 'nh3Blend50', 'nh3Blend35'};
en = {'Base', 'No H_2 recycle', 'Cheap NH_3', 'NH_3 \leq 50%', 'NH_3 \leq 35%'};
zh = {'基准', '不循环 κ 1.61', '绿氨设备下限', '氨掺烧 ≤ 50%', '氨掺烧 ≤ 35%'};
j = find(strcmp(k, name), 1);
if ~isempty(j)
    s = lab(S, zh{j}, en{j});
    return;
end
r = R.scen(R.scen.name == string(name), :);
s = name;
if ~isempty(r)
    s = char(r.label(1));
end
end
