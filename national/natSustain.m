function Z = natSustain(R, n)
%NATSUSTAIN 各燃料路线每 MWh 放电量的可持续性指标（全国评估基准参数），写入 n.outDir/national_sustainability.csv。
%   Z = natSustain(R, n)；R = natAssess(...)，n = params_national()。
%   路线  Fe（铁粉—铁锈，绿氢还原 + 改造煤电燃烧）、NH3（绿氨 + 改造煤电纯氨燃烧）、H2（绿氢 + 氢燃机）。
%   指标（每 MWh 放电量）
%     rte          往返效率（放电量/充电电量）
%     reInput      所需风光电量 MWh = 1/rte
%     h2kg         消耗氢气 kg（氢低位热值 33.33 kWh/kg）
%     waterGross   电解耗水 m^3（n.water.perKgH2）
%     waterRecov   可冷凝回收的水 m^3：铁路线还原反应 Fe2O3 + 3H2 → 2Fe + 3H2O 生成的水在还原厂内冷凝回用
%                  （按化学计量耗氢 3·2.016/(2·55.85) t H2/t Fe 与 n.water.stoich L/kg H2；超过化学计量的供热用氢燃烧生成的水
%                  与氨、氢路线的燃烧产物水随烟气排出，不计回收）
%     waterNet     净耗水 m^3
%     massT        需要转运的燃料质量 t（铁路线为铁粉去程与氧化铁回程合计 (1 + m_Ox)/e_out；氨为液氨质量；氢为氢气质量）
%     ironOutT     铁路线去程铁粉质量 t = 1/e_out（与燃煤 5000 kcal/kg 动力煤每 MWh 约 0.43 t 对比）
%     makeupT      每 MWh 的补铁量 t（每循环损耗 n.fe.loss）
%     makeupCO2Lo/Hi  补铁的隐含排放 t CO2（n.makeupCO2 区间：绿氢直接还原铁到高炉—转炉）
%     directCO2    燃烧直接排放 t CO2（三条路线均为 0）
%   NOx 与颗粒物定性说明见正文与补充材料：铁粉火焰温度高，NOx 由分级燃烧与既有脱硝系统控制，生成的氧化铁颗粒以布袋/电除尘回收；
%   纯氨燃烧需分级燃烧与选择性催化还原控制 NOx 与 N2O；氢燃机需低 NOx 燃烧器。

f = n.fe;
h2lhv = 33.33e-3;                                 % MWh/kg
etaFe = R.info.etaFe;
etaH2 = R.info.etaH2;
etaNH3 = R.info.etaNH3;
route = ["Fe"; "NH3"; "H2"];
rte = [etaFe; etaNH3; etaH2];
h2kg = [f.kappa / f.etaSt; n.nh3.h2PerNH3 / n.nh3.etaSt; 1 / n.h2.etaGT] / h2lhv;
waterGross = h2kg * n.water.perKgH2 / 1e3;
eOutFe = f.etaSt * f.hFe;                         % MWh/t Fe
h2Stoich = 3 * 2.016 / (2 * 55.845) * 1e3;        % kg H2/t Fe，Fe2O3 + 3H2 → 2Fe + 3H2O
waterRecov = [h2Stoich / eOutFe * n.water.stoich / 1e3; 0; 0];
massT = [(1 + f.mOx) / eOutFe; 1 / (n.nh3.etaSt * 5.17); h2kg(3) / 1e3];
ironOutT = [1 / eOutFe; NaN; NaN];
makeupT = [f.loss / eOutFe; 0; 0];
Z = table(route, rte, 1 ./ rte, h2kg, waterGross, waterRecov, waterGross - waterRecov, massT, ironOutT, makeupT, ...
    makeupT * n.makeupCO2(1), makeupT * n.makeupCO2(2), zeros(3, 1), ...
    'VariableNames', {'route', 'rte', 'reInput', 'h2kg', 'waterGross', 'waterRecov', 'waterNet', 'massT', ...
    'ironOutT', 'makeupT', 'makeupCO2Lo', 'makeupCO2Hi', 'directCO2'});
if ~exist(n.outDir, 'dir')
    mkdir(n.outDir);
end
writetable(Z, fullfile(n.outDir, 'national_sustainability.csv'), 'Encoding', 'UTF-8');
fprintf(['可持续性指标（每 MWh 放电量）：往返效率 铁 %.1f%%、氨 %.1f%%、氢 %.1f%%；净耗水 铁 %.2f、氨 %.2f、氢 %.2f m3；', ...
    '燃料储运质量 铁 %.2f t（含回程氧化铁）、氨 %.2f t；补铁隐含排放 %.4f—%.4f t CO2。\n'], ...
    100 * Z.rte, Z.waterNet, Z.massT(1:2), Z.makeupCO2Lo(1), Z.makeupCO2Hi(1));
end
