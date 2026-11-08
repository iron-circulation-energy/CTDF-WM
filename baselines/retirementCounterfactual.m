function res = retirementCounterfactual(ctx, wx, retro, opts)
%RETIREMENTCOUNTERFACTUAL 改造与直接退役反事实对比。
%   退役情景：全部改造电厂退役（p.retire.selected 为全部电厂），新增替代容量（p.retire.type：'h2' 氢燃机配储氢，或 'battery' 4 h 电池），
%   不建设还原站与循环铁库存。替代容量的运行由评估期逐小时的完全预见线性规划给出（对退役情景有利，
%   保留价值估计因而偏保守）：
%       min Σ_t [c^bk·p^bk_t + π^cur·P^cur_t + π^shed·(P^shed_t + P^ovg_t) + ε·(ch_t + dis_t)]
%       s.t. dis_t − ch_t + p^bk_t − P^cur_t + P^shed_t − P^ovg_t = D_t − P^RE_t
%            e_t = e_{t−1} + η_c·ch_t − dis_t/η_d，0 ≤ e_t ≤ E_cap = P·hours/η_d，e_0 = 0.5·E_cap，e_N ≥ e_0
%            0 ≤ ch_t, dis_t ≤ P，0 ≤ p^bk_t ≤ 备用容量，0 ≤ P^cur_t ≤ P^RE_t
%   用二分法调整替代功率 P，使退役情景评估期缺供电量 EUE 不高于改造情景（相对容差 p.retire.eueTol，
%   绝对容差 p.exp.eueAbsTol）。
%   年化成本（资本回收系数 CRF(r, N) = r(1+r)^N / ((1+r)^N − 1)）：
%     改造：改造投资（retrofitFrac·新建投资·容量，剩余寿命）+ 还原站与电解槽、循环铁库存 c·铁粉单价、料仓（还原站寿命）
%           + 年运维（opexFrac）+ 评估期运行成本折算到年（含物流、仓储、补铁与惩罚项）；
%     退役：替代容量投资（功率 + 能量，寿命 lifeRep）+ 年运维 + 运行成本（备用、
%           弃电与失负荷惩罚）。
%   Historical book value is reported separately and never added to prospective cost.
%   Recoverable iron incurs financing r; capital CRFs imply a financial residual credit
%   for assets surviving the common horizon, which ends at the first selected retirement.
%   保留资产价值 RV = (A_退役 − A_改造)·(1 − (1+r)^(−N))/r，N 为剩余寿命；分解为容量价值（投资相关年成本差）
%   与电量价值（运行成本差）。
%   输入：wx 为元胞数组，每个元素含评估期小时曲线 RE、D（24×nd，MW）与 carbon；retro 字段 eueMWh、opCost（元）、
%         curMWh、REMWh、evalDays、c；opts 字段 cache（可选，复用已计算的 P—EUE 曲线）、type。
%   输出 res：P、Ecap、eue、eueTarget、matched、costs（表）、RV、capValue、enValue、curRateRetro、curRateRet、cache。

p = ctx.p;
if nargin < 4
    opts = struct();
end
if ~isequal(sort(p.retire.selected(:))', 1:ctx.topo.nP)
    error('retirementCounterfactual:partial', '退役情景按全部改造电厂退役设置（p.retire.selected 应为 1:nP）。');
end
typ = getf(opts, 'type', p.retire.type);
sp = p.retire.(typ);
cache = getf(opts, 'cache', struct('P', [], 'eue', [], 'op', [], 'cur', [], 'RE', []));
Ppl = sum(p.plant.pmax);
Pmax = 3 * Ppl;
eueTolerance = max(retro.eueMWh * p.retire.eueTol, p.exp.eueAbsTol);
eueT = retro.eueMWh + eueTolerance;

[r0, cache] = evalP(0, cache);
matched = true;
if r0.eue <= eueT
    Pstar = 0;
else
    [rM, cache] = evalP(Pmax, cache);
    if rM.eue > eueT
        Pstar = Pmax;
        matched = false;
    else
        lo = 0;
        hi = Pmax;
        for it = 1:p.retire.bisectIter
            mid = 0.5 * (lo + hi);
            [rm, cache] = evalP(mid, cache);
            if rm.eue <= eueT
                hi = mid;
            else
                lo = mid;
            end
        end
        Pstar = hi;
    end
end
[rs, cache] = evalP(Pstar, cache);
Ecap = Pstar * sp.hours / sp.etaDischarge;

% ---------------- 年化成本 ----------------
r = p.retire.discount;
crf = @(N) capitalFactor(r, N);
lifeRetro = p.plant.remainLife(:);
if any(lifeRetro <= 0)
    error('retirementCounterfactual:expired', 'Selected retrofit assets must have positive remaining life.');
end
Nrem = getf(opts, 'horizon', min([lifeRetro; p.station.life; p.retire.lifeRep]));
validateattributes(Nrem, {'numeric'}, {'scalar','finite','positive','<=',min([lifeRetro; p.station.life; p.retire.lifeRep])});
af = 1 / crf(Nrem);
yrScale = 365 / retro.evalDays;
kW = 1e3;
capexRetroByPlant = p.plant.retrofitFrac * p.plant.newCapex * p.plant.pmax(:) * kW;
capexRetro = sum(capexRetroByPlant);
eRedNom = p.iron.hFe * p.station.kappa(:) ./ p.station.etaEl(:) + p.station.epsAux(:);
elShare = (p.station.kappa(:) ./ p.station.etaEl(:)) * p.iron.hFe ./ eRedNom;
capexRed = p.station.capexRedPerKwFe * sum(p.station.rhoMax(:) * p.iron.hFe / 24) * kW;
capexEl = p.station.capexElPerKw * sum(p.station.pRedMax(:) .* elShare) * kW;
capexIron = retro.c * p.iron.price;
capexSilo = p.retire.siloCapexPerT * sum(ctx.capInv);
Aretro.capex = sum(capexRetroByPlant .* crf(lifeRetro)) + ...
    (capexRed + capexEl + capexSilo) * crf(p.station.life) + capexIron * r;
Aretro.fixedOM = p.retire.opexFrac * (capexRetro + capexRed + capexEl + capexSilo);
Aretro.op = retro.opCost * yrScale;
capexRepP = sp.capexP * Pstar * kW;
capexRepE = sp.capexE * Ecap * kW;
book = p.plant.bookValueFrac(:)' * (p.plant.newCapex * p.plant.pmax(:) * kW);
Aret.capex = (capexRepP + capexRepE) * crf(p.retire.lifeRep);
Aret.fixedOM = p.retire.opexFrac * (capexRepP + capexRepE);
Aret.op = rs.op * yrScale;
dCap = (Aret.capex + Aret.fixedOM) - (Aretro.capex + Aretro.fixedOM);
dEn = Aret.op - Aretro.op;
res.P = Pstar;
res.Ecap = Ecap;
res.eue = rs.eue;
res.eueTarget = eueT;
res.eueReference = retro.eueMWh;
res.eueTolerance = eueTolerance;
res.serviceFeasible = matched && rs.eue <= eueT;
res.matched = res.serviceFeasible && abs(rs.eue - retro.eueMWh) <= eueTolerance;
res.informationBoundary = 'Replacement dispatched with perfect foresight; retrofit under realised control.';
res.accountingBoundary = 'Prospective resources; historical book value separate; full real recovery of iron; financial residual credits for longer-lived assets.';
res.RV = (dCap + dEn) * af;
res.capValue = dCap * af;
res.enValue = dEn * af;
res.curRateRetro = retro.curMWh / max(retro.REMWh, 1e-9);
res.curRateRet = rs.cur / max(rs.RE, 1e-9);
res.Aretro = Aretro;
res.Aret = Aret;
res.detail = struct('capexRetro', capexRetro, 'capexRed', capexRed, 'capexEl', capexEl, 'capexIron', capexIron, ...
    'capexSilo', capexSilo, 'capexRepP', capexRepP, 'capexRepE', capexRepE, 'book', book, 'Nrem', Nrem, ...
    'annuityFactor', af, 'yrScale', yrScale);
res.detail.capexRetroByPlant = capexRetroByPlant;
res.detail.remainingLifeByPlant = lifeRetro;
res.detail.terminalResidualRetro = terminalResidual(capexRetroByPlant, r, lifeRetro, Nrem);
res.detail.terminalResidualCharging = terminalResidual(capexRed + capexEl + capexSilo, r, p.station.life, Nrem);
res.detail.terminalResidualReplacement = terminalResidual(capexRepP + capexRepE, r, p.retire.lifeRep, Nrem);
res.detail.terminalRecoveredIron = capexIron;
if ~res.serviceFeasible
    res.RV = NaN; res.capValue = NaN; res.enValue = NaN;
end
Item = {'年化投资'; '固定运维'; '运行成本'; '合计'};
Retrofit = [Aretro.capex; Aretro.fixedOM; Aretro.op; Aretro.capex + Aretro.fixedOM + Aretro.op];
Retire = [Aret.capex; Aret.fixedOM; Aret.op; Aret.capex + Aret.fixedOM + Aret.op];
res.costs = table(Item, Retrofit, Retire);
res.cache = cache;

    function [out, cache] = evalP(P, cache)
        hit = find(abs(cache.P - P) <= 1e-9 * max(1, P), 1);
        if ~isempty(hit)
            out = struct('eue', cache.eue(hit), 'op', cache.op(hit), 'cur', cache.cur(hit), 'RE', cache.RE(hit));
            return;
        end
        out = struct('eue', 0, 'op', 0, 'cur', 0, 'RE', 0);
        for m = 1:numel(wx)
            o1 = storageDispatchLP(wx{m}, P, sp, p);
            out.eue = out.eue + o1.eue;
            out.op = out.op + o1.op;
            out.cur = out.cur + o1.cur;
            out.RE = out.RE + o1.RE;
        end
        cache.P(end + 1) = P;
        cache.eue(end + 1) = out.eue;
        cache.op(end + 1) = out.op;
        cache.cur(end + 1) = out.cur;
        cache.RE(end + 1) = out.RE;
    end
end

function v = capitalFactor(r, N)
if r == 0
    v = 1 ./ N;
else
    v = r ./ (1 - (1 + r) .^ (-N));
end
end

function v = terminalResidual(capital, r, life, horizon)
% Unamortised financial value: PV(capital minus discounted residual)=CRF(life)*AF(horizon).
if r == 0
    v = capital .* max(1 - horizon ./ life, 0);
else
    v = capital .* ((1 + r) ^ horizon - capitalFactor(r, life) * ((1 + r) ^ horizon - 1) / r);
    v = max(v, 0);
end
end


function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = d;
end
end
