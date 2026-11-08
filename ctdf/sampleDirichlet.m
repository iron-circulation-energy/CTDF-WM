function X = sampleDirichlet(alpha, n, B, rs)
%SAMPLEDIRICHLET 单位单纯形上的 Dirichlet(α·1) 样本（n×B，列和为 1）。
%   由 n 个独立 Gamma(α, 1) 变量归一化得到。α = 1 时为指数分布归一化；否则用 Marsaglia–Tsang
%   拒绝采样（α < 1 时用 Gamma(α+1)·U^(1/α) 变换）。全部使用给定随机流 rs，结果可复现，
%   不依赖统计工具箱。

if ~isscalar(alpha) || ~isfinite(alpha) || alpha <= 0
    error('sampleDirichlet:alpha', 'Dirichlet concentration must be finite and positive.');
end
if alpha == 1
    G = -log(max(rand(rs, n, B), realmin));
else
    G = gammaMT(alpha, n, B, rs);
end
X = G ./ sum(G, 1);
end

function G = gammaMT(alpha, n, B, rs)
boost = 1;
a = alpha;
if alpha < 1
    a = alpha + 1;
    boost = rand(rs, n, B) .^ (1 / alpha);
end
d = a - 1 / 3;
c = 1 / sqrt(9 * d);
G = zeros(n, B);
todo = true(n, B);
while any(todo(:))
    m = nnz(todo);
    z = randn(rs, m, 1);
    v = (1 + c * z) .^ 3;
    u = rand(rs, m, 1);
    ok = v > 0 & log(u) < 0.5 * z .^ 2 + d - d * v + d * log(max(v, realmin));
    ids = find(todo);
    G(ids(ok)) = d * v(ok);
    todo(ids(ok)) = false;
end
G = G .* boost;
end
