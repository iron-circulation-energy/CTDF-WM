function [lcos, comp, eta] = natCost(route, svc, pin, n, dist, loopDays, store)
%NATCOST 单位放电量平准化成本 LCOS（元/kWh，每 1 MW 放电功率口径），全国评估各路线共用。
%   [lcos, comp, eta] = natCost(route, svc, pin, n, dist, loopDays, store)
%   route     'fe'（铁粉—铁锈：电解制氢还原 + 改造煤电燃烧）、'h2'（电解制氢 + 储氢 + 氢燃机）
%             或 'nh3'（电解制氢 + 合成氨 + 液氨储罐 + 改造煤电纯氨燃烧）
%   svc       储能服务：D（满功率自治天数）、hOut（放电利用小时，h/年）、hIn（充电利用小时，h/年）
%   pin       充电电价（元/kWh）
%   n         params_national()
%   dist      铁粉/铁锈铁路里程（km，单程；'fe' 用）
%   loopDays  闭环周转时间（d，在途库存；'fe' 用）
%   store     储氢容量投资（元/kWh_H2；'h2' 用）
%   comp      1×4 成本构成 [输入电费, 转换设备, 储能容量, 运输]（元/kWh）
%
%   铁：e_red = h_Fe(κ/η_el + ε)，e_out = η_st·h_Fe，η = e_out/e_red；E_out = h_out，E_in = E_out/η，P_in = E_in/h_in；
%       转换设备 = 电解槽 c_el·P_in·(κ/η_el)/(κ/η_el + ε) + 还原厂 c_red·P_in/(κ/η_el + ε)（年金 + 运维）+ 改造 c_retro；
%       储能容量 = 库存（24·D/e_out + 年通量/365 × 周转天数）× 铁价 × r + 料仓年金 + 每循环损耗；
%       运输 = (基价 1 + 每公里运价 × 里程) × (1 + m_Ox) × 年通量（两部制运价；铁粉去程 + 铁锈回程，按实际质量计费）。
%   氢：η = η_el·η_GT；转换设备 = c_el·P_in + c_GT（年金 + 运维）；储能容量 = 储氢投资 × 24·D/η_GT（kWh_H2）。
%   公式与浩吉走廊三路线对比相同（单元测试 TestNational 复现其基准结果）。

crf = @capitalFactor;
r = n.r;
Eout = svc.hOut;                                    % MWh/年（每 MW 放电功率）
switch lower(route)
    case 'fe'
        f = n.fe;
        k = f.kappa / f.etaEl + f.eps / f.hFe;
        eRed = f.hFe * k;
        eOut = f.etaSt * f.hFe;
        eta = eOut / eRed;
        Ein = Eout / eta;
        Pin = Ein / svc.hIn;                        % MW
        capSt = (n.fe.capEl * Pin * (f.kappa / f.etaEl) / k + f.capRed * Pin / k) * 1e3;
        capPl = f.capRetro * 1e3;
        thru = Eout / eOut;                         % t/年
        inv = 24 * svc.D / eOut + thru / 365 * loopDays;
        c1 = pin * Ein * 1e3;
        c2 = capSt * (crf(r, f.lifeSt) + n.om) + capPl * (crf(r, f.lifeRetro) + n.om);
        c3 = inv * f.price * r + inv * f.siloPerT * (crf(r, f.lifeSt) + n.om) + f.loss * thru * f.price;
        c4 = (n.rail.base1 + n.rail.perKm * dist) * (1 + f.mOx) * thru;
    case 'h2'
        h = n.h2;
        eta = h.etaEl * h.etaGT;
        Ein = Eout / eta;
        Pin = Ein / svc.hIn;
        c1 = pin * Ein * 1e3;
        c2 = (h.capEl * Pin + h.capGT) * 1e3 * (crf(r, h.life) + n.om);
        c3 = store * 24 * svc.D / h.etaGT * 1e3 * (crf(r, h.lifeStore) + n.om);
        c4 = 0;
    case 'nh3'
        % 绿氨：电解制氢 + 合成氨（含空分与压缩电耗）+ 常压低温液氨储罐 + 改造煤电纯氨燃烧（复用汽水循环）。
        % 合成装置按充电功率配置并随充电功率波动运行（未计氢缓冲与柔性运行成本，对氨路线偏有利）。
        h = n.nh3;
        k = h.h2PerNH3 / n.fe.etaEl + h.elSyn;      % MWh_el / MWh_NH3
        eta = h.etaSt / k;
        Ein = Eout / eta;
        Pin = Ein / svc.hIn;                        % MW 充电功率
        capCh = (n.fe.capEl * Pin * (h.h2PerNH3 / n.fe.etaEl) / k + h.capSyn * Pin / k) * 1e3;
        capPl = h.capRetro * 1e3;
        c1 = pin * Ein * 1e3;
        c2 = capCh * (crf(r, h.life) + n.om) + capPl * (crf(r, n.fe.lifeRetro) + n.om);
        c3 = h.store * 24 * svc.D / h.etaSt * 1e3 * (crf(r, h.lifeStore) + n.om);
        c4 = 0;
    otherwise
        error('natCost:route', '未知路线 %s。', route);
end
comp = [c1, c2, c3, c4] / (Eout * 1e3);
lcos = sum(comp);
end

function v = capitalFactor(r, life)
if r == 0
    v = 1 ./ life;
else
    v = r ./ (-expm1(-life .* log1p(r)));
end
end
