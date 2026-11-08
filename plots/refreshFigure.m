function ok = refreshFigure(base, baseFs)
%REFRESHFIGURE 打开已保存的 base.fig，按统一规范（Times New Roman 加粗、18 磅、全英文）重新导出 .pdf/.png/.fig。
%   用于补充图：其数据与版面不变，只需更新字体、字号与残留中文，无需重新计算。
%   已按新规范导出的图（appdata CTDF_scaled）直接跳过。baseFs 为原图绘制字号（缺省 9 磅）。
if nargin < 2 || isempty(baseFs)
    baseFs = 9;
end
ok = false;
f = [base, '.fig'];
if ~isfile(f)
    return;
end
fig = openfig(f, 'invisible');
if isappdata(fig, 'CTDF_scaled')
    close(fig);
    ok = true;
    return;
end
if ~isappdata(fig, 'CTDF_export')
    setappdata(fig, 'CTDF_export', struct('baseFs', baseFs, 'fs', 18, 'font', 'Times New Roman', 'weight', 'bold'));
end
set(fig, 'Visible', 'off');
[~, nm] = fileparts(base);
set(fig, 'Name', nm);
saveFigure(fig, base);
ok = true;
end
