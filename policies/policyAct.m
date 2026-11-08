function a = policyAct(obs, w, ctx)
%POLICYACT 参数化基准库存型联合策略 π_w。只使用状态向量中包含的信息
%   （物料、品质、上一日出力、当日派生量与 3 日/H 日预测和、当日容量），因此 π_w(s) 是状态的函数，
%   世界模型可由 (s, w) 学习其后果。
%
%   电厂：位置 pos_i = I^Fe_i + 前 H 格在途 − b̂ 的 H 日和（即裕度 + 安全库存）；
%         储备目标 T_i = kRes_i·δ̄^D_i + I̲_i；替代意愿 λ_i = clip((pos_i − T_i)/(band_i·δ̄^D_i), 0, 1)；
%         按峰值缺口做最小出力覆盖的机组组合，λ ≥ 0.5 且可替代电量足够时追加开机；
%         当日能量目标 E_i = Emin_i + must_i + λ_i·(may_i − must_i)（注水分配），
%         b̄_i = min(可用铁, (1 + slack)·E_i /(η_i·h_Fe))；pos_i < thNH3_i·T_i 时启用掺氨。
%   还原站：计划还原 = kapRho_j·ρ̄_j·可用率（实际还原量由内层调度按富余电量决定）。
%   物流：电厂补货目标 S_i = omega·δ̄^D_i + I̲_i + max(r_i, Φ̄_i)·(τ^Fe_i + 1) + fwd·b̂^H_i（不超过料仓），
%         b̂^H_i = 份额_i·E^H/(η_i·h_Fe) 为未来 H 日必需燃铁量预测（前瞻补货：在预报的低风光期之前把铁运到电厂）；
%         按覆盖率从低到高分配上游可用铁；枢纽按 hubDays 周转并补足下游缺口；
%         电厂与枢纽按回运比例 psi 返锈，枢纽锈按还原站锈缺口（kOx_j·δ̄^U_j + S̲_j）分配，均不超过目的地剩余料仓。

p = ctx.p;
topo = ctx.topo;
idx = ctx.idx;
st = ctx.stats;
H = ctx.H;
L = ctx.L;
nP = topo.nP;
nR = topo.nR;
nE = topo.nE;
hFe = p.iron.hFe;
x = obs.x;
eta = obs.etaEff;
eRed = obs.eRedEff;
EH = obs.xi(L.xi.EH - L.n);
pmax = p.plant.pmax(:);

% ---------------- 电厂 ----------------
arr = zeros(nP, 1);
posPipe = zeros(nP, 1);
inPipeAll = zeros(nP, 1);
for i = 1:nP
    g = topo.P(i);
    for e = ctx.inFe{g}
        arr(i) = arr(i) + x(idx.qFirst(e));
        posPipe(i) = posPipe(i) + sum(x(idx.q{e}(1:min(H, topo.tau(e)))));
        inPipeAll(i) = inPipeAll(i) + sum(x(idx.q{e}));
    end
end
av = x(idx.IFe) + arr;
dDi = max(st.deltaDbarP(:), 1e-6);
pos = x(idx.IFe) + posPipe - ctx.shareP .* EH ./ (eta * hFe);
target = w.kRes(:) .* dDi + ctx.safeFe;
lam = min(max((pos - target) ./ max(w.band(:) .* dDi, 1e-9), 0), 1);
nh3ok = pos < w.thNH3(:) .* target;
Emin = plantMinEnergy(p, obs.pLast);
eAv = eta * hFe .* av;
canRun = eAv >= (1 - nh3ok .* p.plant.betaMax(:)) .* Emin;
if obs.d0.peakMust > 0
    o = minCover(obs.d0.peakMust * p.policy.commitMargin, pmax, p.plant.pmin, canRun, p.policy.minCoverEnum);
else
    o = false(nP, 1);
end
capE = min(max(eAv - Emin, 0), pmax * 24);
mayAll = waterfill(obs.d0.may, capE, pmax);
for i = 1:nP
    if ~o(i) && canRun(i) && lam(i) >= 0.5 && mayAll(i) >= 0.5 * Emin(i)
        o(i) = true;
    end
end
capEo = capE .* o;
mustA = waterfill(obs.d0.must, capEo, pmax);
mayA = waterfill(obs.d0.may, capEo, pmax);
E = o .* (Emin + mustA + lam .* (mayA - mustA));
bcap = o .* min(av, E * (1 + p.policy.burnSlack) ./ (eta * hFe));
beta = (o & nh3ok) .* p.plant.betaMax(:);

% ---------------- 还原站 ----------------
rho = w.kapRho(:) .* p.station.rhoMax(:) .* obs.rhoAvail(:);

% ---------------- 物流 ----------------
f = zeros(nE, 1);
used = zeros(nE, 1);
Fcap = obs.Fcap(:);
arrOx = zeros(nR, 1);
inPipeOx = zeros(nR, 1);
for j = 1:nR
    for e = ctx.inOx{topo.R(j)}
        arrOx(j) = arrOx(j) + x(idx.qFirst(e));
        inPipeOx(j) = inPipeOx(j) + sum(x(idx.q{e}));
    end
end
prodR = min([rho, x(idx.SOx) + arrOx, obs.d0.absorb * ctx.shareR ./ eRed], [], 2);
availNode = zeros(topo.nNodes, 1);
for j = 1:nR
    availNode(topo.R(j)) = x(idx.SFe(j)) + prodR(j);
end
for h = 1:topo.nH
    g = topo.H(h);
    v = x(idx.HFe(h));
    for e = ctx.inFe{g}
        v = v + x(idx.qFirst(e));
    end
    availNode(g) = v;
end
rH = ctx.shareP .* EH ./ (H * eta * hFe);
flowRef = max(rH, st.PhiP(:));
fwd = 0;
if isfield(w, 'fwd') && ~isempty(w.fwd)
    fwd = w.fwd;
end
S = min(w.omega * dDi + ctx.safeFe + flowRef .* (ctx.Tl.tauFe + 1) + fwd * ctx.shareP .* EH ./ (eta * hFe), p.plant.capFe(:));
IP = x(idx.IFe) + inPipeAll - E ./ (eta * hFe);
need = max(S - IP, 0);
[~, order] = sort(IP ./ max(S, 1e-9), 'ascend');
for r = 1:nP
    ii = order(r);
    g = topo.P(ii);
    lines = ctx.inFe{g};
    [~, ordL] = sort(topo.tau(lines), 'ascend');
    for e = lines(ordL)
        src = topo.from(e);
        qty = min([need(ii), availNode(src), Fcap(e) - used(e), freeCapacity(x,g,1,ctx,f)]);
        if qty > 0
            f(e) = f(e) + qty;
            used(e) = used(e) + qty;
            availNode(src) = availNode(src) - qty;
            need(ii) = need(ii) - qty;
        end
    end
end
% 枢纽补货
for h = 1:topo.nH
    g = topo.H(h);
    served = [];
    for e = ctx.outFe{g}
        if strcmp(topo.nodeType{topo.to(e)}, 'P')
            served = [served, find(topo.P == topo.to(e))]; %#ok<AGROW>
        end
    end
    tgt = w.hubDays * sum(flowRef(served)) + sum(need(served));
    IPh = x(idx.HFe(h));
    for e = ctx.inFe{g}
        IPh = IPh + sum(x(idx.q{e}));
    end
    for e = ctx.outFe{g}
        IPh = IPh - f(e);
    end
    nh = max(tgt - IPh, 0);
    lines = ctx.inFe{g};
    [~, ordL] = sort(availNode(topo.from(lines)), 'descend');
    for e = lines(ordL)
        src = topo.from(e);
        qty = min([nh, availNode(src), Fcap(e) - used(e), freeCapacity(x, g, 1, ctx, f)]);
        if qty > 0
            f(e) = f(e) + qty;
            used(e) = used(e) + qty;
            availNode(src) = availNode(src) - qty;
            nh = nh - qty;
        end
    end
end
% 电厂返锈
for i = 1:nP
    g = topo.P(i);
    amt = w.psi * (x(idx.IOx(i)) + (1 - p.plant.loss(i)) * bcap(i));
    lines = ctx.outOx{g};
    capl = Fcap(lines);
    if sum(capl) <= 0
        continue;
    end
    for m = 1:numel(lines)
        e = lines(m);
        qty = min([amt * capl(m) / sum(capl), Fcap(e) - used(e), freeCapacity(x, topo.to(e), 2, ctx, f)]);
        if qty > 0
            f(e) = f(e) + qty;
            used(e) = used(e) + qty;
        end
    end
end
% 枢纽转运锈
for h = 1:topo.nH
    g = topo.H(h);
    amt = x(idx.HOx(h));
    for e = ctx.inOx{g}
        amt = amt + x(idx.qFirst(e));
    end
    amt = w.psi * amt;
    lines = ctx.outOx{g};
    if isempty(lines)
        continue;
    end
    needs = zeros(numel(lines), 1);
    for m = 1:numel(lines)
        jj = find(topo.R == topo.to(lines(m)));
        tgtj = w.kOx(jj) * st.deltaUbarR(jj) + ctx.safeOx(jj);
        needs(m) = max(tgtj - (x(idx.SOx(jj)) + inPipeOx(jj)), 0) + 1e-6 * ctx.shareR(jj);
    end
    for m = 1:numel(lines)
        e = lines(m);
        qty = min([amt * needs(m) / sum(needs), Fcap(e) - used(e), freeCapacity(x, topo.to(e), 2, ctx, f)]);
        if qty > 0
            f(e) = f(e) + qty;
            used(e) = used(e) + qty;
        end
    end
end

a.o = o;
a.bcap = bcap;
a.beta = beta;
a.rho = rho;
a.f = f;
end
