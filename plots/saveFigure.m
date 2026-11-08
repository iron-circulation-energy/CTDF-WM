function saveFigure(fig, outBase)
%SAVEFIGURE 保存图为 .fig、.pdf（矢量）与 .png（600 dpi）。
%   运行时图以不可见方式生成，保存后关闭（长时间运行不堆积图窗、不抢占焦点）；重新打开 .fig 时可见，
%   可用 showFigures 一次打开全部结果图。setappdata(groot, 'CTDF_keepFigures', true) 后，保存的图保持打开并显示。

[d, ~] = fileparts(outBase);
if ~isempty(d) && ~exist(d, 'dir')
    mkdir(d);
end
scaleForExport(fig);                                        % Times New Roman 加粗，目标字号（默认 18 磅）
set(fig, 'CreateFcn', 'set(gcbo, ''Visible'', ''on'')');   % 以不可见方式生成，重新打开 .fig 时可见
savefig(fig, [outBase, '.fig']);
if isappdata(fig, 'CTDF_scaled')
    % 按纸张尺寸输出（见 scaleForExport）：矢量 PDF 与 300 dpi PNG（纸张已放大，折合成图尺寸约 700 dpi 以上）
    try
        print(fig, [outBase, '.pdf'], '-dpdf', '-vector');
    catch
        print(fig, [outBase, '.pdf'], '-dpdf', '-painters');
    end
    print(fig, [outBase, '.png'], '-dpng', '-r300');
else
    exportgraphics(fig, [outBase, '.pdf'], 'ContentType', 'vector');
    exportgraphics(fig, [outBase, '.png'], 'Resolution', 600);
end
keep = false;
try
    k = getappdata(groot, 'CTDF_keepFigures');
    keep = ~isempty(k) && logical(k(1));
catch
end
if keep
    [~, nm] = fileparts(outBase);
    set(fig, 'Visible', 'on', 'Name', nm, 'NumberTitle', 'off');
    drawnow;
else
    close(fig);
end
end
