function S = fromModel(X, c, norm)
%FROMMODEL 模型坐标 → 原始状态（toModel 的逆变换）。

n = norm.n;
c = reshape(c, 1, []);
S = zeros(size(X), 'like', X);
S(1:n, :) = X(1:n, :) .* c / norm.matScale;
S(n + 1:end, :) = X(n + 1:end, :) .* norm.sd + norm.mu;
end
