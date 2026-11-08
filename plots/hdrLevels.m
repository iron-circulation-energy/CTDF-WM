function lv = hdrLevels(Z, mass)
%HDRLEVELS 最高密度区域的等值线水平：返回密度阈值，使阈值以上区域包含的概率质量依次为 mass（升序输入）。
%   输出按升序排列的阈值（与 contour 的 levels 要求一致）。

z = sort(Z(:), 'descend');
c = cumsum(z) / max(sum(z), eps);
lv = zeros(size(mass));
for k = 1:numel(mass)
    i = find(c >= mass(k), 1, 'first');
    if isempty(i)
        i = numel(z);
    end
    lv(k) = z(i);
end
lv = unique(sort(lv(lv > 0)));
end
