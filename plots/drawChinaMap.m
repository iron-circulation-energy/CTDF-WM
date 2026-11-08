function drawChinaMap(ax, S, ext, opts)
%DRAWCHINAMAP 在坐标轴 ax 上绘制省级底图（陆地浅灰、省界白色），只绘制与范围 ext = [lon0, lon1, lat0, lat1]
%   相交的多边形；南海断续线以灰色绘制（全国范围时可见）。opts 字段（可选）：
%     edge     省界线宽（缺省 0.8）；labels  是否标注省名（缺省 true）；fs  省名字号（缺省 S.fs − 0.5）；
%     land     陆地颜色（缺省 S.land）。
%   坐标轴按中纬度设置等距纵横比：经度 1° 的显示长度 = cos(φ)·纬度 1°。

if nargin < 4
    opts = struct();
end
edgeW = getOpt(opts, 'edge', 0.8);
showLab = getOpt(opts, 'labels', true);
fsLab = getOpt(opts, 'fs', S.fs - 0.5);
landC = getOpt(opts, 'land', S.land);
G = loadChinaMap();
hold(ax, 'on');
for i = 1:numel(G.provName)
    rings = G.provRings{i};
    for k = 1:numel(rings)
        r = rings{k};
        if max(r(:, 1)) < ext(1) || min(r(:, 1)) > ext(2) || max(r(:, 2)) < ext(3) || min(r(:, 2)) > ext(4)
            continue;
        end
        fill(ax, r(:, 1), r(:, 2), landC, 'EdgeColor', 'w', 'LineWidth', edgeW);
    end
end
for k = 1:numel(G.bndLines)
    s = G.bndLines{k};
    if G.bndIsNanhai(k)
        plot(ax, s(:, 1), s(:, 2), '-', 'Color', [0.55, 0.55, 0.55], 'LineWidth', 0.8);
    else
        plot(ax, s(:, 1), s(:, 2), '-', 'Color', [0.80, 0.80, 0.80], 'LineWidth', 0.4);
    end
end
if showLab
    for i = 1:numel(G.provName)
        L = G.provLabel(i, :);
        if L(1) > ext(1) + 0.4 && L(1) < ext(2) - 0.4 && L(2) > ext(3) + 0.3 && L(2) < ext(4) - 0.3
            nm = regexprep(char(G.provName{i}), '(省|市|壮族自治区|回族自治区|维吾尔自治区|自治区|特别行政区)$', '');
            if isfield(S, 'lang') && strcmpi(S.lang, 'en')
                nm = char(provEnglish({nm}));
            end
            text(ax, L(1), L(2), nm, 'Color', [0.64, 0.67, 0.70], 'FontSize', fsLab, 'FontName', S.font, ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
        end
    end
end
xlim(ax, ext(1:2));
ylim(ax, ext(3:4));
daspect(ax, [1 / cosd(mean(ext(3:4))), 1, 1]);
set(ax, 'XTick', [], 'YTick', [], 'Box', 'on', 'XColor', [0.79, 0.79, 0.79], 'YColor', [0.79, 0.79, 0.79], ...
    'LineWidth', 0.6, 'Color', 'w');
end

function v = getOpt(s, f, d)
if isfield(s, f)
    v = s.(f);
else
    v = d;
end
end
