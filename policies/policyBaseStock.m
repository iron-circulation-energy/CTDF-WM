function w = policyBaseStock(ctx, lib)
%POLICYBASESTOCK 临界循环质量对应的基准库存策略在完整环境中的实现：
%   电厂侧自由铁目标 F* = δ^D·D_max（按容量份额分配），还原站侧自由锈目标 O* = δ^U·U_max，
%   正常期按通量补货（omega = kRes），不启用掺氨。参数可超出策略库取值范围，嵌入按范围截断。
%   流体模型中的同一策略见 fluidLoopSim。

st = ctx.stats;
nP = ctx.topo.nP;
nR = ctx.topo.nR;
kRes = st.deltaD * st.Dmax / max(st.deltaDbar, 1e-9);
kOx = st.deltaU * st.Umax / max(st.deltaUbar, 1e-9);
w.id = zeros(nP + nR + 1, 1);
w.kRes = kRes * ones(nP, 1);
w.band = ones(nP, 1);
w.thNH3 = zeros(nP, 1);
w.kapRho = ones(nR, 1);
w.kOx = kOx * ones(nR, 1);
w.omega = kRes;
w.psi = 1;
w.hubDays = 1;
w.fwd = 0;
w.emb = policyEmbedding(w, lib.ranges);
w.name = 'baseStock';
end
