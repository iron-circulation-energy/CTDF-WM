function E = embeddingsFromIds(lib, ids)
%EMBEDDINGSFROMIDS 批量计算联合策略嵌入（与 jointPolicy/policyEmbedding 一致，向量化）。
%   ids：(nP+nR+1)×M 联合策略编号；E：dimEmb×M。

rg = lib.ranges;
nz = @(v, r) min(max((v - r(1)) / (r(2) - r(1)), 0), 1);
plantOpt = [nz(lib.plant.kRes', rg.kRes); nz(lib.plant.band', rg.band); nz(lib.plant.thNH3', rg.thNH3)];  % 3×nOpt
statOpt = [nz(lib.station.kapRho', rg.kapRho); nz(lib.station.kOx', rg.kOx)];                             % 2×nOpt
logOpt = [nz(lib.logistics.omega', rg.omega); nz(lib.logistics.psi', rg.psi); nz(lib.logistics.hubDays', rg.hubDays); ...
    nz(lib.logistics.fwd', rg.fwd)];
nP = lib.nP;
nR = lib.nR;
M = size(ids, 2);
E = zeros(lib.dimEmb, M);
r = 0;
for i = 1:nP
    E(r + (1:3), :) = plantOpt(:, ids(i, :));
    r = r + 3;
end
for j = 1:nR
    E(r + (1:2), :) = statOpt(:, ids(nP + j, :));
    r = r + 2;
end
E(r + (1:4), :) = logOpt(:, ids(end, :));
end
