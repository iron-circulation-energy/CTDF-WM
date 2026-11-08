function T = paramSources(p)
%PARAMSOURCES 参数来源与状态表（导出为补充表 6）。
%   T = paramSources(p) 返回 table，列为 符号、名称、取值、单位、来源、状态。
%   状态：'文献'（已给出出处）、'再分析转换'（由再分析气象换算）、'情景重建'（非计量观测）、'待核实'、
%   '情景'（研究设定的情景参数，论文中须作为假设说明）、'PLACEHOLDER'（仅用于冒烟测试）。
%   PLACEHOLDER 参数用于冒烟算例。

fmt = @(v) strjoin(arrayfun(@(a) sprintf('%.4g', a), unique(v(:))', 'UniformOutput', false), '/');
rows = {
    'h_Fe',        '铁热值',                 fmt(p.iron.hFe),            'MWh/t',          '[9]',                 '文献'
    'η^st',        '改造机组供电效率',       fmt(p.plant.etaSt),         '—',              '[5]；0.1229/b，全国平均 b = 305.5 g/kWh（发改运行〔2021〕1519 号）', '文献'
    'η^el',        '电解效率（LHV）',        fmt(p.station.etaEl),       '—',              '碱性电解 60%—65%（Enagás 氢能技术观察 2025）', '文献'
    'κ',           '还原氢耗',               fmt(p.station.kappa),       'MWh_H2/MWh_Fe',  '[34]、Bhaskar 2020；保守情景 1.61 [9,33]', '文献'
    'ε',           '还原辅助电耗',           fmt(p.station.epsAux),      'MWh_el/t_Fe',  '[9]',                 '文献'
    '—',           '改造投资比例',           fmt(p.plant.retrofitFrac),  '新建投资的比例', '[9]（专家访谈）',     '文献'
    '—',           '新建燃煤机组投资',       fmt(p.plant.newCapex),      '元/kW',          '火电工程限额设计参考造价指标（2021 年水平）3373—3700', '文献'
    '—',           '还原厂投资',             fmt(p.station.capexRedPerKwFe), '元/kW_Fe',   '[9] 898 €/kW_Fe，按约 7.7 元/欧元折算', '文献'
    '—',           '电解槽装机投资',         fmt(p.station.capexElPerKw), '元/kW',         'IEA Global Hydrogen Review 2025：中国 600—1200 美元/kW', '文献'
    '—',           '铁粉单价',               fmt(p.iron.price),          '元/t',           '铁矿石（Midrex 2024）折铁 + 首次还原电耗推算', '文献推算'
    'p̲_i',         '最小技术出力',           fmt(p.plant.pmin ./ p.plant.pmax), '额定比例', '灵活性改造后约 30%（发改运行〔2021〕1519 号）', '文献'
    'β̄_i',         '掺氨比例上限',           fmt(p.plant.betaMax),       '—',              '铜陵 300 MW 10%—35%、台山 600 MW 示范（中国能源报 2024-07-29）', '文献'
    '—',           '掺氨电量成本',           [fmt(p.cost.nh3Base), ' + ', fmt(p.cost.nh3PerH2), '×氢价'], '元/MWh_e', '氨含氢 177.6 kg/t、热值 18.6 GJ/t；非氢成本 850 元/t 推算', '文献推算'
    'c^tr(rail)',  '铁路运价',               fmt(p.transport.railCost),  '元/(t·km)',      '—',                   '待核实'
    'c^tr(water)', '水运运价',               fmt(p.transport.waterCost), '元/(t·km)',      '—',                   'PLACEHOLDER'
    'τ_e',         '线路运输时延',           fmt(cell2mat(p.net.lines(:, 5))), 'd',        '—',                   'PLACEHOLDER'
    'L_e',         '线路长度',               fmt(cell2mat(p.net.lines(:, 6))), 'km',       '—',                   'PLACEHOLDER'
    'ℓ',           '每循环颗粒损耗率',       fmt(p.plant.loss),          '—',              '除尘效率 > 99.5%，计入装卸与还原磨损', '情景'
    'x̄',           '电厂铁粉料仓容量',       fmt(p.plant.capFeDays),     'd（满发燃铁量）', '设计参数',            '情景'
    'π^shed',      '失负荷惩罚',             fmt(p.cost.piShed),         '元/MWh',         '可靠性罚函数，失负荷另行直接报告', '情景'
    'π^cur',       '弃电惩罚',               fmt(p.cost.piCur),          '元/MWh',         '调度偏好项',          '情景'
    '—',           '碳价区间',               fmt(p.weather.carbonRange), '元/t',           '—',                   '情景'
    '—',           '氢价区间',               fmt(p.weather.h2Range),     '元/kg',          '煤制氢成本约 12、长三角清洁氢终端价约 34.3（SMM 2026-08）', '文献'
    '—',           '备用电源燃料成本',       fmt(p.backup.fuelCost),     '元/MWh',         '华能国际 2024 年境内火电售电单位燃料成本 300.31', '文献'
    '—',           '备用电源排放因子',       fmt(p.backup.ef),           'tCO2/MWh',       '全国化石能源电力排放因子（2022 年，生态环境部 2024-12-26）', '文献'
    '—',           '特高压单位输电成本',     fmt(p.transport.uhvCostPerKwh), '元/kWh',     '—',                   '待核实'
    '—',           '退役替代：储氢、电池',   [fmt(p.retire.h2.capexE), '、', fmt(p.retire.battery.capexE)], '元/kWh', '盐穴 20—40 美元/kg（Burke et al. 2024）；磷酸铁锂直流侧 0.435—0.495 元/Wh（中国能源报 2024-08-19）', '文献'
    'g',           '载体老化参数',           fmt([p.aging.decayPerCycle, p.aging.aEta, p.aging.aKappa]), '—', '无定量实验数据，论文算例关闭', 'PLACEHOLDER'
    };
if strcmp(p.caseName, 'haoji')
    % 浩吉算例：以下各行覆盖上表同名参数的来源与状态（来源全文见 README“区域算例数据”）
    hz = {
        'c^tr(rail)',  '铁路运价',               fmt(p.transport.railCost),  '元/(t·km)',      '浩吉铁路分段运价 0.174~0.2024（产业信息网 2019-10）', '文献'
        'c^tr(water)', '水运运价',               fmt(p.transport.waterCost), '元/(t·km)',      '长江航运运价指数（交通运输部 2023-04）', '文献'
        '—',           '特高压单位输电成本',     fmt(p.transport.uhvCostPerKwh), '元/kWh',     '发改价格〔2018〕684 号（酒泉—湖南 ±800 kV，线损 6.5%）', '文献'
        'L_e',         '线路长度',               fmt(cell2mat(p.net.lines(:, 6))), 'km',       '浩勒报吉—荆州 1260、—岳阳 1428（产业信息网 2019）；集疏运段为大圆距离 × 绕行系数或长江航道里程估算', '文献/估算'
        'τ_e',         '线路运输时延',           fmt(cell2mat(p.net.lines(:, 5))), 'd',        '浩吉全线 1813.5 km 约 3 d（Wikipedia: Haoji Railway）折算；长江驳运约 240 km/d', '文献/估算'
        'F̄_e',         '线路运力分配',           fmt(cell2mat(p.net.lines(:, 7))), 't/d',      '浩吉设计运能 2 亿 t/年的约 15%', '情景'
        'p̄_i',         '改造机组容量',           fmt(p.plant.pmax),          'MW',             'GPPD v1.3.0（GCPT）全厂容量与投运年；一厂一台为情景选择', '文献'
        'η^st',        '改造机组供电效率',       fmt(p.plant.etaSt),         '—',              '按机组等级典型供电煤耗折算 η = 0.1229/b', '文献推算'
        '—',           '剩余寿命与账面价值比例', fmt(p.plant.bookValueFrac), '—',              '30 年设计寿命直线折算到 2035 年', '情景'
        '—',           '碳价区间',               fmt(p.weather.carbonRange), '元/t',           '全国碳市场 2024 年均价约 95.9（生态环境部 2025-01）；区间为情景', '情景'
        '—',           '风光逐日出力',           'ERA5 1995—2024；2025仅尾部', 'MWh/d',          'ERA5经Open-Meteo获取；功率曲线/光伏模型转换；2019外部结构参照校准，气象过程仅训练年拟合', '再分析转换'
        '—',           '区域日负荷',             '温度响应重建；非计量负荷', 'MWh/d',          '武汉、长沙、南昌气温按2019用电量加权；训练年均值归一', '情景重建'
        '—',           '风电偏差校正目标',       fmt([p.weather.era5.reSites.windTarget]), 'h', '2019 年分省风电利用小时数 /(1 − 弃风率)（国家能源局 2020-02-28）', '文献'
        '—',           '负荷站点权重',           fmt([p.weather.era5.loadSites.weight]), 'GWh', '三省 2019 年全社会用电量（国能发新能〔2020〕31 号推算）', '文献'
        '—',           '风光装机、负荷、备用、还原功率', fmt([p.re.capW, p.re.capS, p.load.mean, p.backup.pmax]), 'MW', '规模校准（保持闭环可行）', '情景'
        };
    keep = ~ismember(rows(:, 2), hz(:, 2));
    rows = [rows(keep, :); hz];
    if ~isempty(p.weather.era5.loadFile)
        k=strcmp(rows(:,2),'区域日负荷');
        rows(k,3:6)={p.weather.era5.loadFile,'MWh/d','外部负荷 CSV','待核实'};
    end
end
T = cell2table(rows, 'VariableNames', {'Symbol', 'Name', 'Value', 'Unit', 'Source', 'Status'});
end
