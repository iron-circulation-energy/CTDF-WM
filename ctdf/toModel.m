function X = toModel(S, c, norm)
%TOMODEL 原始状态 → 模型坐标（列为样本）。物料分量缩放到和为 n 的单纯形，其余分量标准化。
%   S：D×M（原始），c：1×M 或标量（各样本循环铁总质量）。

n = norm.n;
c = reshape(c, 1, []);
X = zeros(size(S), 'like', S);
X(1:n, :) = norm.matScale * S(1:n, :) ./ c;
X(n + 1:end, :) = (S(n + 1:end, :) - norm.mu) ./ norm.sd;
end
