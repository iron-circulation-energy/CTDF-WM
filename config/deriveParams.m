function p = deriveParams(p)
%DERIVEPARAMS 由基本参数计算派生参数（params_default 末尾调用；E6 敏感性与 E7 规模扩展修改基本参数后须重新调用）。
%   电厂：满发日燃铁量 b^full_i = p̄_i·24 / (η^st_i·h_Fe)（t/d）；
%         料仓容量 capFe = capFeDays·b^full，锈仓容量 capOx = capOxDays·b^full，安全铁库存 I̲^Fe = safetyDays·b^full；
%   还原站：单位还原电耗 e^red_j = h_Fe·κ_j/η^el_j + ε_j（MWh/t），还原能力 ρ̄_j = p̄^red_j·24 / e^red_j（t/d）；
%         料仓容量 capFe = capFeDays·ρ̄，锈仓容量 capOx = capOxDays·ρ̄，安全锈库存 S̲^Ox = safetyDays·ρ̄。

dailyFull = p.plant.pmax(:) * 24 ./ (p.plant.etaSt(:) * p.iron.hFe);
p.plant.dailyFull = dailyFull;
p.plant.capFe = p.plant.capFeDays * dailyFull;
p.plant.capOx = p.plant.capOxDays * dailyFull;
p.plant.safetyFe = p.plant.safetyDays * dailyFull;
eRed = p.iron.hFe * p.station.kappa(:) ./ p.station.etaEl(:) + p.station.epsAux(:);
p.station.eRedNom = eRed;
p.station.rhoMax = p.station.pRedMax(:) * 24 ./ eRed;
p.station.capFe = p.station.capFeDays * p.station.rhoMax;
p.station.capOx = p.station.capOxDays * p.station.rhoMax;
p.station.safetyOx = p.station.safetyDays * p.station.rhoMax;
end
