function [fig, P, isPanel] = panelHost(S, w, h, target)
%PANELHOST 单图或正文面板的绘图宿主。
%   target 为空时新建 w×h 英寸图窗（单图，补充材料用）；target 为 struct('fig', 图窗, 'pos', [x y w h]) 时，
%   在组合图的给定归一化区域内作图（正文面板用）。P(q) 把单图内的归一化位置 q 映射到该区域，
%   用于 axes、colorbar、legend 与 annotation 的 Position；isPanel 为真时调用方不保存图窗、不加注记。
if nargin < 4 || isempty(target)
    fig = styledFigure(S, w, h);
    P = @(q) q;
    isPanel = false;
else
    fig = target.fig;
    r = target.pos;
    P = @(q) [r(1) + q(1) * r(3), r(2) + q(2) * r(4), q(3) * r(3), q(4) * r(4)];
    isPanel = true;
end
end
