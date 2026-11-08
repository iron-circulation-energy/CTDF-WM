function [a, info] = stochasticMPC(obs, ctx, mpc, rs)
%STOCHASTICMPC M2 随机模型预测控制：同一线性物料模型—(7) 上的两阶段场景型滚动优化。
%   时域 H_MPC = mpc.Hm 天（默认 2·T_loop），电力侧按每日 T4 个时段聚合（时段平均功率，Δ = 24/T4 h）。
%   场景：第 1 天为当日实际（与其他方法相同），第 2 至 Hf+1 天取共用预测器的日电量预测（信息公平），
%   其后取训练年份中“气象状态相同、日序相差不超过 doyWindow”的起始日之后的实际日电量（S 个场景，按 rs 抽样）。
%   非预期约束：第 1 天的全部决策在各场景间共用同一组变量（等价于首阶段非预期约束）。
%   每个日块的约束：
%     物料动态 x_{d+1} = M_x·x_d + M_b·b_d + M_ρ·ρ_d + M_f·f_d，x ≥ 0（隐含燃铁、还原、发运的库存可行性）；
%     能量耦合：η_i·h_Fe·b_i + E^NH3_i = Δ·Σ_τ p_{i,τ}，e^red_j·ρ_j = Δ·Σ_τ p^red_{j,τ}；
%     功率平衡（时段平均）：Σ_i p_{i,τ} − Σ_j p^red_{j,τ} + p^bk_τ − P^cur_τ + P^shed_τ − P^ovg_τ = D_τ − P^RE_τ；
%     上下限：p ≤ p̄、p^red ≤ p̄^red·可用率、ρ ≤ ρ̄·可用率、f ≤ F̄（第 1 天用当日容量，其后取额定值）、
%             E^NH3 ≤ β̄·Δ·Σp、p^bk ≤ 备用容量、P^cur ≤ P^RE；库存+全部入站在途预留≤仓容，
%             转换后及按固定线路顺序每次发运后都须满足，与执行环境一致。
%   目标： 的期望（第 1 天权重 1，场景日权重 γ^(d−1)/S）：运行、掺氨、备用、弃电与失负荷惩罚、物流、补铁、
%         （仓储成本 c^hd·1ᵀx = c^hd·c 为常数，不进入优化）；时域末端的物料按两种方式之一计价：
%         mpc.terminalMode = 'shortfall'：终端铁量低于 terminalFrac × 初始铁量的部分按 v_Fe 计罚；
%         mpc.terminalMode = 'value'（储量价值，与水电的水价值同理）：各场景末日的全部铁按 m·v_Fe、全部锈按
%         oxValueFrac·m·v_Fe 计入收益（折扣 γ^(H−1)），m = ironValueMult 在验证年上调参；
%         v_Fe = mean(η)·h_Fe·(备用燃料价 + 碳价·排放因子)。只按备用燃料计价时，末端铁的价值不足以抵偿锈的回运费用，
%         优化会放弃回运与还原，循环逐渐枯竭；储量价值使回运与还原在时域内即有收益。
%         mpc.terminalNet 为真时，各分量的终端价值扣除其送达使用点（铁至电厂、锈至还原站）的最低物流成本（mpcSetup）。
%   线性松弛：日开机状态与最小出力、小时爬坡不进入 MPC（整数约束），首日计划按 commitFrac 规则取整后交由
%   环境内层调度执行。求解器：p.mpc.solver（Gurobi 直接接口、YALMIP + Gurobi 或 linprog），LP 的最优间隙记为 0。
%   输出 a（o、bcap、beta、rho、f）与 info（time、buildTime、status、obj、nVar、nEq、nIneq、gap、Hm、S）。

t0 = tic;
p = ctx.p;
topo = ctx.topo;
idx = ctx.idx;
nP = topo.nP;
nR = topo.nR;
nE = topo.nE;
n = idx.n;
nInv = idx.nInv;
T4 = mpc.T4;
Dt = 24 / T4;
S = mpc.S;
Hm = mpc.Hm;
lay = mpc.lay;
nb = lay.nb;
M = mpc.M;

% ---------------- 场景气象 ----------------
EW = zeros(S, Hm);
ES = zeros(S, Hm);
EL = zeros(S, Hm);
DY = zeros(S, Hm);
doy0 = obs.hidden.doy;
nFc = min(mpc.Hf + 1, Hm);
for d = 1:nFc
    EW(:, d) = obs.fc.EW(d);
    ES(:, d) = obs.fc.ES(d);
    EL(:, d) = obs.fc.EL(d);
    DY(:, d) = mod(doy0 - 1 + (d - 1), 365) + 1;
end
if Hm > nFc
    starts = pickAnalogs(mpc.bank, obs.hidden.reg, doy0, ctx.p.mpc.doyWindow, S, rs);
    for s = 1:S
        Yb = mpc.bank.Y{mpc.bank.year(starts(s))};
        t0b = mpc.bank.day(starts(s));
        for d = nFc + 1:Hm
            tt = t0b + d - 1;
            EW(s, d) = Yb.EW(tt);
            ES(s, d) = Yb.ES(tt);
            EL(s, d) = Yb.EL(tt);
            DY(s, d) = Yb.doy(tt);
        end
    end
end
[REh, Dh] = hourlyProfiles(EW(:)', ES(:)', EL(:)', DY(:)', p.weather);      % 24×(S·Hm)
REp = squeeze(mean(reshape(REh, Dt, T4, S * Hm), 1));                     % T4×(S·Hm)
Dp = squeeze(mean(reshape(Dh, Dt, T4, S * Hm), 1));
REp = reshape(REp, T4, S, Hm);
Dp = reshape(Dp, T4, S, Hm);

% ---------------- 日块列表 ----------------
NB = 1 + S * (Hm - 1);
blkS = zeros(NB, 1);
blkD = ones(NB, 1);
pred = zeros(NB, 1);
wgt = ones(NB, 1);
for s = 1:S
    for d = 2:Hm
        b = 1 + (s - 1) * (Hm - 1) + (d - 1);
        blkS(b) = s;
        blkD(b) = d;
        if d == 2
            pred(b) = 1;
        else
            pred(b) = b - 1;
        end
        wgt(b) = mpc.gamma ^ (d - 1) / S;
    end
end
lastBlk = 1 + (1:S)' * (Hm - 1);
nv = NB * nb + S;
off = (0:NB - 1)' * nb;

% ---------------- 单块模式（相对索引）----------------
eta = obs.etaEff(:);
eRed = obs.eRedEff(:);
hFe = p.iron.hFe;
[rb, cb, vb] = find(M.Mb);
[rr, cr, vr] = find(M.Mr);
[rf, cf, vf] = find(M.Mf);
[rx, cx, vx] = find(M.Mx);
% 自身部分
Ir = [(1:n)'; rb; rr; rf];
Jc = [lay.iX; lay.iB(cb); lay.iR(cr); lay.iF(cf)];
Vv = [ones(n, 1); -vb; -vr; -vf];
for i = 1:nP
    Ir = [Ir; n + i; n + i; (n + i) * ones(T4, 1)]; %#ok<AGROW>
    Jc = [Jc; lay.iB(i); lay.iN(i); lay.iP(i, :)']; %#ok<AGROW>
    Vv = [Vv; eta(i) * hFe; 1; -Dt * ones(T4, 1)]; %#ok<AGROW>
end
for j = 1:nR
    Ir = [Ir; n + nP + j; (n + nP + j) * ones(T4, 1)]; %#ok<AGROW>
    Jc = [Jc; lay.iR(j); lay.iRd(j, :)']; %#ok<AGROW>
    Vv = [Vv; eRed(j); -Dt * ones(T4, 1)]; %#ok<AGROW>
end
for tau = 1:T4
    r0 = n + nP + nR + tau;
    Ir = [Ir; r0 * ones(nP + nR + 4, 1)]; %#ok<AGROW>
    Jc = [Jc; lay.iP(:, tau); lay.iRd(:, tau); lay.iBk(tau); lay.iCu(tau); lay.iSh(tau); lay.iOg(tau)]; %#ok<AGROW>
    Vv = [Vv; ones(nP, 1); -ones(nR, 1); 1; -1; 1; -1]; %#ok<AGROW>
end
nSelf = numel(Ir);
% 前驱耦合部分（−M_x·x_pred）
nPred = numel(rx);

% ---------------- 组装等式约束 ----------------
nEqB = lay.nEqB;
hasPred = pred > 0;
nTrip = NB * nSelf + nnz(hasPred) * nPred;
I = zeros(nTrip, 1);
J = zeros(nTrip, 1);
V = zeros(nTrip, 1);
beq = zeros(NB * nEqB, 1);
ptr = 0;
x0 = obs.x(:);
for b = 1:NB
    rows = (b - 1) * nEqB;
    I(ptr + (1:nSelf)) = rows + Ir;
    J(ptr + (1:nSelf)) = off(b) + Jc;
    V(ptr + (1:nSelf)) = Vv;
    ptr = ptr + nSelf;
    if hasPred(b)
        I(ptr + (1:nPred)) = rows + rx;
        J(ptr + (1:nPred)) = off(pred(b)) + lay.iX(cx);
        V(ptr + (1:nPred)) = -vx;
        ptr = ptr + nPred;
    else
        beq(rows + (1:n)) = M.Mx * x0;
    end
    s = max(blkS(b), 1);
    d = blkD(b);
    beq(rows + n + nP + nR + (1:T4)) = Dp(:, s, d) - REp(:, s, d);
end
Aeq = sparse(I, J, V, NB * nEqB, nv);

% ---------------- 不等式：逐阶段硬仓容预留与终端铁量 ----------------
iron0 = sum(x0(ctx.ironMask));
ironCols = lay.iX(ctx.ironMask);
nIr = numel(ironCols);
[capacityBlock,capacityBound] = mpcCapacityBlock(ctx,mpc);
capacityA = [kron(speye(NB),capacityBlock), sparse(NB*size(capacityBlock,1),S)];
I2 = zeros(S * (nIr + 1), 1);
J2 = I2;
V2 = I2;
bineq = zeros(S, 1);
ptr = 0;
for s = 1:S
    r0 = s;
    I2(ptr + (1:nIr + 1)) = r0;
    J2(ptr + (1:nIr + 1)) = [off(lastBlk(s)) + ironCols; NB * nb + s];
    V2(ptr + (1:nIr + 1)) = -1;
    ptr = ptr + nIr + 1;
    bineq(r0) = -p.mpc.terminalFrac * iron0;
end
Aineq = [capacityA; sparse(I2(1:ptr), J2(1:ptr), V2(1:ptr), S, nv)];
bineq = [repmat(capacityBound,NB,1);bineq];
% Ammonia remains a bounded blend even when the LP runs at part load.
nh3Rows = zeros(NB*nP*(T4+1),1);
nh3Cols = nh3Rows;
nh3Vals = nh3Rows;
ptr = 0;
for b = 1:NB
    for i = 1:nP
        jj = ptr + (1:T4+1);
        nh3Rows(jj) = (b-1)*nP+i;
        nh3Cols(jj) = off(b) + [lay.iN(i); lay.iP(i,:)'];
        nh3Vals(jj) = [1; -p.plant.betaMax(i)*Dt*ones(T4,1)];
        ptr = ptr + T4+1;
    end
end
Aineq = [Aineq; sparse(nh3Rows,nh3Cols,nh3Vals,NB*nP,nv)];
bineq = [bineq; zeros(NB*nP,1)];

% ---------------- 目标与上下限 ----------------
cBk = p.backup.fuelCost + obs.hidden.carbon * p.backup.ef;
cNH3 = p.cost.nh3Base + p.cost.nh3PerH2 * obs.hidden.h2;
vFe = mean(eta) * hFe * cBk;
fBlk = zeros(nb, 1);
fBlk(lay.iP) = Dt * repmat(p.plant.cop(:), T4, 1);
fBlk(lay.iBk) = Dt * cBk;
fBlk(lay.iCu) = Dt * p.cost.piCur;
fBlk(lay.iSh) = Dt * p.cost.piShed;
fBlk(lay.iOg) = Dt * p.cost.piShed;
fBlk(lay.iN) = cNH3;
fBlk(lay.iF) = ctx.lineCostPerT;
fBlk(lay.iB) = p.cost.cMk * p.plant.loss(:);
fBlk(lay.iOv) = p.cost.overflowPenalty;
f = zeros(nv, 1);
lb = zeros(nv, 1);
ub = inf(nv, 1);
for b = 1:NB
    f(off(b) + (1:nb)) = wgt(b) * fBlk;
    s = max(blkS(b), 1);
    d = blkD(b);
    if d == 1
        avail = obs.rhoAvail(:);
        Fc = obs.Fcap(:);
    else
        avail = ones(nR, 1);
        Fc = topo.Fcap(:);
    end
    u = inf(nb, 1);
    u(lay.iR) = p.station.rhoMax(:) .* avail;
    u(lay.iF) = Fc;
    u(lay.iN) = p.plant.betaMax(:) .* p.plant.pmax(:) * 24;
    u(lay.iP) = repmat(p.plant.pmax(:), 1, T4);
    u(lay.iRd) = repmat(p.station.pRedMax(:) .* avail, 1, T4);
    u(lay.iBk) = p.backup.pmax;
    u(lay.iCu) = REp(:, s, d);
    ub(off(b) + (1:nb)) = u;
end
f(NB * nb + (1:S)) = vFe / S;
if strcmpi(getfOr(mpc, 'terminalMode', 'shortfall'), 'value')
    f(NB * nb + (1:S)) = 0;                                   % 不再使用终端缺口罚项
    vT = getfOr(mpc, 'ironValueMult', 1) * vFe;
    wT = mpc.gamma ^ (Hm - 1) / S;
    oxMask = (idx.matOf == 2);
    oxCols = lay.iX(oxMask);
    dFe = zeros(nIr, 1);
    dOx = zeros(nnz(oxMask), 1);
    if isfield(mpc, 'termDeduct') && getfOr(mpc, 'terminalNet', false)
        dFe = mpc.termDeduct(ctx.ironMask);
        dOx = mpc.termDeduct(oxMask);
    end
    vFeT = max(vT - dFe, 0);
    vOxT = max(getfOr(mpc, 'oxValueFrac', 0.5) * vT - dOx, 0);
    for s = 1:S
        f(off(lastBlk(s)) + ironCols) = f(off(lastBlk(s)) + ironCols) - wT * vFeT;
        f(off(lastBlk(s)) + oxCols) = f(off(lastBlk(s)) + oxCols) - wT * vOxT;
    end
end
buildTime = toc(t0);

% ---------------- 求解 ----------------
prob = struct('f', f, 'Aineq', Aineq, 'bineq', bineq, 'Aeq', Aeq, 'beq', beq, 'lb', lb, 'ub', ub);
[xs, fval, ef, sinfo] = solveLP(prob, mpc.solver);
if ef ~= 1
    error('stochasticMPC:solve', '随机 MPC 求解失败（%s）。', string(sinfo.status));
end
xs = min(max(xs, lb), ub);

% ---------------- 首日计划 → 环境动作 ----------------
b1 = xs(lay.iB);
r1 = xs(lay.iR);
f1 = xs(lay.iF);
n1 = xs(lay.iN);
P1 = reshape(xs(lay.iP), nP, T4);
E = Dt * sum(P1, 2);
Emin = plantMinEnergy(p, obs.pLast);
o = (E >= p.mpc.commitFrac * Emin) & (E > 1e-6);
arr = zeros(n, 1);
for e = 1:nE
    arr(idx.lineTgt(e)) = arr(idx.lineTgt(e)) + x0(idx.qFirst(e));
end
avFe = x0(idx.IFe) + arr(idx.IFe);
sl = p.mpc.burnSlack;
a.o = o;
a.bcap = o .* min(avFe, max(b1 * (1 + sl), Emin ./ (eta * hFe)));
% beta is the ammonia share of actual planned generation, including at part
% load; dividing by nameplate energy would shrink the executable allowance.
a.beta = o .* min(p.plant.betaMax(:), (n1 > 1e-6) .* n1 ./ max(E,1e-12) * (1 + sl));
a.rho = min(p.station.rhoMax(:) .* obs.rhoAvail(:), r1 * (1 + sl) + 1e-6);
a.f = f1;

info.time = sinfo.time;
info.buildTime = buildTime;
info.totalTime = toc(t0);
info.status = sinfo.status;
info.solver = sinfo.solver;
info.obj = fval;
info.nVar = nv;
info.nEq = size(Aeq, 1);
info.nIneq = size(Aineq, 1);
info.gap = 0;
info.Hm = Hm;
info.S = S;
info.firstPlan = struct('burn',b1,'red',r1,'f',f1,'x',xs(lay.iX));
info.capacityExcess = max([0;capacityA*xs-repmat(capacityBound,NB,1)]);
end

function starts = pickAnalogs(bank, reg, doy, win, S, rs)
% 按“气象状态相同 + 日序窗口”条件抽取场景起始日（场景只来自训练年份）
dd = abs(bank.doy - doy);
dd = min(dd, 365 - dd);
cand = find(bank.reg == reg & dd <= win);
if numel(cand) < S
    cand = find(dd <= win);
end
if isempty(cand)
    cand = 1:numel(bank.day);
end
if numel(cand) >= S
    starts = cand(randperm(rs, numel(cand), S));
else
    starts = cand(randi(rs, numel(cand), 1, S));
end
end

function v = getfOr(s, f, d)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = d;
end
end
