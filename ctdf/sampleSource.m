function X0 = sampleSource(meta, nMat, matScale, B, cfg, rs)
%SAMPLESOURCE 源分布 m_0：物料分量 X0_mat = matScale·Dirichlet(α)，位于守恒可行集的相对内部；
%   外生、辅助与成本分量取 N(0, I)。cfg.sourceType = 'gaussian' 时全部分量取 N(0, I)（Dirichlet 源对照与 M4）。
%   输出 X0：D×B，精度为 cfg.precision。

D = meta.dimX;
X0 = zeros(D, B);
switch lower(cfg.sourceType)
    case 'dirichlet'
        X0(1:nMat, :) = matScale * sampleDirichlet(cfg.alphaDir, nMat, B, rs);
        X0(nMat + 1:end, :) = randn(rs, D - nMat, B);
    case 'gaussian'
        X0 = randn(rs, D, B);
    otherwise
        error('sampleSource:type', '未知源分布 %s。', cfg.sourceType);
end
X0 = cast(X0, cfg.precision);
end
