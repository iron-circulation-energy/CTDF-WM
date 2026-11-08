function res = innerDispatchLP(T, day, p)
%INNERDISPATCHLP 内层 24 小时线性规划（—(11)）：给定外层动作求小时级调度。
%   目标：Σ_t [Σ_i c^op_i·p_{i,t} + c^bk·p^bk_t + π^cur·P^cur_t + π^shed·(P^shed_t + P^ovg_t)
%                       − ε_red·Σ_j p^red_{j,t}] + Σ_i c^NH3·E^NH3_i，
%         其中 c^bk = 燃料价 + 碳价·排放因子，c^NH3 = nh3Base + nh3PerH2·氢价；ε_red 为还原优先系数
%         （调度规则，使富余电量优先进入还原而非弃电，不计入真实成本）。
%   约束（—(11)）：功率平衡；出力上下限 o_i·p̲_i ≤ p_{i,t} ≤ o_i·p̄_i；爬坡（首小时与前一日衔接，
%         停机时放松）；燃铁能量上限 Σ_t p_{i,t} − E^NH3_i ≤ η_i·h_Fe·b̄_i；掺氨电量 0 ≤ E^NH3_i ≤ β_i·Σ_t p_{i,t}
%         （两种燃料共用汽轮机效率，以实际发电量限制输入能量占比）；
%         还原功率与能量上限；P^cur_t ≤ P^RE_t；备用容量上限；启用直流潮流时加入区域线路潮流约束。
%
%   day 字段：RE、D（24×1，MW）、o、bcap（t）、beta、Ech（MWh）、redAvail、pLast、etaEff、carbon、h2。
%   输出 res：p（nP×24）、red（nR×24）、eNH3（nP×1）、bk、cur、shed、ovg（1×24，系统合计）、
%            Jop（真实运行成本，元）、balRes（功率平衡残差）、time、solver。

nP = T.nP;
nR = T.nR;
Z = T.Z;
H = T.H;
g = T.grid;
RE = day.RE(:)';
Dm = day.D(:)';
REz = g.reShare(:) * RE;        % Z×24
Dz = g.loadShare(:) * Dm;
o = logical(day.o(:));

cNH3 = p.cost.nh3Base + p.cost.nh3PerH2 * day.h2;
cBk = p.backup.fuelCost + day.carbon * p.backup.ef;
f = zeros(T.nv, 1);
f(T.iP(:)) = repmat(p.plant.cop(:), H, 1);
f(T.iR(:)) = -p.cost.redIncentive;
f(T.iN) = cNH3;
f(T.iB(:)) = cBk;
f(T.iC(:)) = p.cost.piCur;
f(T.iS(:)) = p.cost.piShed;
f(T.iO(:)) = p.cost.piShed;

Aineq = T.Aineq;
% beta limits ammonia's share of actual daily thermal/electric output. With
% the shared turbine efficiency this is linear in the two energy variables.
for i = 1:nP
    Aineq(T.rowNH3(i), T.iP(i, :)) = -day.beta(i);
end
b = T.bBase;
for i = 1:nP
    R = p.plant.ramp(i);
    if o(i)
        b(T.rowT1Up(i)) = max(R, p.plant.pmin(i)) + day.pLast(i);
        if day.pLast(i) > 0
            b(T.rowT1Dn(i)) = R - day.pLast(i);
        else
            b(T.rowT1Dn(i)) = T.bigM;
        end
    else
        b(T.rowT1Up(i)) = T.bigM;
        b(T.rowT1Dn(i)) = T.bigM;
    end
    b(T.rowCap(i)) = day.etaEff(i) * p.iron.hFe * day.bcap(i);
end
for j = 1:nR
    b(T.rowRed(j)) = day.Ech(j);
end
if Z > 1 && ~isempty(g.PTDF)
    netConst = g.PTDF * (REz - Dz);             % Lz×24
    for l = 1:size(g.PTDF, 1)
        b(T.rowFlowUp(l, :)) = g.Fmax(l) - netConst(l, :);
        b(T.rowFlowDn(l, :)) = g.Fmax(l) + netConst(l, :);
    end
end
beq = (Dm - RE)';
if isfield(day,'roomSFe')
    % Reduction and externally replaced capture losses share station iron bins.
    Cstore = sparse(nR,T.nv);
    lossPerMWh = p.plant.loss(:)./(day.etaEff(:)*p.iron.hFe);
    for j = 1:nR
        Cstore(j,T.iR(j,:)) = 1/day.eRedEff(j);
        for i = 1:nP
            Cstore(j,T.iP(i,:)) = day.shareR(j)*lossPerMWh(i);
            Cstore(j,T.iN(i)) = -day.shareR(j)*lossPerMWh(i);
        end
    end
    Aineq = [Aineq;Cstore];
    b = [b;day.roomSFe(:)];
end

lb = zeros(T.nv, 1);
ub = inf(T.nv, 1);
for i = 1:nP
    lb(T.iP(i, :)) = o(i) * p.plant.pmin(i);
    ub(T.iP(i, :)) = o(i) * p.plant.pmax(i);
    ub(T.iN(i)) = day.beta(i) * p.plant.pmax(i) * 24;
end
for j = 1:nR
    ub(T.iR(j, :)) = p.station.pRedMax(j) * day.redAvail(j);
end
for z = 1:Z
    ub(T.iB(z, :)) = p.backup.pmax * g.bkShare(z);
    ub(T.iC(z, :)) = REz(z, :);
end

prob = struct('f', f, 'Aineq', Aineq, 'bineq', b, 'Aeq', T.Aeq, 'beq', beq, 'lb', lb, 'ub', ub);
[xs, ~, ef, info] = solveLP(prob, p.inner.solver);
if ef ~= 1
    error('innerDispatchLP:infeasible', '内层调度求解失败（%s）：o = %s，bcap = %s。', ...
        string(info.status), mat2str(o'), mat2str(day.bcap(:)', 4));
end
xs = min(max(xs, lb), ub);                     % 消除求解器容差导致的越界
res.p = reshape(xs(T.iP(:)), nP, H);
res.red = reshape(xs(T.iR(:)), nR, H);
res.eNH3 = xs(T.iN(:));
res.bk = sum(reshape(xs(T.iB(:)), Z, H), 1);
res.cur = sum(reshape(xs(T.iC(:)), Z, H), 1);
res.shed = sum(reshape(xs(T.iS(:)), Z, H), 1);
res.ovg = sum(reshape(xs(T.iO(:)), Z, H), 1);
res.Jop = sum(p.plant.cop(:) .* sum(res.p, 2)) + cNH3 * sum(res.eNH3) + cBk * sum(res.bk);
bal = sum(res.p, 1) - sum(res.red, 1) + res.bk - res.cur + res.shed - res.ovg - (Dm - RE);
res.balRes = max(abs(bal));
res.time = info.time;
res.solver = info.solver;
end
