function o = storageWindowLP(w, P, sp, p, opt)
%STORAGEWINDOWLP 替代方案逐小时调度线性规划（与 baselines/storageDispatchLP 相同的模型），另可给定初始储能量、
% 窗口末储能量价值与执行段，供滚动有限预见调度 storageDispatchRolling 使用；不给 opt 时与 storageDispatchLP 结果相同。
% opt（可选，滚动有限预见调度 storageDispatchRolling 用）：
%   e0         初始储能量（MWh，缺省 0.5·E_cap）
%   termValue  窗口末储能量的单位价值（元/MWh 储能量）；给出时以 −termValue·e_N 进入目标、不设末端约束，
%              缺省为空，即末端约束 e_N ≥ e_0（原完全预见口径）
%   commitH    只统计前 commitH 小时（执行段）的电量与成本，并返回该时刻的储能量 eCommit（缺省全部小时）
% 变量顺序：ch、dis、e、bk、cur、shed、ovg，各 Nh 个。
RE = w.RE(:);
D = w.D(:);
Nh = numel(RE);
iC = (1:Nh)';
iD = Nh + iC;
iE = 2 * Nh + iC;
iB = 3 * Nh + iC;
iU = 4 * Nh + iC;
iS = 5 * Nh + iC;
iO = 6 * Nh + iC;
nv = 7 * Nh;
if nargin < 5 || isempty(opt)
    opt = struct();
end
Ecap = P * sp.hours / sp.etaDischarge;
e0 = 0.5 * Ecap;
if isfield(opt, 'e0') && ~isempty(opt.e0)
    e0 = min(max(opt.e0, 0), Ecap);
end
termValue = [];
if isfield(opt, 'termValue')
    termValue = opt.termValue;
end
cH = Nh;
if isfield(opt, 'commitH') && ~isempty(opt.commitH)
    cH = min(Nh, opt.commitH);
end
% 功率平衡
Ab = sparse([iC; iC; iC; iC; iC; iC], [iD; iC; iB; iU; iS; iO], ...
    [ones(Nh, 1); -ones(Nh, 1); ones(Nh, 1); -ones(Nh, 1); ones(Nh, 1); -ones(Nh, 1)], Nh, nv);
bb = D - RE;
% 储能动态：e_t − e_{t−1} − η_c·ch_t + dis_t/η_d = 0（t = 1 时右端为 e_0）
rowsE = [iC; iC(2:end); iC; iC];
colsE = [iE; iE(1:end - 1); iC; iD];
valsE = [ones(Nh, 1); -ones(Nh - 1, 1); -sp.etaCharge * ones(Nh, 1); ones(Nh, 1) / sp.etaDischarge];
As = sparse(rowsE, colsE, valsE, Nh, nv);
bs = zeros(Nh, 1);
bs(1) = e0;
cBk = p.backup.fuelCost + w.carbon * p.backup.ef;
f = zeros(nv, 1);
f(iB) = cBk;
f(iU) = p.cost.piCur;
f(iS) = p.cost.piShed;
f(iO) = p.cost.piShed;
f([iC; iD]) = 0.01;                           % 微小充放电成本，避免同时充放（不计入运行成本）
lb = zeros(nv, 1);
ub = inf(nv, 1);
ub([iC; iD]) = P;
ub(iE) = Ecap;
if isempty(termValue)
    lb(iE(end)) = min(e0, Ecap);
else
    f(iE(end)) = f(iE(end)) - termValue;
end
ub(iB) = p.backup.pmax;
ub(iU) = RE;
Ain = sparse(0, nv);
bin = zeros(0, 1);
Aeq = [Ab; As];
beq = [bb; bs];
% 运行约束（opt.real 或 sp.real.on）：与改造情景的机组与物料约束对等。氢燃机与电解槽以在线容量 u、v 表示
% （线性化机组组合），出力不低于最小负荷比例，燃机开机计启动成本；盐穴注采速率受限（满库 injDays、wdDays 天）；
% 注气压缩耗能按比例折减充电效率。新增变量 u、v、su 追加在原变量之后。
R = struct('on', false);
if isfield(sp, 'real') && isstruct(sp.real)
    R = sp.real;
end
if isfield(opt, 'real') && ~isempty(opt.real)
    R.on = logical(opt.real);
end
if isfield(R, 'on') && R.on
    iUo = nv + iC; iVo = nv + Nh + iC; iSu = nv + 2 * Nh + iC;
    nv2 = nv + 3 * Nh;
    Ain = [Ain, sparse(0, 3 * Nh)];
    Aeq = [Aeq, sparse(size(Aeq, 1), 3 * Nh)];
    % 压缩耗能：充电效率 η_c(1 − compLoss)
    Aeq(Nh + iC, iC) = -sp.etaCharge * (1 - R.compLoss) * speye(Nh);
    f = [f; zeros(Nh, 1); zeros(Nh, 1); R.startCost * ones(Nh, 1)];
    lb = [lb; zeros(3 * Nh, 1)];
    ub = [ub; P * ones(Nh, 1); P * ones(Nh, 1); inf(Nh, 1)];
    I = speye(Nh);
    Z = sparse(Nh, nv2);
    % dis ≤ u，turbMin·u ≤ dis；ch ≤ v，elMin·v ≤ ch
    A1 = Z; A1(:, iD) = I; A1(:, iUo) = -I;
    A2 = Z; A2(:, iD) = -I; A2(:, iUo) = R.turbMin * I;
    A3 = Z; A3(:, iC) = I; A3(:, iVo) = -I;
    A4 = Z; A4(:, iC) = -I; A4(:, iVo) = R.elMin * I;
    % 启动：su_t ≥ u_t − u_{t−1}（t = 1 时以 0 为初值）
    Dm = I - spdiags(ones(Nh, 1), -1, Nh, Nh);
    A5 = Z; A5(:, iUo) = Dm; A5(:, iSu) = -I;
    % 盐穴采气与注气速率：dis/η_d ≤ E_cap/(24·wdDays)，η_c·ch ≤ E_cap/(24·injDays)
    ub(iD) = min(ub(iD), sp.etaDischarge * Ecap / (24 * R.wdDays));
    ub(iC) = min(ub(iC), Ecap / (24 * R.injDays) / max(sp.etaCharge, eps));
    u0 = 0;
    if isfield(opt, 'u0') && ~isempty(opt.u0), u0 = opt.u0; end
    b5 = zeros(Nh, 1);
    b5(1) = u0;
    Ain = [Ain; A1; A2; A3; A4; A5];
    bin = [bin; zeros(4 * Nh, 1); b5];
    nv = nv2;
end
prob = struct('f', f, 'Aineq', Ain, 'bineq', bin, 'Aeq', Aeq, 'beq', beq, 'lb', lb, 'ub', ub);
[x, ~, ef, info] = solveLP(prob, p.inner.solver);
if ef ~= 1
    error('retirementCounterfactual:solve', '退役情景调度求解失败（%s）。', string(info.status));
end
h = (1:cH)';
o.eue = sum(x(iS(h)));
o.op = cBk * sum(x(iB(h))) + p.cost.piCur * sum(x(iU(h))) + p.cost.piShed * (sum(x(iS(h))) + sum(x(iO(h))));
if isfield(R, 'on') && R.on
    o.op = o.op + R.startCost * sum(x(iSu(h)));      % 启动成本计入运行成本
end
o.cur = sum(x(iU(h)));
o.RE = sum(RE(h));
o.eCommit = x(iE(cH));
if isfield(R, 'on') && R.on
    o.uCommit = x(iUo(cH));
end
o.cBk = cBk;
end

