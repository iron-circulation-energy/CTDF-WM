function n = params_national()
%PARAMS_NATIONAL 全国 31 省评估参数。
%   铁循环的物理与转换参数取自 params_default('haoji')，保证全国层与区域层（CTDF-WM 仿真）口径一致；
%   本函数只增加全国层特有的数据路径、ERA5 下载、储能服务、成本与情景参数。每个数值的来源与状态见行尾注释与
%   README“全国评估数据”；状态含义同 paramSources：文献 / 实测 / 待核实 / 情景 / PLACEHOLDER。
%
%   储能服务（natStorage）：省内风光组合（按 2019 年风电、光伏累计并网容量配比）与按气温响应的日负荷构成“风光 +
%   季节性储能”的稳定供电单元；风光容量按全记录电量平衡确定（λ 为超配倍数），季节性储能能量由带效率的序列峰值法
%   （sequent-peak）求得。日尺度分析不含日内调节（由短时储能承担，论文中作为假设说明）。基准情景中各省水电按 2019 年
%   消纳占比视为平稳出力（n.svc.hydro），100% 风光为上界情景。

p = params_default('haoji');
root = fileparts(fileparts(mfilename('fullpath')));
n.root = root;
n.dataDir = fullfile(root, 'data', 'national');            % 随代码提供的输入数据（来源见 README“全国评估数据”）
n.outDir = fullfile(root, 'data_real', 'national');        % 下载缓存与结果
n.figDir = fullfile(root, 'figures', 'national');

%% ERA5（经 Open-Meteo 历史天气接口；转换参数与浩吉算例相同）
e = p.weather.era5;
e.rawDir = fullfile(n.outDir, 'raw');
e.years = 2014:2023;          % 10 个完整年 [情景：受免费接口每日限额约束；有密钥时可延长]
e.windCalYear = 2019;         % 风速偏差校正年 = 省级统计年份（国家能源局 2019 年风电并网运行情况）
e.pause = 30;                 % s，请求间隔：免费接口每小时 5000、每日 10000 次加权调用，一年逐时数据约计 26~39 次
e.waits = [30, 120, 300];   % s，限流（HTTP 429）或网络错误后的逐次等待时间；单点失败后跳过，不长时间阻塞
e.maxRetry = 4;
e.maxConsecutiveFail = 4;   % 连续失败的点年数达到该值即判断网络暂不可用，暂停下载并保留已下载数据
e.apikey = '';                % 可选：Open-Meteo 商业接口密钥（非空时改用 customer-archive-api，不受免费限额约束）
e.minYears = 3;               % 至少有该年数（含校正年）全部省份数据齐全时才进行评估，否则提示稍后续跑
e.curtailAdjust = true;
% 风电代表点在 ERA5 网格中风速过低、校正不可达时，借用相邻省份的风电代表点（保留其时序形态），再按本省利用小时校正。
% 山地风电场多位于山脊，ERA5 网格平均风速低估明显；相邻省份代表点更能反映区域天气过程。
e.windDonor = struct('prov', {{'重庆市', '西藏自治区'}}, 'donor', {{'贵州省', '青海省'}});       % 校正目标 = 利用小时数 /(1 − 弃风率)，即不弃风时的可发小时数
n.era5 = e;

%% 铁循环（与区域层一致）
n.fe.hFe = p.iron.hFe;                         % MWh/t [9] 文献
n.fe.mOx = p.iron.oxMassRatio;                 % t(Fe2O3)/t(Fe)
n.fe.kappa = p.station.kappa(1);               % MWh_H2/MWh_Fe，1.04（尾气循环，与绿氨口径一致）[34]；情景 kappa161 为不循环的保守值 [9,33]
n.fe.etaEl = p.station.etaEl(1);               % 电解效率 [待核实]
n.fe.eps = p.station.epsAux(1);                % MWh_el/t_Fe [9] 文献
% 改造机组供电效率 = 0.1229/b，b 为全国 6000 kW 及以上火电厂平均供电煤耗 305.5 gce/kWh（《全国煤电机组改造升级实施方案》
% 发改运行〔2021〕1519 号所引现状值）文献。2005 年后投运机组以超临界/超超临界为主、效率更高，取全国平均为保守值。
n.fe.etaSt = 0.1229 / 0.3055;
n.fe.capEl = p.station.capexElPerKw;           % 元/kW 电解槽装机投资（IEA 2025：中国 600~1200 美元/kW）文献；与氢路线相同
n.fe.capRed = p.station.capexRedPerKwFe;       % 元/kW_Fe 还原厂（≈898 €/kW_Fe [9]）[待核实]
n.fe.capRetro = p.plant.retrofitFrac * p.plant.newCapex;   % 元/kW 改造投资 = 改造比例 [9] × 新建造价（见 n.coal.capex）
n.fe.price = p.iron.price;                     % 元/t 铁粉（铁矿石折铁 + 首次还原电耗推算，见 params_default）[文献推算]
n.fe.siloPerT = 50;                            % 元/t 储存设施投资（敞开/半封闭散货堆场量级）[情景]；情景 siloHigh 取 500（全封闭筒仓量级）
n.fe.loss = p.plant.loss(1);                   % 每循环损耗（除尘效率 > 99.5%，计入装卸与还原磨损）[情景]
n.fe.lifeSt = 25;                              % 年，还原站与电解槽 [情景]
n.fe.lifeRetro = 15;                           % 年，改造部分的摊销年限（2005 年后投运机组在 2035 年后的剩余寿命约 10~20 年）[情景]

%% 氢储能对照
n.h2.etaEl = n.fe.etaEl;                       % 与铁路线相同
n.h2.etaGT = 0.50;                             % 氢燃机效率：联合循环约 0.55~0.60、简单循环约 0.40，季节性调峰取 0.50 [情景]
n.h2.capEl = n.fe.capEl;
n.h2.capGT = 3000;                             % 元/kW，氢燃机（国内燃气联合循环约 2500~3000 元/kW，掺氢/纯氢改型另计）[情景]
n.h2.life = 25;
n.fx = 7.1217;                                 % 元/美元，2024 年人民币平均汇率（国家统计局 2024 年统计公报）文献
% 储氢容量投资（元/kWh_H2，LHV 33.33 kWh/kg）：盐穴 20~40 美元/kg、地面压力容器 400~700 美元/kg
% （Burke, Ogden, Fulton & Cerniauskas 2024, UC Davis ITS UCD-ITS-RR-24-17；盐穴与 Papadias & Ahluwalia 2021,
%  Int. J. Hydrogen Energy, doi:10.1016/j.ijhydene.2021.08.028 的规模相关式一致）
n.h2.storeSalt = 30 * n.fx / 33.33;            % ≈ 6.5，区间 [20, 40] 美元/kg 文献
n.h2.storeSaltRange = [20, 40] * n.fx / 33.33;
n.h2.storeTank = 550 * n.fx / 33.33;           % ≈ 119，区间 [400, 700] 美元/kg 文献
n.h2.storeTankRange = [400, 700] * n.fx / 33.33;
n.h2.lifeStore = 25;
n.h2.saltTierMax = 2;                          % 盐穴可用：1 已运行/示范，2 在建或先导/可行性研究（salt_cn.csv）；3 为乐观情景

%% 绿氨对照（煤电低碳化改造的官方路线之一：绿氨掺烧或纯氨燃烧，复用改造煤电）
% 合成氨 NH3 低位热值 18.6 GJ/t = 5.17 MWh/t；化学计量氢耗 0.1776 t H2/t NH3 = 5.92 MWh_H2(LHV)/t，即 1.145 MWh_H2/MWh_NH3。
n.nh3.h2PerNH3 = 0.1776 * 33.33 / 5.17;        % MWh_H2/MWh_NH3 化学计量 文献
n.nh3.elSyn = 0.5 / 5.17;                      % MWh_el/MWh_NH3：空分、合成回路与压缩约 0.3~0.7 MWh/t NH3 [待核实]
n.nh3.elSynRange = [0.3, 0.7] / 5.17;
n.nh3.etaSt = n.fe.etaSt;                      % 改造机组纯氨燃烧供电效率，取与燃铁相同 [情景]
n.nh3.capSyn = 900 * n.fx;                     % 元/kW_NH3：合成氨 + 空分装置，约 600~1500 美元/kW_NH3 [待核实]
n.nh3.capSynRange = [600, 1500] * n.fx;
n.nh3.store = 0.15 * n.fx;                     % 元/kWh_NH3：常压低温液氨储罐约 0.1~0.3 美元/kWh [待核实]
n.nh3.storeRange = [0.1, 0.3] * n.fx;
n.nh3.capRetro = n.fe.capRetro;                % 元/kW：纯氨燃烧器、脱硝与安全改造，取与燃铁改造相同比例 [情景]
n.nh3.life = 25;
% 改造锅炉的氨掺烧上限（燃料热量份额）。基准取 1（纯氨燃烧，远期技术状态，对氨路线有利）。已实现的规模化掺烧：
% 皖能铜陵 300 MW 机组 10%~35%（2023，Engineering 2024, doi:10.1016/j.eng.2024.06.003）、国能台山 600 MW 机组（2023）；
% JERA 碧南 4 号 1 GW 机组 20%（2024），目标 2030 年代 ≥ 50%、2040 年代纯氨；国家发展改革委、国家能源局
% 《煤电低碳化改造建设行动方案（2024—2027 年）》要求改造机组具备掺烧 10% 以上绿氨的能力。情景 nh3Blend50 / nh3Blend35。
% 氨不足的热量份额由同一机组掺烧铁粉补足（零碳口径，见 natPortfolio）；铁粉燃烧本身仅有 1 MW 级示范，二者均为低技术成熟度。
n.nh3.blendMax = 1;
n.nh3.lifeStore = 30;

%% 可持续性指标（natSustain）
n.water.perKgH2 = 15;                          % L/kg H2：电解耗水含纯水制备损失，化学计量 9 L/kg，常见 10~20 L/kg [待核实]
n.water.stoich = 9;                            % L/kg H2：氢还原铁生成并可冷凝回收的水量（化学计量）
n.makeupCO2 = [0.1, 2.0];                      % t CO2/t Fe：补铁来源从绿氢直接还原铁到高炉—转炉流程的排放强度区间 [待核实]

%% 蒙特卡洛（natMonteCarlo；在全国评估基准服务上重抽成本与技术参数，检验最优路线排序的稳健性）
n.mc.draws = 300;
n.mc.seed = 20261031;
n.mc.retrofitFrac = [0.05, 0.30];              % 改造投资占新建造价比例
n.mc.loss = [0.001, 0.01];                     % 每循环铁损耗
n.mc.kappa = [0.95, 1.61];                     % 还原氢耗 MWh_H2/MWh_Fe
n.mc.siloPerT = [50, 500];                     % 元/t 铁粉储存设施

%% 风光发电成本（输入电价 = 省内风光组合度电成本 × surplusValue）
% 2021 年陆上风电单位千瓦造价平原 5800、山地 7200 元/kW，地面光伏约 4150 元/kW
% （水电水利规划设计总院《中国可再生能源发展报告 2021》，中国能源报 2022-06-27）文献
n.re.capexW = 5800;
n.re.capexWRange = [4000, 7200];               % 下限为 2023 年后降价情景 [情景]
n.re.capexS = 4150;
n.re.capexSRange = [2800, 4150];               % [情景]
n.re.lifeW = 20;                               % 年 [情景]
n.re.lifeS = 25;                               % 年 [情景]
n.re.om = 0.02;                                % 年运维费率 [情景]
n.re.surplusValue = 1.0;                       % 1：充电电量按风光度电成本计价；0：按零价弃电计价 [情景]

%% 通用经济参数
n.r = 0.06;                                    % 折现率 [情景]
n.om = 0.02;                                   % 储能设备年运维费率（LCOS 文献常用 1%~3%）[情景]

%% 运输
% 全国铁路运费按国铁两部制运价：每吨 base1 + perKm × 里程。煤炭适用 4 号运价，基价 1 为 16.3 元/t、基价 2 为
% 0.098 元/(t·km)，另计铁路建设基金 0.033 元/(t·km)（搜狐 2019-07 转引国铁运价表）文献；铁矿石适用更低的 2 号运价，
% 取煤炭运价偏保守。浩吉铁路分段运价 0.174~0.2024 元/(t·km) 只用于区域层算例。
n.rail.base1 = 16.3;
n.rail.perKm = 0.098 + 0.033;
n.rail.detour = 1.3;                           % 铁路里程 / 大圆距离 [情景]
n.rail.speed = 605;                            % km/d（浩吉全线 1813.5 km 约 3 d）[待核实]
n.rail.dwell = 2;                              % d，两端装卸停留合计（散货列车各约 1 d）[情景]
n.uhv.tariff = 0.0701;                         % 元/kWh（发改价格〔2018〕684 号，酒泉—湖南 ±800 kV）文献
n.uhv.loss = 0.065;                            % 线损率（同上）文献
n.uhv.includeConstruction = false;             % 是否计入在建特高压直流 [情景]

%% 煤电与储能服务
% 搁浅风险机组：2005 年及以后投运。按 30 年设计寿命，这批机组在 2035 年仍有剩余寿命，是碳中和路径下提前退役
% 损失的主体 [情景]；敏感性 2010 年（情景 young2010）。
n.coal.yearMin = 2005;
n.coal.capex = p.plant.newCapex;               % 元/kW，新建煤电单位造价（2021 年水平 2×660 MW 约 3700、2×1000 MW 约 3373，
n.coal.capexRange = [3373, 3700];              %   电力规划设计总院《火电工程限额设计参考造价指标（2021 年水平）》）文献
n.coal.life = 30;                              % 年，设计寿命 [情景]
n.coal.retireYear = 2035;                      % 提前退役基准年（剩余寿命价值按直线折算到该年）[情景]；另报 2030、2040 年
% 储能服务中水电的处理：hydro = true 时，各省水电按 2019 年消纳占比（可再生能源消纳比重 − 非水比重，含区外来水）
% 视为平稳出力，风光 + 季节性储能承担其余负荷；false 时为 100% 风光（上界，情景 fullRE）。核电、生物质保守地不计。
n.svc.hydro = true;
n.svc.lambda = 1.0;                            % 风光超配倍数（相对电量平衡容量）[情景]；敏感性 1.25、1.5
n.svc.pinQ = 0.95;                             % 充电功率取日富余功率的分位数（高于该值的富余弃用）[情景]
n.svc.etaRef = 'fe';                           % 储能服务按铁路线往返效率确定（'fe' 或 'h2'）
n.load.mode = 'temp';                          % 'temp'：日负荷按光伏代表点气温响应；'flat'：恒定负荷
n.load.coolBase = e.loadCoolBase;              % °C [待核实]（与浩吉算例相同）
n.load.coolCoef = e.loadCoolCoef;
n.load.heatBase = e.loadHeatBase;
n.load.heatCoef = e.loadHeatCoef;
n.regime.low = p.weather.regLow;               % 低风光日：日风光出力 / 季节基准 < 0.6（与区域层一致）
n.regime.high = p.weather.regHigh;
n.stats.dQuantile = p.stats.dQuantile;
n.stats.deltaQuantile = p.stats.deltaQuantile;
n.steel2019 = 996.34e6;                        % t，2019 年全国粗钢产量（国家统计局 2019 年国民经济和社会发展统计公报）文献

%% 情景集合（natAssess 逐一计算，结果写入 R.scen）
n.scenarios = struct( ...
    'name', {'base', 'fullRE', 'freeSurplus', 'reLow', 'lambda125', 'lambda150', 'saltConservative', ...
             'saltOptimistic', 'uhvConstruction', 'kappa161', 'cheapTech', 'h2Service', 'young2010', 'siloHigh', ...
             'etaEl70', 'retrofit5', 'retrofit30', 'loss1pct', 'mix2024', 'pv2035', 'nh3Cheap', 'nh3Blend50', 'nh3Blend35'}, ...
    'label', {'基准', '100% 风光（不计水电）', '充电电量零价', '风光造价下限', '风光超配 1.25', '风光超配 1.5', ...
              '盐穴保守（仅第 1 级）', '盐穴乐观（含第 3 级）', '计入在建特高压', '还原氢耗 1.61（不循环）', '设备投资减半', ...
              '储能服务按氢效率', '搁浅机组 2010 年后', '储存设施 500 元/t', '电解效率 0.70', '改造投资 5%', ...
              '改造投资 30%', '每循环损耗 1%', '2024 年风光结构', '2035 年光伏主导', '绿氨设备与储罐下限', ...
              '氨掺烧上限 50%', '氨掺烧上限 35%'}, ...
    'set', {{}, {'svc.hydro', false}, {'re.surplusValue', 0}, ...
            {'re.capexW', n.re.capexWRange(1), 're.capexS', n.re.capexSRange(1)}, ...
            {'svc.lambda', 1.25}, {'svc.lambda', 1.5}, {'h2.saltTierMax', 1}, {'h2.saltTierMax', 3}, ...
            {'uhv.includeConstruction', true}, {'fe.kappa', 1.61}, ...
            {'fe.capEl', n.fe.capEl / 2, 'fe.capRed', n.fe.capRed / 2, 'h2.capEl', n.h2.capEl / 2}, ...
            {'svc.etaRef', 'h2'}, {'coal.yearMin', 2010}, {'fe.siloPerT', 500}, ...
            {'fe.etaEl', 0.70, 'h2.etaEl', 0.70}, ...
            {'fe.capRetro', 0.05 * n.coal.capex, 'nh3.capRetro', 0.05 * n.coal.capex}, ...
            {'fe.capRetro', 0.30 * n.coal.capex, 'nh3.capRetro', 0.30 * n.coal.capex}, ...
            {'fe.loss', 0.01}, ...
            {'svc.windOdds', 0.57}, ...
            {'svc.windOdds', 0.40}, ...
            {'nh3.capSyn', n.nh3.capSynRange(1), 'nh3.store', n.nh3.storeRange(1), 'nh3.elSyn', n.nh3.elSynRange(1)}, ...
            {'nh3.blendMax', 0.50}, {'nh3.blendMax', 0.35}});
% 情景说明：mix2024 将各省风电与光伏的容量比按全国 2024 年底结构（风电约 521 GW、光伏约 887 GW）相对 2019 年（约 210、204 GW）
% 等比例改变（风电容量比的几率乘以 0.57）；pv2035 为光伏进一步主导的情景（几率乘以 0.40）[情景]。
n.svc.windOdds = 1;
% 组合优化（natPortfolio）：每省以日尺度线性规划在铁（FeL）、盐穴氢、储罐氢与绿氨之间优化组合，
% 共同满足同一放电需求；铁与氨共用可改造煤电容量。只在下列情景求解（蒙特卡洛不求解）。
n.portfolio.enable = true;
% 燃料路线比较的关键假设各取一档：铁的还原氢耗（kappa161：不循环的保守值，对铁不利）、
% 氨的设备成本（nh3Cheap，对氨有利）与氨掺烧上限（nh3Blend50、nh3Blend35，对氨不利）。不叠加情景。
n.portfolio.scenarios = {'base', 'kappa161', 'nh3Cheap', 'nh3Blend50', 'nh3Blend35'};
n.portfolio.minShare = 0.05;                     % 计为“进入最优组合”的最小放电量份额
end
