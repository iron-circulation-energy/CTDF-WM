function A = e1Comprehensive(res, p, Phi, retro)
%E1COMPREHENSIVE 改造与退役的全面核算：在 retirementCounterfactual 的社会成本比较之上，逐项加入此前未计的成本与收益。
%   A = e1Comprehensive(res, p, Phi, retro)
%   res    retirementCounterfactual 的输出（RV、Aretro、Aret、P、detail、curRateRet 等）
%   p      参数（p.retire.acct 为本函数的取值与来源）
%   Phi    循环铁平均通量（t/d，ctx.stats.Phi）
%   retro  改造情景的评估期汇总（curMWh、REMWh、evalDays）
%
%   原则：凡对改造计入的收益，替代方案若同样能获得则对称计入；社会成本与投资方视角分开报告；
%   原始建设投资对两种选择都已发生，属沉没成本，不进入社会成本比较，只在全生命周期视角中报告其被继续利用的部分。
%   每一项给出年度成本差的修正 Δ（元/年，正值有利于改造）与按共同会计期折现的保留资产价值修正。
%   类别：
%     核心        拆除费用的推迟、新建并网接入（替代方案与还原站负荷对称计入）、延寿改造投资；
%     成本路径    2030 年电解槽与还原厂投资（两条路线同时调整）；
%     工艺情景    还原氢耗取另一口径（kappaAlt，缺省 1.61 不循环的保守值），电解槽按同一还原能力等比例变化；
%     设计情景    储氢缓冲使还原厂按平均通量配置（未在闭环中模拟）；
%     副产品情景  富余时段售氢、电解副产氧气、余热供热、同步机组的转动惯量；
%     投资方      保留机组的容量电价、避免的账面核销（不计入社会成本合计）；
%     生命周期    原始投资中仍未回收、因改造继续服役的部分（不计入社会成本合计）。
%   输出 A：items（逐项表）、summary（各口径合计与会计期）、breakEven（电解槽投资的盈亏平衡点）、owner、lifecycle。
if ~isfield(res, 'type') || isempty(res.type)
    res.type = p.retire.type;                       % 替代方案类型缺省取参数设定
end

a = p.retire.acct;
r = p.retire.discount;
crf = @(N) capitalFactor(r, N);
kW = 1e3;
Ppl = sum(p.plant.pmax);
d = res.detail;
Nrem = d.Nrem;
af = d.annuityFactor;
yr = d.yrScale;
lifeRetro = d.remainingLifeByPlant(:);
Prep = res.P;
ann = @(cap, life) cap * (crf(life) + p.retire.opexFrac);
eRedNom = p.iron.hFe * p.station.kappa(:) ./ p.station.etaEl(:) + p.station.epsAux(:);
elShare = (p.station.kappa(:) ./ p.station.etaEl(:)) * p.iron.hFe ./ eRedNom;
elMW = sum(p.station.pRedMax(:) .* elShare);
etaEl = p.station.etaEl(1);
h2PerTFe = a.h2PerTFe;                               % t H2 / t Fe（化学计量 54.1 kg）
eOutFe = p.plant.etaSt(1) * p.iron.hFe;              % MWh_e / t Fe（放电侧，汽轮机循环效率口径，偏保守）
dA0 = (res.Aret.capex + res.Aret.fixedOM + res.Aret.op) - (res.Aretro.capex + res.Aretro.fixedOM + res.Aretro.op);

rows = {};
add = @(cat, name, dA, note) {cat, name, dA, note};

% ---- 核心：拆除费用推迟（退役立即支付；改造在延寿后的服役期末支付）----
D0 = a.decomPerKw * Ppl * kW;
Tend = mean(lifeRetro) + a.lifeExt;
rows(end + 1, :) = add('核心', '拆除费用推迟', D0 * crf(Nrem) * (1 - (1 + r) ^ (-Tend)), ...
    sprintf('%.0f 元/kW（RFF 2017 均值 117 美元/kW）', a.decomPerKw));
% ---- 核心：新建接入（两条路线对称）。改造的放电侧沿用电厂既有接入与厂址，但还原站电解与还原负荷需要新建接入；
%      替代方案的充放电共用同一新建接入（容量取功率 P）----
Pst = sum(p.station.pRedMax(:));
rows(end + 1, :) = add('核心', '新建并网接入（双方对称）', ann(a.gridPerKw * Prep * kW, p.retire.lifeRep) ...
    - ann(a.gridPerKw * Pst * kW, p.station.life), ...
    sprintf('%.0f 元/kW；替代方案 %.0f MW，还原站负荷 %.0f MW', a.gridPerKw, Prep, Pst));
% ---- 核心：延寿改造投资（低利用小时运行下延寿 lifeExt 年）----
rows(end + 1, :) = add('核心', '延寿改造投资', -ann(a.lifeExtCapexFrac * p.plant.newCapex * Ppl * kW, a.lifeExt), ...
    sprintf('新建造价的 %.0f%%，延寿 %d 年', 100 * a.lifeExtCapexFrac, a.lifeExt));

% ---- 核心：保留机组的固定运维（退役后不再发生；替代方案运维已按 opexFrac 计入）----
fomFrac = 0;
if isfield(a, 'coalFixedOMFrac') && ~isempty(a.coalFixedOMFrac)
    fomFrac = a.coalFixedOMFrac;
end
coalFOM = fomFrac * p.plant.newCapex * Ppl * kW;
rows(end + 1, :) = add('核心', '保留机组固定运维', -coalFOM, ...
    sprintf('新建造价的 %.1f%%/年（%.0f 元/kW·年），与替代方案运维口径一致', 100 * fomFrac, fomFrac * p.plant.newCapex));

% ---- 核心：剔除弃电惩罚（调度偏好项，不是真实成本；原核算两边的运行成本均含该项）----
curRetroY = retro.curMWh * yr;
curRetY = res.curRateRet * retro.REMWh * yr;
rows(end + 1, :) = add('核心', '剔除弃电惩罚', -p.cost.piCur * (curRetY - curRetroY), ...
    sprintf('%.0f 元/MWh 的调度偏好项不计入经济性比较', p.cost.piCur));
% ---- 核心：替代方案的跨区域输能（风光在西部，替代方案的充电或放电经特高压送达华中；改造以运铁完成同一输能）----
uhvCap = 0;
if isfield(a, 'uhvKm') && ~isempty(a.uhvKm)
    uhvCap = a.uhvCapexPerKwKm * a.uhvKm * Prep * kW;
    rows(end + 1, :) = add('核心', '替代方案跨区域特高压输能', ...
        uhvCap * (crf(a.uhvLife) + p.retire.opexFrac), ...
        sprintf('%.0f km，%.2f 元/(kW·km)，按替代功率 %.0f MW 配置', a.uhvKm, a.uhvCapexPerKwKm, Prep));
end
% ---- 运输口径：铁路按边际运营成本计价（线路建设投资为沉没成本，与原始电厂投资同一原则）----
railItem = 0;
if isfield(retro, 'railCost') && isfield(a, 'railMarginalFrac') && ~isempty(a.railMarginalFrac)
    railItem = (1 - a.railMarginalFrac) * retro.railCost * yr;
    rows(end + 1, :) = add('运输口径', '铁路按边际运营成本计价', railItem, ...
        sprintf('边际运营成本占运价 %.0f%%；铁路运费 %.2f 亿元/年', 100 * a.railMarginalFrac, retro.railCost * yr / 1e8));
end

% ---- 成本路径：2030 年电解槽与还原厂投资（两条路线同时调整）----
saveRetro = ann(d.capexEl * (1 - a.fEl2030) + d.capexRed * (1 - a.fRed2030), p.station.life);
elPartRep = 0;
if isfield(p.retire, res.type) && isfield(p.retire.(res.type), 'capexP') && strcmpi(res.type, 'h2')
    elPartRep = p.station.capexElPerKw / p.retire.h2.capexP;   % 氢替代方案功率投资中电解槽所占比例
end
saveRep = ann(d.capexRepP * elPartRep * (1 - a.fEl2030), p.retire.lifeRep);
rows(end + 1, :) = add('成本路径', '2030 年电解与还原投资', saveRetro - saveRep, ...
    sprintf('电解槽 ×%.2f、还原厂 ×%.2f，替代方案电解部分同步调整', a.fEl2030, a.fRed2030));

% ---- 成本路径：2030 年碳价（改造少用的备用煤电按碳价增量计入；备用电量差由运行成本差折算，不含掺氨与机组可变成本，偏保守）----
carbonItem = 0;
if isfield(a, 'carbon2030') && ~isempty(a.carbon2030) && isfield(retro, 'opOnly')
    cBase = mean(p.weather.carbonRange);
    cBkBase = p.backup.fuelCost + p.backup.ef * cBase;
    bkRetY = res.Aret.op - p.cost.piCur * res.curRateRet * retro.REMWh * yr - p.cost.piShed * res.eue * yr;
    dBkMWh = max(0, (bkRetY - retro.opOnly * yr) / cBkBase);
    carbonItem = (a.carbon2030 - cBase) * p.backup.ef * dBkMWh;
    rows(end + 1, :) = add('成本路径', '2030 年碳价', carbonItem, ...
        sprintf('碳价 %.0f → %.0f 元/tCO2，改造少用备用电量约 %.2f TWh/年', cBase, a.carbon2030, dBkMWh / 1e6));
end

% ---- 工艺情景：还原氢耗 κ 取另一口径（kappaAlt；基准 1.04 为尾气循环，1.61 为不循环的保守值，化学计量约 0.88）----
%      同一还原能力所需电解槽容量按 κ 等比例变化；替代方案不受影响。只计投资，不计电耗变化（充电电量多为富余风光），
%      闭环运行未按该 κ 重算。
kap0 = p.station.kappa(1);
kapA = kap0;
if isfield(a, 'kappaAlt') && ~isempty(a.kappaAlt)
    kapA = a.kappaAlt;
end
kapItem = ann(d.capexEl * (1 - kapA / kap0), p.station.life);
rows(end + 1, :) = add('工艺情景', sprintf('还原氢耗 %.2f', kapA), kapItem, ...
    sprintf('κ %.2f → %.2f MWh_H2/MWh_Fe，化学计量 %.2f；电解槽按同一还原能力等比例变化', kap0, kapA, ...
    h2PerTFe * 33.33 / p.iron.hFe));

% ---- 设计情景：储氢缓冲使还原厂按平均通量配置 ----
rhoMax = sum(p.station.rhoMax);
rhoNew = min(rhoMax, a.bufPeak * Phi);
capRedNew = d.capexRed * rhoNew / rhoMax;
h2Day = elMW * 24 * etaEl;                           % MWh_H2/d（电解槽满功率）
bufCost = a.bufDays * h2Day * kW * p.retire.h2.capexE;
rows(end + 1, :) = add('设计情景', '储氢缓冲与还原厂按平均通量配置', ann(d.capexRed - capRedNew - bufCost, p.station.life), ...
    sprintf('还原能力 %.0f → %.0f t/d，缓冲 %d 天电解满发氢量（盐穴）', rhoMax, rhoNew, a.bufDays));

% ---- 设计情景：盐穴垫底气（替代方案储氢的垫底气须一次性制氢充注；盐穴单价若已含垫底气则不计）----
if strcmpi(res.type, 'h2') && isfield(a, 'cushionFrac') && ~isempty(a.cushionFrac)
    cushT = a.cushionFrac * res.Ecap / 33.33;                % t H2（Ecap 为 MWh_H2 工作气）
    rows(end + 1, :) = add('设计情景', '盐穴垫底气', ann(cushT * 1e3 * a.h2Price, p.retire.lifeRep) - ...
        cushT * 1e3 * a.h2Price * p.retire.opexFrac, ...
        sprintf('垫底气与工作气之比 %.2f，按 %.0f 元/kg 充注', a.cushionFrac, a.h2Price));
end

% ---- 副产品情景（两条路线对称）----
curRetro = retro.curMWh * yr;
curRet = res.curRateRet * retro.REMWh * yr;
selRetro = min(curRetro, elMW * 8760 * a.idleFrac);
elRep = 0;
if strcmpi(res.type, 'h2')
    elRep = Prep;
end
selRep = min(curRet, elRep * 8760 * a.idleFrac);
toH2 = @(mwh) mwh * etaEl / 33.33;                   % t H2
rows(end + 1, :) = add('副产品情景', '富余时段售氢', (toH2(selRetro) - toH2(selRep)) * 1e3 * a.h2Price, ...
    sprintf('%.0f 元/kg，电解槽闲置可用比例 %.1f', a.h2Price, a.idleFrac));
h2Retro = Phi * 365 * h2PerTFe;                      % t H2/年（还原用）
h2Rep = Phi * 365 * eOutFe / max(p.retire.h2.etaDischarge, eps) / 33.33;   % 替代方案放出同等电量所需氢（t/年）
if ~strcmpi(res.type, 'h2')
    h2Rep = 0;
end
rows(end + 1, :) = add('副产品情景', '电解副产氧气', 8 * (h2Retro - h2Rep) * a.o2Price, ...
    sprintf('%.0f 元/t，需有就近用户', a.o2Price));
heat = @(h2t) h2t * 33.33 / etaEl * (1 - etaEl) * a.heatUse * a.heatPrice;
rows(end + 1, :) = add('副产品情景', '电解余热供热', heat(h2Retro) - heat(h2Rep), ...
    sprintf('可利用比例 %.1f，%.0f 元/MWh_th', a.heatUse, a.heatPrice));
syncRep = 0;
if strcmpi(res.type, 'h2')
    syncRep = Prep;
end
rows(end + 1, :) = add('副产品情景', '同步机组转动惯量', (Ppl - syncRep) * kW * a.inertiaPerKwYr, ...
    sprintf('%.0f 元/kW·年（情景）', a.inertiaPerKwYr));

% ---- 政策情景：可再生能源消纳责任权重（退役方案少消纳的风光电量以绿证补足）----
if isfield(a, 'gecPrice') && ~isempty(a.gecPrice)
    rows(end + 1, :) = add('政策情景', '消纳责任权重履约（绿证）', a.gecPrice * (res.curRateRet * retro.REMWh - retro.curMWh) * yr, ...
        sprintf('%.0f 元/MWh', a.gecPrice));
end
% ---- 敏感性（不计入合计）：氢燃机复用退役电厂原址并网接入 ----
rows(end + 1, :) = add('敏感性', '替代方案复用原址并网接入', -ann(a.gridPerKw * Prep * kW, p.retire.lifeRep), ...
    '替代方案不新建接入时对改造的影响，只作敏感性报告');

items = cell2table(rows, 'VariableNames', {'category', 'item', 'dAnnual', 'basis'});
items.dRV = items.dAnnual * af;
sumCat = @(c) sum(items.dAnnual(ismember(items.category, c)));
S.base = dA0;
S.core = dA0 + sumCat({'核心'});
S.core2030 = S.core + sumCat({'成本路径'});
S.design2030 = S.core2030 + sumCat({'设计情景'});
S.all2030 = S.design2030 + sumCat({'副产品情景'});
S.coreToday_design = S.core + sumCat({'设计情景'});
S.allToday = S.core + sumCat({'设计情景', '副产品情景'});
S.kappaToday = S.core + kapItem;                                 % 核心 + 工艺（当前成本）
S.kappa2030 = S.design2030 + a.fEl2030 * kapItem;                % 核心 + 2030 + 设计 + 工艺（电解槽降价后 κ 的节省同比缩小）
S.all2030kappa = S.all2030 + a.fEl2030 * kapItem;
S.coreRail = S.core + railItem;                                  % 核心 + 铁路边际成本（当前成本）
S.all2030Rail = S.all2030 + railItem;
S.all2030RailPolicy = S.all2030Rail + sumCat({'政策情景'});     % 再加消纳责任权重
% 盈亏平衡：最有利口径下使年度成本差为零的铁路边际成本比例（≥ 该比例为负，低于为正）
S.railFracBreakEven = NaN;
if isfield(retro, 'railCost') && retro.railCost > 0
    base0 = S.all2030RailPolicy - railItem;
    S.railFracBreakEven = 1 + base0 / (retro.railCost * yr);
end                            % 核心 + 设计 + 副产品 + 铁路边际成本（2030 年成本）
Nlong = min([min(lifeRetro) + a.lifeExt, p.station.life, p.retire.lifeRep]);
S.Nrem = Nrem;
S.Nlong = Nlong;
fn = fieldnames(S);
for k = 1:numel(fn)
    if ~any(strcmp(fn{k}, {'Nrem', 'Nlong'}))
        S.(['RV_' fn{k}]) = S.(fn{k}) * af;
        S.(['RVlong_' fn{k}]) = S.(fn{k}) / crf(Nlong);
    end
end

% ---- 盈亏平衡：两条路线电解槽单位投资同时下降到多少时年度成本差为零（其余条件按各口径）----
%      ΔA(f) = ΔA(f_0) + (f_0 − f)·g，g 为电解槽投资（按单位投资比例 1）对改造与替代方案年成本之差的贡献。
gEl = ann(d.capexEl, p.station.life) - ann(d.capexRepP * elPartRep, p.retire.lifeRep);
gElK = ann(d.capexEl * kapA / kap0, p.station.life) - ann(d.capexRepP * elPartRep, p.retire.lifeRep);
be = @(dA, f0, g) f0 + dA / g;
B.gEl = gEl;
B.fEl_core = be(S.core, 1, gEl);                      % 电解槽投资相对当前的比例
B.fEl_design2030 = be(S.design2030 - ann(d.capexEl * (1 - a.fEl2030), p.station.life) ...
    + ann(d.capexRepP * elPartRep * (1 - a.fEl2030), p.retire.lifeRep), 1, gEl);   % 只改电解槽、其余按 2030 + 设计
B.fEl_kappa2030 = be(S.kappa2030 - (ann(d.capexEl * kapA / kap0 * (1 - a.fEl2030), p.station.life) ...
    - ann(d.capexRepP * elPartRep * (1 - a.fEl2030), p.retire.lifeRep)), 1, gElK);
B.perKw_core = B.fEl_core * p.station.capexElPerKw;
B.perKw_design2030 = B.fEl_design2030 * p.station.capexElPerKw;
B.perKw_kappa2030 = B.fEl_kappa2030 * p.station.capexElPerKw;
B.note = ['f 为两条路线电解槽单位投资相对当前（' sprintf('%.0f', p.station.capexElPerKw) ' 元/kW）的比例；', ...
    'f ≤ 0 表示仅靠电解槽降价不能使成本差为零。design2030 与 kappa2030 口径中还原厂按 2030 年成本。'];

% ---- 投资方视角（电厂业主；不计入社会成本合计）----
yrsServe = mean(lifeRetro) + a.lifeExt;
pvYrs = (1 - (1 + r) ^ (-yrsServe)) / r;
O.capacityRevenuePV = a.capPrice * Ppl * kW * pvYrs;
O.retrofitPlantCapex = d.capexRetro + a.lifeExtCapexFrac * p.plant.newCapex * Ppl * kW;
O.decomRetire = D0;
O.decomRetrofitPV = D0 * (1 + r) ^ (-yrsServe);
O.fixedOMPV = coalFOM * pvYrs;
O.netOwnerRetrofitMinusRetire = O.capacityRevenuePV - O.retrofitPlantCapex - O.fixedOMPV - O.decomRetrofitPV + O.decomRetire;
O.avoidedWriteOff = d.book;
O.note = '电厂业主只承担机组改造与延寿；充能侧（电解、还原、铁粉）由独立主体投资并按服务收费，不计入业主。';

% ---- 全生命周期（原始投资；不计入社会成本合计）----
I0 = p.plant.newCapex * Ppl * kW;
L.originalInvestment = I0;
L.remainingBook = d.book;
L.shareStrandedIfRetired = d.book / I0;
L.yearsAddedService = yrsServe;
L.note = '原始投资对两种选择都已发生；改造使剩余账面价值对应的资产继续服役，而非提前核销。';

A.items = items;
A.summary = S;
A.breakEven = B;
A.owner = O;
A.lifecycle = L;
end

function v = capitalFactor(r, N)
if r == 0
    v = 1 ./ N;
else
    v = r ./ (1 - (1 + r) .^ (-N));
end
end
