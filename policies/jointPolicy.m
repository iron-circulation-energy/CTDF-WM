function w = jointPolicy(lib, id)
%JOINTPOLICY 由联合策略编号 id（[电厂(nP); 还原站(nR); 物流(1)]）组装参数与策略嵌入。
%   嵌入：各参数按 lib.ranges 归一化到 [0,1] 后拼接（电厂 3·nP、还原站 2·nR、物流 4）。

id = id(:);
nP = lib.nP;
nR = lib.nR;
ip = id(1:nP);
ir = id(nP + (1:nR));
il = id(end);
rg = lib.ranges;
w.id = id;
w.kRes = lib.plant.kRes(ip);
w.band = lib.plant.band(ip);
w.thNH3 = lib.plant.thNH3(ip);
w.kapRho = lib.station.kapRho(ir);
w.kOx = lib.station.kOx(ir);
w.omega = lib.logistics.omega(il);
w.psi = lib.logistics.psi(il);
w.hubDays = lib.logistics.hubDays(il);
w.fwd = lib.logistics.fwd(il);
w.emb = policyEmbedding(w, rg);
end
