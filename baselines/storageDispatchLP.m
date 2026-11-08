function o = storageDispatchLP(w, P, sp, p)
%STORAGEDISPATCHLP Retirement service benchmark with hourly perfect foresight.
% Public kernel for direct timing of the annual LP. All physical/financial inputs are
% supplied by w, P, sp, p; this function does not size P or annualise investment.
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
Ecap = P * sp.hours / sp.etaDischarge;
e0 = 0.5 * Ecap;
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
lb(iE(end)) = min(e0, Ecap);
ub(iB) = p.backup.pmax;
ub(iU) = RE;
prob = struct('f', f, 'Aineq', sparse(0, nv), 'bineq', zeros(0, 1), 'Aeq', [Ab; As], 'beq', [bb; bs], ...
    'lb', lb, 'ub', ub);
[x, ~, ef, info] = solveLP(prob, p.inner.solver);
if ef ~= 1
    error('retirementCounterfactual:solve', '退役情景调度求解失败（%s）。', string(info.status));
end
o.eue = sum(x(iS));
o.op = cBk * sum(x(iB)) + p.cost.piCur * sum(x(iU)) + p.cost.piShed * (sum(x(iS)) + sum(x(iO)));
o.cur = sum(x(iU));
o.RE = sum(RE);
end

