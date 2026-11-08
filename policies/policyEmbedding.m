function emb = policyEmbedding(w, rg)
%POLICYEMBEDDING 联合策略嵌入：各参数按取值范围归一化到 [0,1]（截断）后拼接为列向量。

nz = @(v, r) min(max((v(:) - r(1)) / (r(2) - r(1)), 0), 1);
plantPart = [nz(w.kRes, rg.kRes), nz(w.band, rg.band), nz(w.thNH3, rg.thNH3)]';
stationPart = [nz(w.kapRho, rg.kapRho), nz(w.kOx, rg.kOx)]';
logPart = [nz(w.omega, rg.omega); nz(w.psi, rg.psi); nz(w.hubDays, rg.hubDays); nz(w.fwd, rg.fwd)];
emb = [plantPart(:); stationPart(:); logPart];
end
