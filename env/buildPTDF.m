function grid = buildPTDF(p, topo)
%BUILDPTDF 区域映射与直流潮流功率转移分布因子（p.grid.useDCPF 为真时启用，默认单区域）。
%   区域线路 [起点, 终点, x, Fmax]；关联矩阵 A（Lz×Z），B = Aᵀ·diag(1/x)·A，
%   PTDF(:, 非平衡节点) = diag(1/x)·A(:, 非平衡节点)·B(非平衡, 非平衡)^(−1)，平衡节点列为零。
%   电厂、还原站按 p.net.nodes 第三列（区域名）映射到 p.grid.zones。

g = struct();
if ~p.grid.useDCPF
    g.Z = 1;
    g.plantZone = ones(topo.nP, 1);
    g.stationZone = ones(topo.nR, 1);
    g.reShare = 1;
    g.loadShare = 1;
    g.bkShare = 1;
    g.PTDF = zeros(0, 1);
    g.Fmax = zeros(0, 1);
    grid = g;
    return;
end
zones = p.grid.zones;
Z = numel(zones);
g.Z = Z;
g.plantZone = zeros(topo.nP, 1);
for i = 1:topo.nP
    z = find(strcmp(zones, topo.nodeRegion{topo.P(i)}));
    if isempty(z)
        error('buildPTDF:zone', '电厂 %s 的区域 %s 不在 p.grid.zones 中。', topo.nodeNames{topo.P(i)}, topo.nodeRegion{topo.P(i)});
    end
    g.plantZone(i) = z;
end
g.stationZone = zeros(topo.nR, 1);
for j = 1:topo.nR
    z = find(strcmp(zones, topo.nodeRegion{topo.R(j)}));
    if isempty(z)
        error('buildPTDF:zone', '还原站 %s 的区域 %s 不在 p.grid.zones 中。', topo.nodeNames{topo.R(j)}, topo.nodeRegion{topo.R(j)});
    end
    g.stationZone(j) = z;
end
g.reShare = p.grid.reShare(:) / sum(p.grid.reShare);
g.loadShare = p.grid.loadShare(:) / sum(p.grid.loadShare);
g.bkShare = p.grid.backupShare(:) / sum(p.grid.backupShare);
if numel(g.reShare) ~= Z || numel(g.loadShare) ~= Z || numel(g.bkShare) ~= Z
    error('buildPTDF:share', '区域份额向量长度须等于区域数。');
end
Lz = size(p.grid.lines, 1);
A = zeros(Lz, Z);
for l = 1:Lz
    A(l, p.grid.lines(l, 1)) = 1;
    A(l, p.grid.lines(l, 2)) = -1;
end
bf = diag(1 ./ p.grid.lines(:, 3));
Bbus = A' * bf * A;
ns = setdiff(1:Z, p.grid.slack);
PT = zeros(Lz, Z);
if ~isempty(ns) && Lz > 0
    PT(:, ns) = (bf * A(:, ns)) / Bbus(ns, ns);
end
g.PTDF = PT;
g.Fmax = p.grid.lines(:, 4);
grid = g;
end
