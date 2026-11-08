function out = natPortfolio(svc, pin, n, capCoal, saltOK, dLocal, loopDays, techs)
%NATPORTFOLIO 省级长时储能组合优化（日尺度容量扩展线性规划）：多条路线共同满足同一条放电需求序列。
%   out = natPortfolio(svc, pin, n, capCoal, saltOK, dLocal, loopDays, techs)
%   svc       natStorage 的共同储能服务（de：Y×365 日放电需求；chAvailable：Y×365 可用富余电量；单位为平均负荷日）
%   pin       充电电价（元/kWh）
%   n         params_national()
%   capCoal   可改造煤电放电功率上限（以本省平均负荷为 1；铁与氨两条燃料路线共用）
%   saltOK    本省是否具备盐穴储氢条件
%   dLocal    省内铁路短驳里程（km）；loopDays 省内闭环周转时间（d）
%   techs     参与组合的路线子集（缺省 {'Fe','H2S','H2T','NH3'}；单一路线时即为该路线的最优规模）
%
%   决策变量（每条路线 r）：放电功率 P^dis_r、充电功率 P^ch_r、储能容量 E_r（可放出电量口径），
%   以及逐日放电 d_rt、充电 c_rt 与库存 s_rt（循环边界 s_r,0 = s_r,T）。
%     Σ_r d_rt = de_t，Σ_r c_rt ≤ ch_t，s_rt = s_r,t−1 + η_r c_rt − d_rt，0 ≤ s_rt ≤ E_r，d_rt ≤ P^dis_r，c_rt ≤ P^ch_r，
%     P^dis_Fe + P^dis_NH3 ≤ capCoal（两条燃料路线复用同一批煤电机组）；
%     n.nh3.blendMax = β < 1 时另加掺烧约束 (1 − β)·d_NH3,t ≤ β·d_Fe,t（氨只能与铁粉掺烧，见下）。
%   目标为年化总成本（元/年，每 MW 平均负荷）：
%     Σ_r [a^dis_r P^dis_r + a^ch_r P^ch_r + 24·a^E_r E_r + 24·(v^out_r Σ_t d_rt + v^in Σ_t c_rt)/Y]，
%   系数与 natCost 逐项一致（年金 + 运维；铁的在途库存、每循环损耗与铁路运费计入 v^out）。
%   单一路线评估（natCost）只能在各省之间“择一”，组合优化允许各路线按所长分担：铁的储能容量与放电功率廉价、
%   往返效率低，氢、氨效率较高而储能或放电功率较贵，二者在长时与高频两类需求上互补。
%   输出 out：cost（元/年/MW 平均负荷）、costPerMWh（元/MWh 放电量）、share（各路线放电量占比）、
%             Pdis、Pch、E（各路线规模）、techs、ok。

if nargin < 8 || isempty(techs)
    techs = {'Fe', 'H2S', 'H2T', 'NH3'};
end
if ~saltOK
    techs = setdiff(techs, {'H2S'}, 'stable');
end
if capCoal <= 0
    techs = setdiff(techs, {'Fe', 'NH3'}, 'stable');
end
out = struct('ok', false, 'cost', NaN, 'costPerMWh', NaN, 'techs', {techs}, 'share', [], 'Pdis', [], 'Pch', [], 'E', []);
if isempty(techs)
    return;
end
de = reshape(svc.de', [], 1);
if isfield(svc, 'chAvailable')
    ch = reshape(svc.chAvailable', [], 1);
else
    ch = reshape(svc.ch', [], 1);
end
T = numel(de);
Y = size(svc.de, 1);
R = numel(techs);
cf = @(r, life) capitalFactor(r, life);
f = n.fe;
co = zeros(R, 6);                                   % [aDis, aCh, aE（元/年/MWh_out）, vOut（元/MWh_out）, vIn（元/MWh_in）, η]
for k = 1:R
    switch techs{k}
        case 'Fe'
            kk = f.kappa / f.etaEl + f.eps / f.hFe;
            eOut = f.etaSt * f.hFe;
            perT = f.price * n.r + f.siloPerT * (cf(n.r, f.lifeSt) + n.om);          % 元/年/t 库存
            co(k, :) = [f.capRetro * 1e3 * (cf(n.r, f.lifeRetro) + n.om), ...
                (n.fe.capEl * (f.kappa / f.etaEl) / kk + f.capRed / kk) * 1e3 * (cf(n.r, f.lifeSt) + n.om), ...
                perT / eOut, ...
                (loopDays / 365 * perT + f.loss * f.price + (n.rail.base1 + n.rail.perKm * dLocal) * (1 + f.mOx)) / eOut, ...
                pin * 1e3, eOut / (f.hFe * kk)];
        case {'H2S', 'H2T'}
            h = n.h2;
            st = h.storeSalt;
            if strcmp(techs{k}, 'H2T')
                st = h.storeTank;
            end
            co(k, :) = [h.capGT * 1e3 * (cf(n.r, h.life) + n.om), h.capEl * 1e3 * (cf(n.r, h.life) + n.om), ...
                st * 1e3 / h.etaGT * (cf(n.r, h.lifeStore) + n.om), 0, pin * 1e3, h.etaEl * h.etaGT];
        case 'NH3'
            h = n.nh3;
            k3 = h.h2PerNH3 / n.fe.etaEl + h.elSyn;
            co(k, :) = [h.capRetro * 1e3 * (cf(n.r, n.fe.lifeRetro) + n.om), ...
                (n.fe.capEl * (h.h2PerNH3 / n.fe.etaEl) / k3 + h.capSyn / k3) * 1e3 * (cf(n.r, h.life) + n.om), ...
                h.store * 1e3 / h.etaSt * (cf(n.r, h.lifeStore) + n.om), 0, pin * 1e3, h.etaSt / k3];
        otherwise
            error('natPortfolio:tech', '未知路线 %s。', techs{k});
    end
end
% 变量排布：每条路线 [P^dis, P^ch, E, d(1:T), c(1:T), s(1:T)]
nv = 3 + 3 * T;
N = R * nv;
iP = @(k) (k - 1) * nv + 1;
iC = @(k) (k - 1) * nv + 2;
iE = @(k) (k - 1) * nv + 3;
iD = @(k) (k - 1) * nv + 3 + (1:T)';
iCh = @(k) (k - 1) * nv + 3 + T + (1:T)';
iS = @(k) (k - 1) * nv + 3 + 2 * T + (1:T)';
fobj = zeros(N, 1);
for k = 1:R
    fobj(iP(k)) = co(k, 1);
    fobj(iC(k)) = co(k, 2);
    fobj(iE(k)) = 24 * co(k, 3);
    fobj(iD(k)) = 24 * co(k, 4) / Y;
    fobj(iCh(k)) = 24 * co(k, 5) / Y;
end
tt = (1:T)';
% 等式：需求平衡（T 行）与各路线库存递推（R·T 行，循环边界）
Jeq = zeros(0, 1);
Veq = zeros(0, 1);
Ieq = zeros(0, 1);
for k = 1:R
    Ieq = [Ieq; tt]; Jeq = [Jeq; iD(k)]; Veq = [Veq; ones(T, 1)]; %#ok<AGROW>
end
beq = de;
for k = 1:R
    rows = T * k + tt;
    prev = iS(k);
    prev = prev([T, 1:T - 1]);
    Ieq = [Ieq; rows; rows; rows; rows]; %#ok<AGROW>
    Jeq = [Jeq; iS(k); prev; iCh(k); iD(k)]; %#ok<AGROW>
    Veq = [Veq; ones(T, 1); -ones(T, 1); -co(k, 6) * ones(T, 1); ones(T, 1)]; %#ok<AGROW>
    beq = [beq; zeros(T, 1)]; %#ok<AGROW>
end
Aeq = sparse(Ieq, Jeq, Veq, T * (R + 1), N);
% 不等式：充电不超过可用富余（T 行）；库存 ≤ E、放电 ≤ P^dis、充电 ≤ P^ch（各 R·T 行）；煤电共用（1 行）
Ii = zeros(0, 1); Ji = zeros(0, 1); Vi = zeros(0, 1);
for k = 1:R
    Ii = [Ii; tt]; Ji = [Ji; iCh(k)]; Vi = [Vi; ones(T, 1)]; %#ok<AGROW>
end
bi = ch;
r0 = T;
for k = 1:R
    for blk = 1:3
        rows = r0 + tt;
        switch blk
            case 1
                Ii = [Ii; rows; rows]; Ji = [Ji; iS(k); repmat(iE(k), T, 1)]; %#ok<AGROW>
            case 2
                Ii = [Ii; rows; rows]; Ji = [Ji; iD(k); repmat(iP(k), T, 1)]; %#ok<AGROW>
            case 3
                Ii = [Ii; rows; rows]; Ji = [Ji; iCh(k); repmat(iC(k), T, 1)]; %#ok<AGROW>
        end
        Vi = [Vi; ones(T, 1); -ones(T, 1)]; %#ok<AGROW>
        bi = [bi; zeros(T, 1)]; %#ok<AGROW>
        r0 = r0 + T;
    end
end
fuel = find(ismember(techs, {'Fe', 'NH3'}));
if ~isempty(fuel)
    r0 = r0 + 1;
    for k = fuel(:)'
        Ii = [Ii; r0]; Ji = [Ji; iP(k)]; Vi = [Vi; 1]; %#ok<AGROW>
    end
    bi = [bi; capCoal];
end
% 氨掺烧上限 β（n.nh3.blendMax < 1）：改造锅炉中氨只能承担燃料热量的 β，其余由同一机组的另一种零碳燃料（铁粉）承担，
% 即逐日 (1 − β)·d_NH3,t − β·d_Fe,t ≤ 0，功率 (1 − β)·P^dis_NH3 − β·P^dis_Fe ≤ 0；无铁路线时氨不能单独供电。
beta = 1;
if isfield(n.nh3, 'blendMax') && ~isempty(n.nh3.blendMax)
    beta = n.nh3.blendMax;
end
kN = find(strcmp(techs, 'NH3'));
kF = find(strcmp(techs, 'Fe'));
if beta < 1 && ~isempty(kN)
    rows = r0 + tt;
    Ii = [Ii; rows]; Ji = [Ji; iD(kN)]; Vi = [Vi; (1 - beta) * ones(T, 1)];
    r1 = r0 + T + 1;
    Ii = [Ii; r1]; Ji = [Ji; iP(kN)]; Vi = [Vi; 1 - beta];
    if ~isempty(kF)
        Ii = [Ii; rows]; Ji = [Ji; iD(kF)]; Vi = [Vi; -beta * ones(T, 1)];
        Ii = [Ii; r1]; Ji = [Ji; iP(kF)]; Vi = [Vi; -beta];
    end
    bi = [bi; zeros(T + 1, 1)];
    r0 = r1; %#ok<NASGU>
end
Ain = sparse(Ii, Ji, Vi, numel(bi), N);
prob = struct('f', fobj, 'Aineq', Ain, 'bineq', bi, 'Aeq', Aeq, 'beq', beq, 'lb', zeros(N, 1), 'ub', inf(N, 1));
[x, fval, ef] = solveLP(prob, 'auto');
if ef ~= 1 || isempty(x)
    return;
end
out.ok = true;
out.cost = fval;
Eann = 24 * sum(de) / Y;                            % MWh/年（每 MW 平均负荷）
out.costPerMWh = fval / max(Eann, eps);
out.share = zeros(1, R);
out.Pdis = zeros(1, R);
out.Pch = zeros(1, R);
out.E = zeros(1, R);
for k = 1:R
    out.share(k) = sum(x(iD(k))) / max(sum(de), eps);
    out.Pdis(k) = x(iP(k));
    out.Pch(k) = x(iC(k));
    out.E(k) = x(iE(k));
end
out.coef = co;
end

function v = capitalFactor(r, life)
if r == 0
    v = 1 ./ life;
else
    v = r ./ (-expm1(-life .* log1p(r)));
end
end
