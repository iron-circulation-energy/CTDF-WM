function C = mapColors(cmap, t)
%MAPCOLORS 把 [0, 1] 内的数值 t 映射为色图 cmap（K×3）中的颜色（线性插值），输出 numel(t)×3。

t = min(1, max(0, t(:)));
K = size(cmap, 1);
C = interp1(linspace(0, 1, K), cmap, t);
end
