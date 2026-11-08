function norm = buildNormalizer(ds, ctx)
%BUILDNORMALIZER 世界模型坐标变换参数。
%   物料分量：x̃ = n·x / c，使守恒集合 {x ≥ 0, 1ᵀx = c} 变为和为 n 的缩放单纯形（各分量量级约为 1）；
%   其余分量（外生、辅助、成本）：(v − μ)/σ，σ 下限 1e−6；常数分量（σ < 1e−6）取 σ = 1。
%   条件输入另加 log(c / cRef)，cRef 取训练状态 c 的中位数。

L = ctx.L;
n = L.n;
S = double(ds.S(L.iOther, :));
mu = mean(S, 2);
sd = std(S, 0, 2);
sd(sd < 1e-6) = 1;
norm.n = n;
norm.matScale = n;
norm.mu = mu;
norm.sd = sd;
norm.cRef = median(ds.c);
norm.D = L.D;
end
