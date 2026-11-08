function drawProvMap(ax, S, ext, names, cols, opts)
%DRAWPROVMAP 省级分级设色底图（全国图 N01—N05）：按省名把颜色 cols（numel(names)×3，NaN 行为无数据）填入
%   用户提供的标准底图，未列出或无数据的省份（如未评估的港澳台）用浅灰；绘制省界、国界与南海断续线。
%   drawProvMap(ax, S, ext, names, cols, opts)，ext = [lon0, lon1, lat0, lat1]。opts（可选）：
%     edge     省界线宽（缺省 0.45）；edgeColor（缺省白色）；noData（缺省 [0.92 0.92 0.92]）；
%     labels   是否标注省名（缺省 false）；labelColor（缺省 S.ink）；fs（缺省 S.fs − 1.5）。
%   多边形按面积从大到小绘制，省内“洞”（被其他省份包围的飞地）不单独填色，由飞地所属省份的多边形覆盖，
%   因此不需要多边形布尔运算。纵横比与 drawChinaMap 相同（中纬度等距）。

if nargin < 6
    opts = struct();
end
edgeW = getOpt(opts, 'edge', 0.45);
edgeC = getOpt(opts, 'edgeColor', [1, 1, 1]);
noData = getOpt(opts, 'noData', [0.92, 0.92, 0.92]);
G = loadChinaMap();
info = ringInfo(G);
nG = numel(G.provName);
fc = repmat(noData, nG, 1);
[tf, loc] = ismember(cellstr(G.provName(:)), cellstr(names(:)));
for i = find(tf)'
    c = cols(loc(i), :);
    if all(isfinite(c))
        fc(i, :) = c;
    end
end
hold(ax, 'on');
for q = 1:size(info, 1)
    i = info(q, 1);
    k = info(q, 2);
    r = G.provRings{i}{k};
    if max(r(:, 1)) < ext(1) || min(r(:, 1)) > ext(2) || max(r(:, 2)) < ext(3) || min(r(:, 2)) > ext(4)
        continue;
    end
    patch(ax, r(:, 1), r(:, 2), fc(i, :), 'EdgeColor', edgeC, 'LineWidth', edgeW);
end
for k = 1:numel(G.bndLines)
    s = G.bndLines{k};
    if G.bndIsNanhai(k)
        plot(ax, s(:, 1), s(:, 2), '-', 'Color', [0.45, 0.45, 0.45], 'LineWidth', 0.8);   % 南海断续线
    else
        plot(ax, s(:, 1), s(:, 2), '-', 'Color', [0.62, 0.62, 0.62], 'LineWidth', 0.5);
    end
end
if getOpt(opts, 'labels', false)
    fsLab = getOpt(opts, 'fs', S.fs - 1.5);
    lc = getOpt(opts, 'labelColor', S.ink);
    for i = 1:nG
        L = G.provLabel(i, :);
        skip = any(strcmp(G.provName{i}, {'香港特别行政区', '澳门特别行政区'}));   % 面积过小，不标注
        if ~skip && L(1) > ext(1) && L(1) < ext(2) && L(2) > ext(3) && L(2) < ext(4)
            nm = regexprep(char(G.provName{i}), '(省|市|壮族自治区|回族自治区|维吾尔自治区|自治区|特别行政区)$', '');
            if isfield(S, 'lang') && strcmpi(S.lang, 'en')
                nm = char(provEnglish({nm}));
            end
            text(ax, L(1), L(2), nm, 'Color', lc, 'FontSize', fsLab, 'FontName', S.font, ...
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

function info = ringInfo(G)
% 各环的 [省序号, 环序号]（只含外环），按面积从大到小排序；外环/洞的判断：首顶点落在同省更大环内即为洞
persistent cache
if ~isempty(cache)
    info = cache;
    return;
end
rows = zeros(0, 3);
for i = 1:numel(G.provName)
    R = G.provRings{i};
    nr = numel(R);
    a = zeros(nr, 1);
    for k = 1:nr
        a(k) = polyarea(R{k}(:, 1), R{k}(:, 2));
    end
    for k = 1:nr
        hole = false;
        for j = find(a > a(k))'
            if inpolygon(R{k}(1, 1), R{k}(1, 2), R{j}(:, 1), R{j}(:, 2))
                hole = true;
                break;
            end
        end
        if ~hole
            rows(end + 1, :) = [i, k, a(k)]; %#ok<AGROW>
        end
    end
end
[~, o] = sort(rows(:, 3), 'descend');
info = rows(o, 1:2);
cache = info;
end

function v = getOpt(s, f, d)
if isfield(s, f)
    v = s.(f);
else
    v = d;
end
end
