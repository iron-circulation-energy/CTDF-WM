function idx = buildStateIndex(topo)
%BUILDSTATEINDEX 物料状态向量 x 的分量索引。
%   x 依次为：I^Fe_i、I^Ox_i（电厂）、S^Fe_j、S^Ox_j（还原站）、H^Fe_h、H^Ox_h（枢纽）、
%   各线路在途管道格 q_{e,1..τ_e}（q_{e,1} 为次日最先到达的一格）、虚拟储备 V。
%   全部按铁当量吨计。

nP = topo.nP; nR = topo.nR; nH = topo.nH; nE = topo.nE;
idx.IFe = (1:nP)';
idx.IOx = nP + (1:nP)';
idx.SFe = 2 * nP + (1:nR)';
idx.SOx = 2 * nP + nR + (1:nR)';
idx.HFe = 2 * nP + 2 * nR + (1:nH)';
idx.HOx = 2 * nP + 2 * nR + nH + (1:nH)';
off = 2 * nP + 2 * nR + 2 * nH;
idx.nInv = off;                       % 库存分量个数（不含管道与储备）
idx.q = cell(nE, 1);
for e = 1:nE
    idx.q{e} = off + (1:topo.tau(e))';
    off = off + topo.tau(e);
end
idx.V = off + 1;
idx.n = off + 1;

% 节点—物料到库存分量的映射：nodeInv(g, 1) 为铁库存，nodeInv(g, 2) 为锈库存
nodeInv = zeros(topo.nNodes, 2);
nodeInv(topo.R, 1) = idx.SFe;
nodeInv(topo.R, 2) = idx.SOx;
nodeInv(topo.P, 1) = idx.IFe;
nodeInv(topo.P, 2) = idx.IOx;
nodeInv(topo.H, 1) = idx.HFe;
nodeInv(topo.H, 2) = idx.HOx;
idx.nodeInv = nodeInv;

idx.lineSrc = zeros(nE, 1);
idx.lineTgt = zeros(nE, 1);
idx.qFirst = zeros(nE, 1);
idx.qLast = zeros(nE, 1);
for e = 1:nE
    idx.lineSrc(e) = nodeInv(topo.from(e), topo.mat(e));
    idx.lineTgt(e) = nodeInv(topo.to(e), topo.mat(e));
    idx.qFirst(e) = idx.q{e}(1);
    idx.qLast(e) = idx.q{e}(end);
end

% 每个分量的物料类型：1 = Fe，2 = Ox，0 = 虚拟储备
idx.matOf = zeros(idx.n, 1);
idx.matOf([idx.IFe; idx.SFe; idx.HFe]) = 1;
idx.matOf([idx.IOx; idx.SOx; idx.HOx]) = 2;
for e = 1:nE
    idx.matOf(idx.q{e}) = topo.mat(e);
end
idx.ironMask = (idx.matOf == 1);       % 铁（含在途铁），用于荷电状态
idx.pipeMask = false(idx.n, 1);
idx.pipeMask(idx.nInv + 1:idx.V - 1) = true;
idx.invList = (1:idx.nInv)';
end
