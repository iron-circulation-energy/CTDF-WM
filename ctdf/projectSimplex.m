function X = projectSimplex(Y, s)
%PROJECTSIMPLEX 各列到缩放单纯形 {x ≥ 0, 1ᵀx = s} 的欧氏投影（Duchi 等排序算法，O(n log n)）。
%   终端投影 Π：闭凸集上的欧氏投影是 1-Lipschitz 的，故 W_p(Π#q, m) ≤ W_p(q, m)。
%   Y：n×B；s：标量或 1×B。

[n, B] = size(Y);
if isscalar(s)
    s = s * ones(1, B, 'like', Y);
end
U = sort(Y, 1, 'descend');
css = cumsum(U, 1) - s;
ind = (1:n)';
cond = U - css ./ ind > 0;
rho = sum(cond, 1);                         % 满足条件的最大下标（单调性保证为前缀）
rho = max(rho, 1);
lin = sub2ind([n, B], rho, 1:B);
theta = css(lin) ./ rho;
X = max(Y - theta, 0);
end
