function p = params_default(caseName)
%PARAMS_DEFAULT 全部默认参数。
%   p = params_default('smoke') 返回冒烟算例参数（2 个还原站、3 座电厂、1 个枢纽、2 个合成气象年）。
%   p = params_default('full')  返回完整算例参数（3 个还原站、6 座电厂、2 个枢纽、30 个气象年）。
%   p = params_default('haoji') 返回浩吉铁路—长江通道算例（规模与 full 相同；节点对应真实地点与机组，
%                               气象与负荷来自 ERA5 再分析，须再调用 p = prepareRealData(p)，见 main 与 README“区域算例数据”）。
%
%   单位约定：物料 t（铁当量）、能量 MWh、功率 MW、成本 元、时间 d 与 h。
%   标记 PLACEHOLDER 的取值用于冒烟算例与流程调试；
%   标记 [待核实] 的取值来自文献或行业经验，投稿前必须核对出处。参数来源表见 paramSources.m。
%
%   规模校准说明（PLACEHOLDER）：风光装机、负荷、备用容量与还原功率按“最小出力约束下的平均燃铁量
%   低于平均可吸收还原量”校准（冒烟算例比值约 1.4），保证存在可持续的铁—锈闭环；容量缺口导致的
%   失负荷为零，使失负荷只由缺铁引起。换用实测数据时须重新校准。

if nargin < 1 || isempty(caseName)
    caseName = 'smoke';
end
caseName = lower(char(caseName));
sizeName = caseName;                 % 规模档位：haoji 算例的数据量、网络宽度、种子数等与 full 相同
if strcmp(caseName, 'haoji')
    sizeName = 'full';
end
projRoot = fileparts(fileparts(mfilename('fullpath')));
p = struct();
p.caseName = caseName;
p.seed = 2026;                       % 全局基准随机种子

%% 1 网络拓扑（节点：名称, 类型 R/P/H, 区域；线路：起点, 终点, 物料, 方式, τ_e(d), L_e(km), 运力 F̄_e(t/d)）
switch caseName
    case 'smoke'
        p.net.nodes = { ...
            'R1', 'R', 'west'; ...
            'R2', 'R', 'west'; ...
            'P1', 'P', 'east'; ...
            'P2', 'P', 'east'; ...
            'P3', 'P', 'coast'; ...
            'H1', 'H', 'central'};
        p.net.lines = { ...
            'R1', 'H1', 'Fe', 'rail',  2, 1200, 6.0e4; ...
            'R2', 'H1', 'Fe', 'rail',  2, 1100, 6.0e4; ...
            'H1', 'P1', 'Fe', 'rail',  1,  300, 6.0e4; ...
            'H1', 'P2', 'Fe', 'rail',  1,  400, 6.0e4; ...
            'R2', 'P3', 'Fe', 'water', 6, 2500, 1.0e5; ...
            'P1', 'H1', 'Ox', 'rail',  1,  300, 6.0e4; ...
            'P2', 'H1', 'Ox', 'rail',  1,  400, 6.0e4; ...
            'H1', 'R1', 'Ox', 'rail',  2, 1200, 6.0e4; ...
            'H1', 'R2', 'Ox', 'rail',  2, 1100, 6.0e4; ...
            'P3', 'R2', 'Ox', 'water', 6, 2500, 1.0e5};
        plantNames = {'P1'; 'P2'; 'P3'};
        plantPmax = [600; 600; 1000];                     % MW，PLACEHOLDER
        stationNames = {'R1'; 'R2'};
        stationPred = [1250; 1250];                       % MW（电解+还原总电功率），PLACEHOLDER
        hubNames = {'H1'};
        p.re.capW = 9000;                                 % MW 风电装机，PLACEHOLDER
        p.re.capS = 6000;                                 % MW 光伏装机，PLACEHOLDER
        p.load.mean = 3000;                               % MW 平均负荷，PLACEHOLDER
        p.backup.pmax = 1200;                             % MW 其他可调度资源（化石备用或区外受电），PLACEHOLDER
    case 'full'
        p.net.nodes = { ...
            'R1', 'R', 'west'; 'R2', 'R', 'west'; 'R3', 'R', 'northwest'; ...
            'P1', 'P', 'central'; 'P2', 'P', 'central'; 'P3', 'P', 'central'; ...
            'P4', 'P', 'coast'; 'P5', 'P', 'coast'; 'P6', 'P', 'coast'; ...
            'H1', 'H', 'railhub'; 'H2', 'H', 'port'};
        p.net.lines = { ...
            'R1', 'H1', 'Fe', 'rail',  2, 1200, 8.0e4; ...
            'R2', 'H1', 'Fe', 'rail',  2, 1100, 8.0e4; ...
            'R3', 'H2', 'Fe', 'rail',  3, 1500, 8.0e4; ...
            'R2', 'H2', 'Fe', 'rail',  3, 1600, 8.0e4; ...     % 跨区联络线，使两个子网连通（多厂联合）
            'H1', 'P1', 'Fe', 'rail',  1,  300, 6.0e4; ...
            'H1', 'P2', 'Fe', 'rail',  1,  350, 6.0e4; ...
            'H1', 'P3', 'Fe', 'rail',  1,  450, 6.0e4; ...
            'H2', 'P4', 'Fe', 'water', 2,  600, 1.0e5; ...
            'H2', 'P5', 'Fe', 'water', 3,  900, 1.0e5; ...
            'H2', 'P6', 'Fe', 'water', 4, 1200, 1.0e5; ...
            'P1', 'H1', 'Ox', 'rail',  1,  300, 6.0e4; ...
            'P2', 'H1', 'Ox', 'rail',  1,  350, 6.0e4; ...
            'P3', 'H1', 'Ox', 'rail',  1,  450, 6.0e4; ...
            'H1', 'R1', 'Ox', 'rail',  2, 1200, 8.0e4; ...
            'H1', 'R2', 'Ox', 'rail',  2, 1100, 8.0e4; ...
            'P4', 'H2', 'Ox', 'water', 2,  600, 1.0e5; ...
            'P5', 'H2', 'Ox', 'water', 3,  900, 1.0e5; ...
            'P6', 'H2', 'Ox', 'water', 4, 1200, 1.0e5; ...
            'H2', 'R3', 'Ox', 'rail',  3, 1500, 8.0e4; ...
            'H2', 'R2', 'Ox', 'rail',  3, 1600, 8.0e4};        % 跨区联络线
        plantNames = {'P1'; 'P2'; 'P3'; 'P4'; 'P5'; 'P6'};
        plantPmax = [600; 600; 1000; 660; 1000; 1000];   % MW，PLACEHOLDER
        stationNames = {'R1'; 'R2'; 'R3'};
        stationPred = [1700; 1700; 1700];                % MW，PLACEHOLDER
        hubNames = {'H1'; 'H2'};
        p.re.capW = 18000;
        p.re.capS = 12000;
        p.load.mean = 6000;
        p.backup.pmax = 2400;
    case 'haoji'
        % 浩吉铁路—长江通道算例（README“区域算例数据”，参数来源见 paramSources）：
        %   还原站 R1 乌审旗（浩吉铁路起点浩勒报吉南附近）、R2 靖边（榆林）、R3 杭锦旗（库布其沙漠基地），均在“西部”；
        %   枢纽 H1 荆州（江陵）煤炭铁水联运储配基地、H2 岳阳（华容）铁水联运基地；
        %   电厂为浩吉铁路沿线与长江沿岸 2011 年后投运的煤电机组（搁浅风险机组，与全国层口径一致；电厂坐标、全厂容量与
        %   投运年取 GPPD v1.3.0 的 GCPT 记录，改造对象为其中指定的机组，见 p.site）。
        %   线路时延 τ = ceil(L/605)：605 km/d 为浩吉全线 1813.5 km 约 3 d 的平均速度（含装卸，向上取整）；
        %   长江驳运按约 240 km/d（10 km/h）估计 [待核实]。线路长度注明“估”的为地图估算 [待核实]。
        %   运力 F̄_e 为情景假设：铁路每条线 8×10⁴ t/d（约 2900 万 t/年，浩吉设计运能 2 亿 t/年 的约 15%），
        %   集疏运 6×10⁴ t/d，长江 1×10⁵ t/d。
        p.net.nodes = { ...
            'R1', 'R', 'west'; 'R2', 'R', 'west'; 'R3', 'R', 'west'; ...
            'P1', 'P', 'central'; 'P2', 'P', 'central'; 'P3', 'P', 'central'; ...
            'P4', 'P', 'central'; 'P5', 'P', 'central'; 'P6', 'P', 'central'; ...
            'H1', 'H', 'railhub'; 'H2', 'H', 'railhub'};
        p.net.lines = { ...
            'R1', 'H1', 'Fe', 'rail',  3, 1260, 8.0e4; ...   % 浩勒报吉—荆州 1260 km（产业信息网 2019）
            'R2', 'H1', 'Fe', 'rail',  2, 1100, 8.0e4; ...   % 靖边—荆州（估：1260 − 160）
            'R3', 'H2', 'Fe', 'rail',  3, 1678, 8.0e4; ...   % 杭锦旗—岳阳（估：1428 + 250）
            'R2', 'H2', 'Fe', 'rail',  3, 1268, 8.0e4; ...   % 靖边—岳阳（估：1428 − 160），跨枢纽联络
            'H1', 'P1', 'Fe', 'rail',  1,   20, 6.0e4; ...   % 江陵储配基地—华电江陵电厂（估）
            'H1', 'P2', 'Fe', 'rail',  1,  130, 6.0e4; ...   % 荆州—华能荆门电厂（估：大圆距离 114 km × 1.15）
            'H2', 'P3', 'Fe', 'rail',  1,  175, 6.0e4; ...   % 岳阳—华电常德电厂（估：大圆距离 134 km × 1.3）
            'H2', 'P4', 'Fe', 'water', 1,   70, 1.0e5; ...   % 华容基地—华能岳阳电厂（城陵矶），长江（估）
            'H2', 'P5', 'Fe', 'water', 1,  120, 1.0e5; ...   % 城陵矶—蒲圻电厂（赤壁），长江（估：大圆距离 99 km）
            'H2', 'P6', 'Fe', 'water', 3,  500, 1.0e5; ...   % 城陵矶—九江电厂，长江（估：城陵矶—武汉约 230 km + 武汉—九江约 270 km）
            'P1', 'H1', 'Ox', 'rail',  1,   20, 6.0e4; ...
            'P2', 'H1', 'Ox', 'rail',  1,  130, 6.0e4; ...
            'P3', 'H2', 'Ox', 'rail',  1,  175, 6.0e4; ...
            'P4', 'H2', 'Ox', 'water', 1,   70, 1.0e5; ...
            'P5', 'H2', 'Ox', 'water', 1,  120, 1.0e5; ...
            'P6', 'H2', 'Ox', 'water', 3,  500, 1.0e5; ...
            'H1', 'R1', 'Ox', 'rail',  3, 1260, 8.0e4; ...
            'H1', 'R2', 'Ox', 'rail',  2, 1100, 8.0e4; ...
            'H2', 'R3', 'Ox', 'rail',  3, 1678, 8.0e4; ...
            'H2', 'R2', 'Ox', 'rail',  3, 1268, 8.0e4};
        plantNames = {'P1'; 'P2'; 'P3'; 'P4'; 'P5'; 'P6'};
        % 改造机组容量（MW）：华电江陵 660（GPPD 全厂 660，2017）、华能荆门 2×350（GPPD 700，2014）、华电常德 1×660
        % （全厂 2×660，2015）、华能岳阳三期 1×600（全厂 2524，三期 2011 [待核实]）、华润蒲圻 1×1000 级（全厂 2600，
        % 容量加权投运年 2011 [待核实机组年份]）、国能九江 1×1000（全厂 2104，2018）；一厂一台为情景选择，合计 4620 MW
        plantPmax = [660; 700; 660; 600; 1000; 1000];
        plantYear = [2017; 2014; 2015; 2011; 2011; 2018];   % 改造机组投运年（GPPD；P4、P5 待核实）
        stationNames = {'R1'; 'R2'; 'R3'};
        stationPred = [1700; 1700; 1700];                % MW，情景参数（与 full 相同的规模校准）
        hubNames = {'H1'; 'H2'};
        p.re.capW = 18000;                               % MW，情景参数；prepareRealData 按实测容量因子换算（rescaleCap）
        p.re.capS = 12000;
        p.load.mean = 6000;                              % MW，情景参数：系统所服务的华中负荷份额
        p.backup.pmax = 2400;                            % MW，情景参数：其他可调度资源（区内其他机组或区外受电）
        % p.site：节点名称与近似坐标（图 F01 地图、F06 行标签）；lab 为地图标注相对节点的偏移（度）。
        % 坐标说明：R 为旗/县城附近、P3/P4/P5 取 Wikipedia 电站列表坐标，其余（H1、H2、P1、P2、P6）为所在县市近似位置。
        p.site = struct( ...
            'id',   {'R1', 'R2', 'R3', 'H1', 'H2', 'P1', 'P2', 'P3', 'P4', 'P5', 'P6'}, ...
            'short', {'乌审旗', '靖边', '杭锦旗', '荆州江陵枢纽', '岳阳华容枢纽', '华电江陵', '华能荆门', '华电常德', ...
                      '华能岳阳', '华润蒲圻', '国能九江'}, ...
            'lab',  {[-0.75, 0], [-0.75, -0.15], [-0.75, 0.15], [0.45, -0.40], [0.30, 0.45], [-0.45, -0.30], ...
                     [-0.45, 0.25], [-0.40, -0.25], [0.10, -0.45], [0.35, 0.30], [0.30, 0.35]}, ...
            'name', {'乌审旗（浩勒报吉南附近）', '靖边（榆林）', '杭锦旗（库布其）', '荆州江陵煤炭铁水联运储配基地', ...
                     '岳阳华容铁水联运基地', '华电江陵电厂 660 MW（2017）', '华能荆门热电 2×350 MW（2014）', ...
                     '华电常德电厂 1×660 MW（共 2×660，2015）', '华能岳阳电厂三期 1×600 MW', ...
                     '华润电力蒲圻电厂 1×1000 MW 级', '国能九江电厂 1×1000 MW（2018）'}, ...
            'lat',  {38.60, 37.60, 39.83, 30.06, 29.70, 30.0912, 31.0582, 29.0310, 29.4498, 29.6653, 29.8266}, ...
            'lon',  {108.84, 108.80, 108.73, 112.50, 112.85, 112.3106, 112.2487, 111.7000, 113.1623, 113.8734, 116.3760});
        % 地图上的示意走向（图 F01；折线为途经城市的近似坐标，不是实际线路矢量）
        p.siteLines = struct('name', {'浩吉铁路（示意走向）', '长江'}, 'style', {'rail', 'river'}, ...
            'lon', {[108.62, 108.80, 109.49, 110.50, 111.20, 112.53, 112.12, 112.20, 112.24, 112.22, 112.56, 113.10, ...
                     113.52, 114.20, 114.98], ...
                    [111.30, 111.80, 112.25, 112.43, 112.40, 112.88, 113.15, 113.47, 113.90, 114.30, 114.88, 115.50, ...
                     116.00, 117.00, 118.40, 119.50, 120.40, 121.30]}, ...
            'lat', {[38.93, 37.60, 36.60, 35.40, 34.77, 32.99, 32.01, 31.03, 30.42, 30.05, 29.53, 29.30, 28.85, 28.00, ...
                     27.11], ...
                    [30.62, 30.40, 30.30, 30.02, 29.72, 29.82, 29.45, 29.82, 30.15, 30.58, 30.40, 29.90, 29.75, 30.50, ...
                     31.40, 32.20, 31.90, 31.50]});
    otherwise
        error('params_default:case', '未知算例 %s，只支持 smoke、full 或 haoji。', caseName);
end
nP = numel(plantNames);
nR = numel(stationNames);
nH = numel(hubNames);

%% 2 物理常数
p.iron.hFe = 2.05;                % MWh/t，铁热值（低位）[9]
p.iron.oxMassRatio = 159.69 / 111.69;  % t(Fe2O3)/t(Fe)，铁锈实际质量与铁当量之比，只用于运费计量
p.iron.price = 3000;              % 元/t，铁粉单价：首次装填可用铁矿石经氢还原，62% 品位铁矿约 100 美元/t（Midrex 2024 年统计）
%                                   折每吨铁约 1150 元，加首次还原电耗约 1500 元，合计约 2700 元，取 3000（含加工）[文献推算]
p.h2.lhvKWhPerKg = 33.33;         % kWh/kg，氢低位热值

%% 3 改造火电（向量顺序与 plantNames 一致）
p.plant.names = plantNames;
p.plant.pmax = plantPmax;                         % MW
p.plant.pmin = 0.30 * plantPmax;                  % MW，最小技术出力：现役机组灵活性改造后约 30% 额定负荷（发改运行〔2021〕1519 号）文献
p.plant.ramp = 0.50 * plantPmax;                  % MW/h，爬坡速率（偏保守的情景取值；日尺度调度中不起约束作用）
p.plant.etaSt = 0.42 * ones(nP, 1);               % 汽轮机循环效率 0.40~0.45 [5]，[待核实]
if strcmp(caseName, 'haoji')
    % 按机组参数等级取典型供电效率 η = 0.1229/b（b 为供电煤耗 kg/kWh）：超超临界 1000 MW 级 b ≈ 0.275、660 MW 级
    % b ≈ 0.285，超临界 600/350 MW 级 b ≈ 0.300；全国平均 0.3055（2020 年，发改运行〔2021〕1519 号）[待核实各厂实际值]
    p.plant.etaSt = [0.431; 0.410; 0.431; 0.410; 0.447; 0.447];
end
p.plant.loss = 0.005 * ones(nP, 1);               % 每循环颗粒损耗率 ℓ_i：电除尘/布袋除尘效率 > 99.5%，计入装卸与还原磨损取 0.5% [情景]
p.plant.betaMax = 0.20 * ones(nP, 1);             % 掺氨比例上限 β̄_i：皖能铜陵 300 MW 机组 10%~35% 掺氨（2023-04）、国能台山
%                                                   600 MW 机组掺氨试验（2023-12）已验证，取 20% [文献：中国能源报 2024-07-29]
p.plant.cop = 25 * ones(nP, 1);                   % 元/MWh，可变运维成本 c^op_i（不含燃料）[情景]
p.plant.capFeDays = 30;                           % 铁粉料仓容量 = capFeDays × 满发日燃铁量（软约束），[情景：设计参数]
p.plant.capOxDays = 30;                           % 锈仓容量 = capOxDays × 满发日燃铁量（软约束），[情景：设计参数]
p.plant.safetyDays = 1.0;                         % 安全铁库存 I̲^Fe_i = safetyDays × 满发日燃铁量，[情景：设计参数]
%   派生量 capFe、capOx、safetyFe（t）由 deriveParams 计算
p.plant.remainLife = 15 * ones(nP, 1);            % 年，剩余寿命（smoke/full 算例，PLACEHOLDER；haoji 算例按投运年计算，见下）
p.plant.newCapex = 3500;                          % 元/kW，新建燃煤机组单位投资：2021 年水平 2×660 MW 约 3700、
%   2×1000 MW 约 3373 元/kW（电力规划设计总院《火电工程限额设计参考造价指标（2021 年水平）》，国信证券 2022-09 引用）
p.plant.retrofitFrac = 0.10;                      % 改造投资占新建投资比例 [9]（专家访谈估计）
p.plant.bookValueFrac = 0.40 * ones(nP, 1);       % 退役时剩余账面价值占新建投资比例（smoke/full，PLACEHOLDER）
if strcmp(caseName, 'haoji')
    % 30 年设计寿命直线折算到提前退役年 2035（与全国层 n.coal.life、n.coal.retireYear 一致）[情景]
    p.plant.commYear = plantYear;
    p.plant.remainLife = max(1, plantYear + 30 - 2035);
    p.plant.bookValueFrac = p.plant.remainLife / 30;
end

%% 4 新能源侧还原站
p.station.names = stationNames;
p.station.pRedMax = stationPred;                  % MW，电解+还原总电功率上限
p.station.kappa = 1.04 * ones(nR, 1);             % MWh_H2/MWh_Fe，还原氢耗：竖炉炉顶煤气脱水后循环（氢直接还原的标准流程）并计加热 [34]；
%                                                   化学计量 0.88（54.1 kg H2/t Fe）；电解槽补氢约 59 kg/t（Bhaskar et al. 2020, Energies 13, 758）
%                                                   折 0.96；与绿氨按合成回路循环计氢耗的口径一致。保守情景 1.61（不循环、以氢燃烧加热）[9,33]
p.station.etaEl = 0.65 * ones(nR, 1);             % 电解效率（LHV）：碱性电解系统 60%~65%（Enagás 氢能技术观察 2025-12）文献；
%                                                   敏感性 0.70（2030 年后改进水平）
p.station.epsAux = 0.06 * ones(nR, 1);            % MWh_el/t_Fe，还原辅助电耗 [9]
p.station.capFeDays = 30;                         % 铁粉料仓容量 = capFeDays × 日还原能力，[情景：设计参数]
p.station.capOxDays = 60;                         % 锈仓容量 = capOxDays × 日还原能力，[情景：设计参数]
p.station.safetyDays = 0.5;                       % 安全锈库存 S̲^Ox_j = safetyDays × 日还原能力，[情景：设计参数]
%   派生量 rhoMax（t/d，还原能力 ρ̄_j = p̄^red_j·24 / e^red_j）、capFe、capOx、safetyOx（t）由 deriveParams 计算
p.station.capexRedPerKwFe = 7000;                 % 元/kW_Fe，还原厂投资：898 €/kW_Fe [9] 按 2024 年约 7.7 元/欧元折算 文献
p.station.capexElPerKw = 6400;                    % 元/kW，电解槽装机投资：2024 年中国制造并安装 600~1200 美元/kW（IEA Global
%                                                   Hydrogen Review 2025），取中值 900 × 7.1217（2024 年平均汇率，国家统计局）文献
p.station.life = 25;                              % 年 [情景]

%% 5 枢纽
p.hub.names = hubNames;
p.hub.capFe = 3.0e5 * ones(nH, 1);                % t，[情景：设计参数]
p.hub.capOx = 3.0e5 * ones(nH, 1);                % t，[情景：设计参数]

%% 6 运输、闭环停留时间与补铁
p.transport.railCost = 0.12;                      % 元/(t·km)，铁路运价 0.10~0.15，[待核实]
p.transport.waterCost = 0.03;                     % 元/(t·km)，水运运价，PLACEHOLDER
p.transport.uhvCostPerKwh = 0.08;                 % 元/kWh，特高压输电单位成本（E6 对比用），[待核实]
p.transport.uhvCostPer1000km = 0;                 % 元/kWh 每千公里，特高压成本随距离增长部分（E6），PLACEHOLDER
if strcmp(caseName, 'haoji')
    p.transport.railCost = 0.18;                  % 元/(t·km)，浩吉铁路分段运价 0.174~0.2024（产业信息网 2019）取中值 [待核实单位口径]
    p.transport.railCostRange = [0.174, 0.2024];  % 元/(t·km)，分段运价范围（图 F14 阴影带）
    p.transport.waterCost = 0.025;                % 元/(t·km)：长江煤炭、金属矿石航线运价 南京—武汉 14.2 元/t、镇江—武汉 12.8 元/t
    %                                               （交通运输部长江航运运价指数 2023-04，约 0.018~0.026）文献
    p.transport.uhvCostPerKwh = 0.0701;           % 元/kWh，酒泉—湖南 ±800 kV 输电价（发改价格〔2018〕684 号，线损率 6.5% 另计）
end
p.loop.dwellPlant = 0;                            % d，日尺度环境无额外厂内队列；非零仅存入Tl.reference
p.loop.dwellStation = 0;                          % d，日尺度环境无额外站内队列；非零仅作假设参照
p.loop.tRed = 0;                                  % d，还原能耗/功率约束已执行，转换在日内完成，无额外跨日队列
p.loop.hMode = 'mean';                            % H 取通量加权平均（'mean'）或最大值（'max'）
p.makeup.reserveFrac = 0;                         % 虚拟储备节点初始存量占 c 的比例（缺省 0：当日损耗计入 V 后立即等量补回，
%                                                   V ≡ 0，c 全部为循环铁，与—(20) 的口径一致）
p.init.feSplit = [0.70, 0.20, 0.05, 0.05];        % 确定性初始化：铁在 电厂/还原站/枢纽/管道 的比例
p.init.oxSplit = [0.10, 0.80, 0.05, 0.05];        % 确定性初始化：锈在 电厂/还原站/枢纽/管道 的比例

%% 7 载体老化模块（参数为 PLACEHOLDER：缺少铁粉多次燃烧—还原循环后反应性衰减的定量实验数据，论文算例 haoji 关闭本模块）
p.aging.enable = ~strcmp(caseName, 'haoji');     % 缺少循环老化的定量实验数据：论文算例（haoji）关闭，冒烟算例保留以检验代码
p.aging.decayPerCycle = 0.002;                    % 每次燃烧—还原循环品质指数下降量
p.aging.floor = 0.85;                             % 品质指数下限
p.aging.aEta = 0.30;                              % η_eff = η·(1 − aEta·(1 − g))
p.aging.aKappa = 0.30;                            % κ_eff = κ·(1 + aKappa·(1 − g))

%% 8 成本与价格
p.cost.piCur = 50;                                % 元/MWh，弃电惩罚 π^cur（调度偏好项，不计入经济性比较）[情景]
p.cost.piShed = 1.0e4;                            % 元/MWh，失负荷惩罚 π^shed（10 元/kWh，作为可靠性约束的罚函数；失负荷电量
%                                                   与断供事件另行直接报告，结论不依赖该取值）[情景]
p.cost.cHold = 0.02;                              % 元/(t·d)，仓储成本 c^hd，[情景：设计参数]
p.cost.cMk = p.iron.price;                        % 元/t，补铁成本 c^mk
% 掺氨电量成本（物理推算）：每 MWh_e 需氨 3.6/(η̄·18.6) t（氨低位热值 18.6 GJ/t），每 t 氨含氢 177.6 kg；
% 非氢成本（合成与空分）约 850 元/t，由国内常规合成氨均价 < 3000 元/t（中国能源报 2024-07-29）减去 177.6 kg × 12 元/kg
% 煤制氢成本推得 [文献推算]
tNH3 = 3.6 / (mean(p.plant.etaSt) * 18.6);
p.cost.nh3Base = 850 * tNH3;                      % 元/MWh_e
p.cost.nh3PerH2 = 177.6 * tNH3;                   % 元/MWh_e 每 元/kg 氢价
p.cost.overflowPenalty = 20;                      % 元/(t·d)，料仓超限惩罚（软约束），[情景：设计参数]
p.cost.redIncentive = 1;                          % 元/MWh，内层调度中的还原优先系数（调度规则，不计入真实成本）
p.backup.fuelCost = 300;                          % 元/MWh：区内其余煤电燃料成本，华能国际 2024 年境内火电售电单位燃料成本 300.31 元/MWh 文献
p.backup.ef = 0.8325;                             % tCO2/MWh：全国化石能源电力 CO2 排放因子（2022 年，生态环境部、国家统计局 2024-12-26）文献

%% 9 气象与负荷过程（马尔可夫切换 + AR(1)）
w = struct();
switch sizeName
    case 'smoke'
        w.Y = 2;
        w.train = 1;
        w.val = 1;                 % 冒烟算例年份较少，验证集复用训练年
        w.test = 2;
    case 'full'
        w.Y = 30;
        w.train = 1:20;            % haoji：1995—2014 年（按时间顺序划分，避免信息泄漏）
        w.val = 21:25;             % haoji：2015—2019 年
        w.test = 26:30;            % haoji：2020—2024 年
end
w.source = 'synthetic';            % 'synthetic' 或 'csv'（见 readWeatherCSV；haoji 算例由 prepareRealData 改为 'csv'）
w.csvFile = '';
w.csvLastIsTail = false;           % 为真时 CSV 最后一年只作为前一年的尾部
w.regLow = 0.6;                    % 实测数据天气状态划分阈值（classifyRegime）：风光日电量/季节基准 < regLow 为低风光
w.regHigh = 1.3;                   % > regHigh 为富余
w.daysPerYear = 365;
w.tailDays = 200;                  % 每年额外生成的尾部天数，供前瞻预测、场景窗口与片段截取使用
% 以下合成气象参数只用于 smoke/full 算例；haoji 算例由 fitWeatherModel 用 ERA5 训练年份重新估计并覆盖
w.pLow = 0.03;                     % 常规→低风光转移概率，PLACEHOLDER
w.pSur = 0.05;                     % 常规→富余转移概率，PLACEHOLDER
w.qLow = 0.80;                     % 低风光持续概率 q（平均持续 5 d），PLACEHOLDER
w.qSur = 0.75;                     % 富余持续概率，PLACEHOLDER
w.P = [1 - w.pLow - w.pSur, w.pLow, w.pSur; 1 - w.qLow, w.qLow, 0; 1 - w.qSur, 0, w.qSur];
w.mW = [1.00, 0.25, 1.50];         % 三状态风电乘子（1 常规、2 低风光、3 富余），PLACEHOLDER
w.mS = [1.00, 0.60, 1.15];         % 三状态光伏乘子，PLACEHOLDER
w.cfW0 = 0.32; w.cfWamp = 0.08; w.cfWpeak = 20; w.cfWmax = 0.95;
w.cfS0 = 0.17; w.cfSamp = 0.05; w.cfSpeak = 172; w.cfSmax = 0.60;
w.phiW = 0.5; w.sigW = 0.20;
w.phiS = 0.4; w.sigS = 0.12;
w.phiL = 0.6; w.sigL = 0.02;
w.lAmp1 = 0.08; w.lPeak1 = 15; w.lAmp2 = 0.05; w.lPeak2 = 200;
w.carbonRange = [60, 200];         % 元/tCO2，每年随机，PLACEHOLDER（haoji 算例见下）
w.h2Range = [12, 35];              % 元/kg：下限为中西部煤制氢成本约 12 元/kg，上限约为长三角清洁氢终端价 34.3 元/kg
%                                    （上海有色网 SMM 中国氢价分析 2026-08）文献
% 典型日形状（hourlyProfiles）
w.shapeWAmp = 0.15; w.shapeWPeak = 4;            % 风电日内形状：1 + a·cos(2π(t − t0)/24)
w.dayLen0 = 12; w.dayLenAmp = 3;                 % 日照时长 h
w.solarNoon = 12;                                % 光伏出力重心时刻（h，北京时间；实测数据由 fitWeatherModel 估计）
w.loadDayAmp = 0.15; w.loadNightDip = 0.10; w.loadEveAmp = 0.05; w.loadEvePeak = 20; w.loadEveWidth = 2;
if strcmp(caseName, 'haoji')
    % 全国碳市场 2024 年成交 1.89 亿 t、成交额 181.14 亿元（均价约 95.9 元/t，生态环境部 2025-01）；区间为情景假设
    w.carbonRange = [60, 120];
    % ERA5 实测数据配置（prepareRealData）
    e = struct();
    e.url = 'https://archive-api.open-meteo.com/v1/archive';
    e.model = 'era5';
    e.timezone = 'Asia/Shanghai';
    e.vars = {'wind_speed_100m', 'temperature_2m', 'surface_pressure', 'shortwave_radiation', ...
        'direct_radiation', 'diffuse_radiation'};
    e.years = 1995:2024;           % 模型年份（30 年：训练 1995—2014、验证 2015—2019、测试 2020—2024）
    e.tailYear = 2025;             % 只作为 2024 年的前瞻尾部
    e.dataDir = fullfile(projRoot, 'data_real', 'era5');
    e.pause = 2;                   % s，请求间隔（Open-Meteo 免费接口有限流）
    % 还原侧风光站点（旗/县城附近的近似坐标）；windTarget 为所在省区 2019 年风电利用小时数 /(1 − 弃风率)，即不弃风时的
    % 可发小时数（国家能源局 2020-02-28：内蒙古 2305 h、弃风 7.1%；陕西 1931 h、弃风 0.6%），与全国层口径一致
    e.reSites = struct('name', {'uxin', 'jingbian', 'hangjin'}, 'lat', {38.60, 37.60, 39.83}, ...
        'lon', {108.84, 108.80, 108.73}, 'windTarget', {2305 / (1 - 0.071), 1931 / (1 - 0.006), 2305 / (1 - 0.071)}, ...
        'pvTarget', {NaN, NaN, NaN}, ...
        'windWeight', {1, 1, 1}, 'pvWeight', {1, 1, 1});
    % 负荷侧气温站点（武汉、长沙、南昌），权重为三省 2019 年全社会用电量（GWh，= 可再生能源消纳量/消纳比重，
    % 国能发新能〔2020〕31 号）
    e.loadSites = struct('name', {'wuhan', 'changsha', 'nanchang'}, 'lat', {30.59, 28.23, 28.68}, ...
        'lon', {114.31, 112.94, 115.86}, 'weight', {72100 / 0.325, 82800 / 0.444, 39200 / 0.255});
    e.windBiasCorrect = true;      % 按官方利用小时数校正 ERA5 风速偏差
    e.windCalYear = 2019;          % 校正年（与 windTarget 的统计年份一致；属于验证期，不使用测试年份）
    % 以下为风光出力换算的通用参数（多兆瓦级陆上机组与晶硅组件的典型值）；风电年电量由偏差校正对齐官方统计，
    % 这些参数只影响日内与日间分布 [方法参数]
    e.windVin = 3;                 % m/s，切入风速
    e.windVr = 12;                 % m/s，额定风速
    e.windVout = 25;               % m/s，切出风速
    e.windLoss = 0.10;             % 尾流、可用率与场内电气损失（文献常用 0.10~0.15）
    e.pvTilt = NaN;                % 固定倾角（°），NaN 取 Jacobson & Jadhav (2018, Solar Energy 169:55) 最佳倾角拟合式
    e.pvAlbedo = 0.20;             % 地表反照率（沙地可达 0.3）
    e.pvNOCT = 45;                 % °C，组件额定工作温度
    e.pvGamma = -0.0035;           % 1/K，功率温度系数（晶硅组件约 −0.0034~−0.0040）
    e.pvPR = 0.85;                 % 性能比（不含温度损失）
    e.loadFile = '';               % 可选：实测日负荷 CSV（列 year, day, load），非空时替代温度模型
    e.loadCoolBase = 25;           % °C，制冷基准温度 [情景]
    e.loadCoolCoef = 0.03;         % 每 °C 制冷负荷增幅（文献区间约 0.02~0.04）[情景]
    e.loadHeatBase = 12;           % °C，采暖基准温度 [情景]
    e.loadHeatCoef = 0.015;        % 每 °C 采暖负荷增幅（文献区间约 0.01~0.02）[情景]
    e.rescaleCap = true;           % 按“训练年平均风光电量与合成算例相同”换算风光装机
    w.era5 = e;
end
p.weather = w;

%% 10 预测器
p.forecast.mode = 'conditional';   % 'conditional'（马尔可夫条件期望）、'noisyTruth'（AR(1) 乘性误差）、'oracle'
p.forecast.sigma0 = 0.05;          % noisyTruth：首日误差标准差
p.forecast.growth = 0.03;          % noisyTruth：标准差随前瞻天数的线性增长率
p.forecast.rho = 0.7;              % noisyTruth：误差 AR(1) 系数
p.forecast.Hmax = 40;              % d，预计算的最大前瞻天数
p.forecast.window3 = 3;            % d，状态中短窗口预测和的天数

%% 11 统计估计（临界循环质量、事件风险）
p.stats.dQuantile = 1.0;           % D_max、U_max 取持续天数的分位数（1 为最大值）
p.stats.deltaQuantile = 1.0;       % δ^D、δ^U 取日净耗的分位数（1 为最大值）
p.stats.flux = 'must';             % Φ̄ 的口径：'must'（必需燃铁量均值）
p.stats.bootB = 1000;              % 自助法次数
p.stats.epsRisk = 0.05;            % 风险校准临界质量的可接受风险 ε
p.stats.cNominalMode = 'eps';      % 数据采集名义质量：'eps' 取 M_crit(ε)，'crit' 取 M_crit

%% 12 策略库与数据采集
switch sizeName
    case 'smoke'
        p.policy.nLhs = 0;         % 每个智能体子库中拉丁超立方补充的策略数
        p.data.nTransitions = 1.2e4;
        p.data.episodeLen = 60;
        p.data.blockEpisodes = 100; % 断点续跑：数据采集每块回合数（每块完成后保存分块文件，不影响数据本身）
    case 'full'
        p.policy.nLhs = 4;
        p.data.nTransitions = 1.0e6;
        p.data.episodeLen = 120;
        p.data.blockEpisodes = 500;
end
p.policy.commitMargin = 1.05;      % 机组组合按峰值缺口的裕度
p.policy.burnSlack = 0.05;         % 燃铁上限的小时分配裕量
p.policy.minCoverEnum = 10;        % 电厂数不超过该值时枚举求最小出力覆盖，否则用贪心
p.policy.ranges.kRes = [0, 25];    % 电厂储备（低风光日数）
p.policy.ranges.band = [1, 6];     % 电厂储备过渡带（低风光日数）
p.policy.ranges.thNH3 = [0, 1];    % 掺氨启用阈值（储备目标的比例）
p.policy.ranges.kapRho = [0.5, 1]; % 还原站计划还原比例
p.policy.ranges.kOx = [0, 20];     % 还原站锈目标（富余日数）
p.policy.ranges.omega = [2, 25];   % 物流对电厂的补货目标（低风光日数）
p.policy.ranges.psi = [0.3, 1];    % 回运比例
p.policy.ranges.hubDays = [0, 5];  % 枢纽周转库存（日数）
p.policy.ranges.fwd = [0, 1.5];    % 前瞻补货系数（未来 H 日必需燃铁量预测的倍数）
p.policy.epsExplore = 0.30;        % 动作扰动概率 ε_explore
p.policy.perturbSigma = 0.30;      % 乘性扰动对数标准差
p.policy.flipProb = 0.05;          % 开机与掺氨状态翻转概率
p.policy.addProb = 0.05;           % 发运量附加随机请求的概率
p.policy.addFrac = 0.10;           % 附加请求占线路运力的比例上限
p.policy.switchDays = [10, 30];    % 行为策略切换周期（d）
p.policy.alignedProb = 0.5;        % 行为策略取“全体同原型”联合策略的概率
p.data.cRange = [0.3, 1.5];        % 采样循环铁总质量相对 cNominal 的范围（cNominal 为标量时）
p.data.cCover = [0.9, 1.05];       % runExperiments 以绝对区间 [0.9·c_min, 1.05·c_max] 采样 c，覆盖 E2 网格
p.data.socRange = [0.2, 0.9];      % 初始荷电状态范围
p.data.cNominal = NaN;             % 由 runExperiments 依据 criticalMass 设定
p.data.valFrac = 0.1;              % 验证年份数据量占训练数据量的比例
p.data.chunkCols = 2.0e5;          % 数据集分块保存的列数
p.data.useParfor = false;          % 并行计算（需 Parallel Computing Toolbox）；缺省串行运行，结果与并行一致

%% 13 CTDF-WM
c = struct();
switch sizeName
    case 'smoke'
        c.width = 128; c.nBlocks = 2; c.dT = 32; c.dCond = 128; c.batch = 128; c.lr = 3e-4; c.ema = 5e-3;
        c.stepsPerStage = 100; c.K = 16; c.nRandCand = 4; c.diagEvery = 50; c.snapEvery = 20;
        c.nMicro = 4;                   % 梯度方差诊断的微批数
        c.lambdaGrid = [0, 1, 10];      % 验证集调参网格
        c.ckptEvery = 50;               % 断点续训：每 ckptEvery 步保存检查点（另在每个 γ 阶段结束时保存，不影响训练结果）
    case 'full'
        c.width = 512; c.nBlocks = 3; c.dT = 128; c.dCond = 512; c.batch = 1024; c.lr = 1e-4; c.ema = 1e-3;
        c.stepsPerStage = 5.0e4; c.K = 128; c.nRandCand = 28; c.diagEvery = 1000; c.snapEvery = 2000;
        c.nMicro = 8;
        c.lambdaGrid = [0, 0.3, 1, 3, 10];
        c.ckptEvery = 5000;
end
c.wd = 1e-3;                        % AdamW 权重衰减
c.beta1 = 0.9; c.beta2 = 0.999; c.epsAdam = 1e-8;
c.gradClip = 1.0;
c.gammaStages = [0.8, 0.9, 0.95, 0.99];
c.useGammaCurriculum = true;
c.nOde = 10;                        % 中点法步数
c.alphaDir = 1.0;                   % Dirichlet 浓度参数
c.useNullSpaceProj = true;
c.useTerminalProj = true;
c.sourceType = 'dirichlet';         % 'dirichlet' 或 'gaussian'
c.maxSnaps = 6;                     % 分布收缩经验检验保存的目标网络快照数
c.lambda = 1.0;                     % 风险权重 λ（验证集调整，runExperiments 写回）
c.varthetaDays = 0.5;              % ϑ = varthetaDays × 平均低风光日净耗铁量（t），按电厂份额折算后取均值
c.precision = 'single';
c.useGPU = 'auto';
c.gpiMode = 'central';              % 'central' 或 'distributed'
p.ctdf = c;

%% 14 随机 MPC
switch sizeName
    case 'smoke'
        p.mpc.S = 3;
        p.mpc.tune = false;         % 冒烟算例不调参
    case 'full'
        p.mpc.S = 20;
        p.mpc.tune = true;          % 在验证集上调整 S 与时域
end
p.mpc.tuneS = [10, 20];             % 验证集调参网格：场景数
p.mpc.tuneHorizon = [1.5, 2, 3];    % 验证集调参网格：时域倍数（H_MPC = 倍数 × T_loop）
p.mpc.horizonFactor = 2;            % H_MPC = horizonFactor × T_loop（≥ T_loop + 缓冲）
p.mpc.Hf = 7;                       % d，前 Hf 天使用共同预测器，其后使用训练年场景窗口
p.mpc.periods = 4;                  % 每日时段数（6 h 一段）
p.mpc.gamma = 0.99;                 % 时域内日成本折扣（与一致）
p.mpc.burnSlack = 0.10;             % 首日燃铁计划转为燃铁上限时的裕量
p.mpc.commitFrac = 0.5;             % 首日计划电量不低于 commitFrac × 最小日发电量时开机（线性松弛的取整规则）
p.mpc.terminalFrac = 1.0;           % 终端铁量低于 terminalFrac × 初始铁量的部分按铁的能量价值计罚（terminalMode = 'shortfall'）
p.mpc.terminalMode = 'shortfall';   % 'shortfall'（终端缺口罚项）或 'value'（末日铁与锈按储量价值计入，见 stochasticMPC）
p.mpc.terminalNet = false;           % 终端储量价值是否扣除送达使用点的物流成本（mpcSetup）
p.mpc.ironValueMult = 1;            % 储量价值倍数 m（terminalMode = 'value'；paper 算例在验证集上调参）
p.mpc.oxValueFrac = 0.5;            % 锈的储量价值占铁的比例
p.mpc.doyWindow = 15;               % d，场景窗口的季节匹配半宽
p.mpc.solver = 'auto';              % 'gurobi'、'yalmip'、'linprog' 或 'auto'

%% 15 内层调度与电网
p.inner.solver = 'auto';            % 'auto'、'gurobi'、'yalmip'、'linprog'
p.inner.bigM = 1e9;                 % 放松爬坡约束时使用的大数
p.grid.useDCPF = false;             % 为真时按区域节点加入 PTDF 线路约束
p.grid.zones = {'all'};             % 区域名称；电厂与还原站按 p.net.nodes 第三列映射到区域
p.grid.lines = zeros(0, 4);         % [起点区域号, 终点区域号, 电抗 x(p.u.), 容量 Fmax(MW)]
p.grid.slack = 1;
p.grid.reShare = 1;                 % 各区域风光出力份额
p.grid.loadShare = 1;               % 各区域负荷份额
p.grid.backupShare = 1;             % 各区域备用容量份额

%% 16 改造与退役反事实
p.retire.type = 'h2';               % 'h2'（氢燃机+储氢）或 'battery'（4 h 电池）
p.retire.h2.capexP = p.station.capexElPerKw + 3000;   % 元/kW：电解槽（同还原站）+ 氢燃机 3000 元/kW [氢燃机待核实]
p.retire.h2.capexE = 30 * 7.1217 / 33.33;      % 元/kWh_H2：盐穴 20~40 美元/kg 取 30（Burke et al. 2024；湖北应城、潜江具备盐穴条件）文献
p.retire.h2.etaCharge = p.station.etaEl(1);    % 电→氢效率，与还原站电解槽相同
p.retire.h2.etaDischarge = 0.40;    % 氢→电效率：替代方案利用小时低，按简单循环燃机取 0.40，与 3000 元/kW 的燃机造价同一口径
                                     % （联合循环约 0.55~0.60，造价约 4500 元/kW）[情景]
p.retire.h2.real = struct('on', true, ...       % 对等信息条件下替代方案的运行约束，与改造情景的机组与物料约束对等
    'turbMin', 0.3, ...                         % 氢燃机最小稳定负荷（低氮燃烧的稳定下限）[情景]
    'startCost', 200, ...                       % 元/MW·次，燃机启动成本 [情景]
    'elMin', 0.2, ...                           % 碱性电解槽最低负荷 [情景]
    'wdDays', 10, 'injDays', 20, ...            % 盐穴满库采气、注气天数（采注速率限制）[情景]
    'compLoss', 0.016);                         % 注气压缩耗能占氢能量比例（60→200 bar 约 1.6%，Neuman & Esser）文献
p.retire.h2.hours = 168;            % h，储氢时长（替代容量按 EUE 匹配，时长为情景设定）[情景]
p.retire.battery.capexP = 300;      % 元/kW，变流器与并网 [情景]
p.retire.battery.capexE = 500;      % 元/kWh：2024 年磷酸铁锂储能直流侧中标 0.435~0.495 元/Wh（中国能源报 2024-08-19）文献
p.retire.battery.etaCharge = 0.94;
p.retire.battery.etaDischarge = 0.94;
p.retire.battery.hours = 4;
% 100 h 长时储能（铁—空气等金属—空气电池类）：能量成本约 20 美元/kWh、往返效率约 40% 为开发商目标值 [待核实]
p.retire.ldes100.capexP = 1500;     % 元/kW [情景]
p.retire.ldes100.capexE = 150;      % 元/kWh [待核实]
p.retire.ldes100.etaCharge = 0.65;
p.retire.ldes100.etaDischarge = 0.65;
p.retire.ldes100.hours = 100;
p.retire.altTypes = {'battery', 'ldes100'};   % E1 另算的替代方案（图 F17 各行）
% E6 运输经济性的补充口径：特高压按实际利用小时回收线路投资（输电价对应设计利用小时），铁锈回程利用回空车辆
p.retire.e6.uhvRefHours = 5000;     % h，特高压输电价对应的线路利用小时 [情景]
p.retire.e6.uhvHours = 2000;        % h，承担季节性可靠供电时线路的年利用小时 [情景]
p.retire.e6.backhaulFrac = 0.5;     % 铁锈回程运价相对重车运价的比例（运煤专线回空车辆）[情景]
p.retire.discount = 0.06;           % 折现率 [情景]（与全国层 n.r 一致）
p.retire.lifeRep = 25;              % 年，替代容量寿命 [情景]
p.retire.opexFrac = 0.02;           % 年运维费占投资比例 [情景]
p.retire.siloCapexPerT = 50;        % 元/t，料仓投资 [情景]，全国层敏感性取 500
p.retire.selected = 1:nP;           % 参与对比的电厂
p.retire.eueTol = 0.01;             % 期望缺供电量匹配的相对容差
p.retire.bisectIter = 12;
p.retire.foresightDays = 3;         % d，替代方案滚动有限预见的天数（retirementForesight / diagE1acct 用；E1 主结果仍为完全预见，对替代方案有利）
p.retire.waterValueGrid = [0.5, 0.8, 1, 1.2, 1.5, 2, 3];   % 滚动预见下窗口外储能量价值（× 备用燃料与碳成本 × η_d）的候选
% 全面核算（e1Comprehensive）：此前未计的成本与收益，社会成本与投资方视角分开；两条路线对称计入
p.retire.acct.decomPerKw = 830;          % 元/kW，煤电拆除与场地处置：RFF (Raimi 2017) 28 项估计均值 117 美元/kW（2016 年），范围 21~466 文献
p.retire.acct.lifeExt = 10;              % 年，改造后低利用小时运行下的延寿年限 [情景]
p.retire.acct.lifeExtCapexFrac = 0.05;   % 延寿改造投资占新建造价比例 [情景]
p.retire.acct.gridPerKw = 500;           % 元/kW，新建替代方案的接入系统、送出工程与选址 [待核实]
p.retire.acct.fEl2030 = 0.5;             % 2030 年电解槽投资相对当前的比例：千标方碱性槽中标价 >500 万元/台，预计降至 200~300 万（中国能源报 2024-02-26）[情景]
p.retire.acct.fRed2030 = 0.7;            % 2030 年还原厂投资相对当前的比例 [情景]
p.retire.acct.bufPeak = 1.5;             % 储氢缓冲下还原能力 = bufPeak × 平均通量 [情景]
p.retire.acct.bufDays = 7;               % 储氢缓冲容量：电解槽满发 bufDays 天的氢量（盐穴，单价同 p.retire.h2.capexE）[情景]
p.retire.acct.h2Price = 20;              % 元/kg，富余时段外售绿氢 [情景]
p.retire.acct.idleFrac = 0.5;            % 弃电时段电解槽可用于外售的容量比例 [情景]
p.retire.acct.o2Price = 300;             % 元/t，电解副产氧气（需就近用户）[待核实]
p.retire.acct.heatUse = 0.3;             % 电解余热可利用比例 [情景]
p.retire.acct.heatPrice = 144;           % 元/MWh_th（约 40 元/GJ 供热价）[情景]
p.retire.acct.inertiaPerKwYr = 20;       % 元/kW·年，同步机组转动惯量与短路容量价值 [情景]
p.retire.acct.railMarginalFrac = 0.25;    % 铁路边际运营成本（牵引能耗、车辆与线路维修、乘务）占运价的比例，敏感性 0.15~0.40：
                                          % 铁路成本以固定成本为主，变动成本约占总成本两成（PMCG 2023 铁路主成本测算）；浩吉铁路建设投资为沉没成本，
                                          % 2024 年一季度货运 2019 万 t（中国日报网 2024-03-31），年化约 0.8 亿 t，设计运能 2 亿 t，能力富余 [情景]
p.retire.acct.uhvKm = 1200;              % km，氢替代方案由西部风光基地向华中输能的特高压线路长度（鄂尔多斯—荆州直线约 1000 km）[情景]
p.retire.acct.uhvCapexPerKwKm = 1.37;    % 元/(kW·km)：酒泉—湖南 ±800 kV 动态投资约 262 亿元、8 GW、2383 km 折算 [待核实]
p.retire.acct.uhvLife = 40;              % 年，特高压线路寿命 [情景]
p.retire.acct.carbon2030 = 200;          % 元/tCO2，2030 年全国碳市场碳价情景（与 2030 年电解与还原成本同一情景）[情景]
p.retire.acct.gecPrice = 5;              % 元/MWh，绿色电力证书价格：可再生能源消纳责任权重的履约成本（2024 年绿证成交价每张数元）[情景]
p.retire.acct.cushionFrac = 0.5;         % 盐穴垫底气与工作气之比（约三分之一库容为垫底气，Neuman & Esser）；垫底气按 h2Price 一次性购入 [情景]
p.retire.acct.coalFixedOMFrac = 0.02;    % 保留煤电机组的年固定运维（人工、检修、保险）占新建造价比例，与替代方案运维口径 opexFrac 一致 [情景]
p.retire.acct.capPrice = 165;            % 元/kW·年，煤电容量电价：固定成本 330 元/kW·年，2026 年起回收比例不低于 50%（发改价格〔2023〕1501 号）文献
p.retire.acct.kappaAlt = 1.61;           % MWh_H2/MWh_Fe，还原氢耗保守情景（尾气不循环、以氢燃烧加热）[9,33]；基准 1.04 见 p.station.kappa
p.retire.acct.h2PerTFe = 0.0541;         % t H2 / t Fe，Fe2O3 氢还原化学计量 文献

%% 17 实验设置
switch sizeName
    case 'smoke'
        p.exp.seeds = 1;
        p.exp.cGridN = 8;
        p.exp.droughtDays = 10;
        p.exp.evalDays = 60;
        p.exp.warmup = 10;
        p.exp.scaleList = [3, 6];
        p.exp.e2Methods = {'M0'};
        p.exp.gtStates = 4; p.exp.gtValStates = 2; p.exp.gtR = 4; p.exp.gtSamples = 256; p.exp.gtTcap = 100;
        p.exp.stepwiseK = 8; p.exp.stepwiseTcap = 30;
        p.exp.stepwiseTcapCtrl = 30;  % M3 闭环决策（E3）时逐步推演的截断步数
        p.exp.verifyDays = 2000;
        p.exp.riskEvents = 1.0e4;
        p.exp.heatN = 3;
        p.exp.e3Methods = {'M0', 'M1', 'M2', 'M3', 'M4'};
        p.exp.e1Method = 'M0';      % E1、E6 使用的运行策略（冒烟算例取 M0 以节省时间）
        p.exp.timingReps = 2;       % E7 每个规模的计时重复次数
        p.exp.e5Scenarios = {'normal', 'drought'};
        p.exp.networkEventGap = 10;      % 完整网络环境检查的事件间隔（d）
    case 'full'
        p.exp.seeds = 1:5;
        p.exp.cGridN = 20;
        p.exp.droughtDays = 14;
        p.exp.evalDays = 365;
        p.exp.warmup = 30;
        p.exp.scaleList = [3, 6, 12, 24];
        p.exp.e2Methods = {'M0', 'M1'};
        p.exp.gtStates = 64; p.exp.gtValStates = 16; p.exp.gtR = 64; p.exp.gtSamples = 2048; p.exp.gtTcap = 600;
        p.exp.stepwiseK = 64; p.exp.stepwiseTcap = 600;
        p.exp.stepwiseTcapCtrl = 300; % M3 闭环截断（截断概率 0.99^300 ≈ 0.05，计算量约为 600 步的一半）
        p.exp.verifyDays = 1.0e5;
        p.exp.riskEvents = 1.0e5;
        p.exp.heatN = 5;
        p.exp.e3Methods = {'M0', 'M1', 'M2', 'M3', 'M4'};
        p.exp.e1Method = 'M1';
        p.exp.timingReps = 5;
        p.exp.e5Scenarios = {'normal', 'drought', 'outage', 'stationOut'};
        p.exp.networkEventGap = 30;
end
p.exp.e3MethodSeeds = struct();     % E3 中个别方法只用部分种子（例如 struct('M3', 1:3)，计算预算受限时），空为全部种子
p.exp.outageLines = [];             % E3 中断线路编号；空时取全部“还原站→枢纽”铁路线路
p.exp.outStations = 1;              % E3 故障还原站编号
p.exp.eueAbsTol = 1.0;              % MWh，E1 退役情景缺供电量匹配的绝对容差
% E6 单因素敏感性（kind：'scale' 为相对基准值的倍数，'value' 为绝对取值，'mode' 为运输方式）[情景区间]：
%   实际往返效率 ±15%（电解效率 0.60~0.70 与机组效率 0.40~0.45 组合下往返效率的变化范围；两端各承担其平方根，见 applyVariant）；
%   还原氢耗 0.95（电解补氢 59 kg/t，Bhaskar et al. 2020）至 1.61（不循环的保守值 [9,33]）；
%   运距、改造成本 ±50%；碳价 60~200 元/t（2024 年全国碳市场均价约 96 元/t 至 2030 年代预期）；氢价同 h2Range
p.exp.sens = struct( ...
    'name',  {'roundtrip', 'kappa', 'mode', 'distance', 'retrofit', 'carbon', 'h2'}, ...
    'label', {'往返效率', '还原氢耗', '运输方式', '运输距离', '改造成本', '碳价', '氢价'}, ...
    'kind',  {'scale', 'value', 'mode', 'scale', 'scale', 'value', 'value'}, ...
    'lo',    {0.85, 0.95, 'rail', 0.5, 0.5, 60, 12}, ...
    'hi',    {1.15, 1.61, 'water', 1.5, 1.5, 200, 35});
p.exp.heatRoundtrip = [0.85, 1.15];  % 热图：实际往返效率倍数范围
p.exp.heatTransport = [0.5, 1.5];    % 热图：运价倍数范围
p.exp.breakevenMaxKm = 4000;         % 盈亏平衡运距图的距离上限（km）
p.exp.outageDays = 7;
p.exp.stationOutDays = 7;
p.exp.extremeStart = 20;            % 极端事件开始日（相对评估窗口）
p.exp.bufferEta = [0.01, 0.05, 0.10];
p.exp.sensFactor = 0.5;             % 单因素敏感性 ±50%
p.exp.exactW1Max = 512;             % 精确 W1 的样本上限
p.exp.slicedDirs = 256;             % 切片 W1 的方向数
p.exp.initSOC = 0.6;                % 评估回合的初始荷电状态
p.exp.resultsRoot = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'results');

%% 18 绘图
p.plot.widthIn = 7.0;               % 英寸，默认图宽（IEEE 双栏通栏约 7.16 英寸）
p.plot.font = 'Source Han Serif SC'; % 首选字体（思源宋体）；未安装时 plotStyle 依次尝试 Noto Serif CJK SC、宋体等
p.plot.fontSize = 9;
p.plot.lang = 'en';                % 图中文字一律英文
p.plot.fontEn = 'Times New Roman'; % 英文字体，导出时加粗
p.plot.exportFontSize = 18;        % 导出字号（磅）；图窗按 导出字号/绘制字号 等比放大

%% 19 派生参数
p = deriveParams(p);
end
