function scaleForExport(fig)
%SCALEFOREXPORT 导出前统一字体：Times New Roman、加粗，基准字号放大到目标字号（默认 18 磅）。
%   图在 styledFigure 中按绘制字号（正文图 7 磅、补充图 9 磅）排版；导出时图窗尺寸、全部字号、线宽与标记
%   按同一倍数 k = 目标字号 / 绘制字号 放大，版面比例与原图一致，只是整体等比放大。
%   绘制字号与目标设置由 styledFigure 写入图窗的 appdata（CTDF_export）。
E = [];
try
    E = getappdata(fig, 'CTDF_export');
catch
end
if isempty(E) || ~isfield(E, 'baseFs') || ~(E.baseFs > 0)
    return;
end
if isappdata(fig, 'CTDF_scaled')
    return;                                               % 已放大，不重复处理
end
k = E.fs / E.baseFs;
% 1 坐标刻度先固定：输出尺寸改变后 MATLAB 不再重新选取刻度，刻度与标签保持一一对应
for ax = findall(fig, 'Type', 'axes')'
    for d = {'X', 'Y', 'Z'}
        try
            set(ax, [d{1}, 'Tick'], get(ax, [d{1}, 'Tick']));
        catch
        end
    end
end
for cb = findall(fig, 'Type', 'colorbar')'
    try
        set(cb, 'Ticks', get(cb, 'Ticks'));
    catch
    end
end
% 输出纸张按 k 等比放大；屏幕图窗尺寸不变（大图窗会被屏幕尺寸截断、改变长宽比），导出时按纸张尺寸排版
u = get(fig, 'Units');
set(fig, 'Units', 'inches');
pos = get(fig, 'Position');
set(fig, 'Units', u);
w = pos(3) * k;
h = pos(4) * k;
set(fig, 'PaperUnits', 'inches', 'PaperPositionMode', 'manual', 'PaperSize', [w, h], 'PaperPosition', [0, 0, w, h]);
% 2 字号、字体与加粗：先处理文本（含坐标轴标签与标题），再处理坐标轴、图例与色标，避免二次放大
txt = findall(fig, 'Type', 'text');
fsT = {};
if ~isempty(txt), fsT = get(txt, {'FontSize'}); end
oth = findall(fig, '-property', 'FontSize');
if ~isempty(oth)
    ty = get(oth, {'Type'});
    oth = oth(~strcmp(ty, 'text'));
end
fsO = {};
if ~isempty(oth), fsO = get(oth, {'FontSize'}); end
for i = 1:numel(txt)
    try
        set(txt(i), 'FontSize', fsT{i} * k, 'FontName', E.font, 'FontWeight', E.weight);
    catch
    end
end
for i = 1:numel(oth)
    try
        set(oth(i), 'FontSize', fsO{i} * k, 'FontName', E.font, 'FontWeight', E.weight);
    catch
    end
end
% 2b 文字：残留中文替换为英文，全角标点换为半角
for h = findall(fig, '-property', 'String')'
    try
        if ~isa(h, 'matlab.ui.control.UIControl')
            set(h, 'String', enText(get(h, 'String')));
        end
    catch
    end
end
hasCJK = @(v) any(cellfun(@(q) any(double(q) > 127 & ~ismember(double(q), double('−–—×≤≥°·±µκγεΔ'))), cellstr(v)));
for h = findall(fig, 'Type', 'axes')'
    for ax = {'XTickLabel', 'YTickLabel', 'ZTickLabel'}
        try
            v = get(h, ax{1});
            if ~isempty(v) && hasCJK(v)
                set(h, ax{1}, enText(v));
            end
        catch
        end
    end
end
for h = findall(fig, 'Type', 'colorbar')'
    try
        v = get(h, 'TickLabels');
        if ~isempty(v) && hasCJK(v)
            set(h, 'TickLabels', enText(v));
        end
    catch
    end
end
left = {};
for h = findall(fig, '-property', 'String')'
    try
        v = get(h, 'String');
        v = cellstr(v);
        v = v(cellfun(@(q) any(q >= 19968 & q <= 40959), v));
        left = [left, v(:)']; %#ok<AGROW>
    catch
    end
end
if ~isempty(left)
    fprintf('  [英文检查] %s 中仍有中文：%s\n', get(fig, 'Name'), strjoin(unique(left), ' | '));
end
% 3 线宽、标记大小与散点面积
L = findall(fig, '-property', 'LineWidth');
for i = 1:numel(L)
    try
        set(L(i), 'LineWidth', get(L(i), 'LineWidth') * k);
    catch
    end
end
M = findall(fig, '-property', 'MarkerSize');
for i = 1:numel(M)
    try
        set(M(i), 'MarkerSize', get(M(i), 'MarkerSize') * k);
    catch
    end
end
Sc = findall(fig, 'Type', 'scatter');
for i = 1:numel(Sc)
    try
        set(Sc(i), 'SizeData', get(Sc(i), 'SizeData') * k ^ 2);
    catch
    end
end
setappdata(fig, 'CTDF_scaled', true);
drawnow;
end
