function p = params_paper()
%PARAMS_PAPER Locked research protocol from the supplied manuscript, Note 5.
% This returns an unprepared Haoji case. It never downloads data or promises
% a runtime; prepareRealData is a separate, explicit data-preparation action.
p=params_default('haoji');
p.protocol=struct('version','paper-v1','scope','regional-paper', ...
    'requireRealData',true,'requireProvenance',true,'allowNetwork',false, ...
    'allowSyntheticData',false,'coveragePolicy','exact', ...
    'referenceType','fitted_weather_capped_geometric', ...
    'elementInference','single_training_seed');
p.protocol.comparisonScope.M3='matched_configured_budget';
p.protocol.requiredExperiments={'capacity','E1','E2','E3','E4','E5','E6','E7','checks'};
p.protocol.calibrationBoundary=['2019 provincial utilisation statistics calibrate the structural reference. ' ...
    'Weather-process fitting uses 1995-2014; model selection uses 2015-2019; test outcomes use 2020-2024.'];
p.protocol.decisionBoundary=['Candidate values are estimated with common random numbers. The decision mode (distributed ' ...
    'response sweep, central selection, or central selection with training-year value calibration), the hold period and ' ...
    'lambda are selected once on validation years (normal and drought) by a pre-registered rule, minimising the worse ' ...
    'of the two regimes'' cost relative to the fixed policy, and frozen before test evaluation. The controller departs ' ...
    'from the validated fixed policy only when the predicted gain exceeds z paired standard errors, z selected likewise.'];
% 设计点：designScan 扫描充能功率 × 循环质量（验证年、固定候选策略），designSelect 按一倍标准误规则选取——年化总成本
% （运行 + 充能侧投资年金 + 循环铁资金成本）与最低者之差不超过逐年配对差的一倍标准误时视为并列，并列中取失负荷最小者；
% 结果保存在 config/design_point.mat；κ 等参数改变后须重新运行（文件中的 κ 与当前不符时视为未就绪）。
% 充能功率与循环质量须同时满足：功率不足时循环质量以锈积压于还原站，质量不足时电厂缺铁。
p.design=struct('ready',false,'pMult',1,'cNominal',2.0e6,'kappa',p.station.kappa(1),'rule','','stamp','');
dpFile=fullfile(fileparts(mfilename('fullpath')),'design_point.mat');
if isfile(dpFile)
    Ld=load(dpFile,'design');
    if abs(Ld.design.kappa-p.station.kappa(1))<1e-12
        p.design=Ld.design; p.design.ready=true;
    end
end
p.station.pRedMax=p.design.pMult*p.station.pRedMax;
p.stats.cNominalMode='fixed'; p.stats.cNominalFixed=p.design.cNominal;
p.data.cRangeAbs=[3.0e4 3.5e6];
p.protocol.implementationChoices=['Episode length 120; E5 all four scenarios; E6 heatN=5; ' ...
    'E7 five repetitions; E4 stepwise cap 400; snapshots every 1000 final-stage steps.'];
p.data.nTransitions=300000; p.data.valFrac=.1; p.data.episodeLen=120;
p.data.cCover=[.9 1.05]; p.data.socRange=[.2 .9];
p.policy.nLhs=4;
p.ctdf.width=256; p.ctdf.nBlocks=2; p.ctdf.dCond=256; p.ctdf.dT=64;
p.ctdf.batch=256; p.ctdf.lr=3e-4; p.ctdf.ema=1e-3;
p.ctdf.stepsPerStage=5000; p.ctdf.gammaStages=[.8 .9 .95 .99];
p.ctdf.K=32; p.ctdf.nRandCand=12; p.ctdf.lambdaGrid=[0 1 3 10];
p.ctdf.diagEvery=500; p.ctdf.nMicro=8; p.ctdf.snapEvery=1000;
p.ctdf.gpiMode='distributed';
p.mpc.S=8; p.mpc.tune=true; p.mpc.tuneS=8; p.mpc.tuneHorizon=[2 4];
p.mpc.terminalMode='value'; p.mpc.tuneIronValue=[1 5 25]; p.mpc.oxValueFrac=0.5;
p.mpc.tuneTerminalNet=[false true];   % 终端价值是否扣除送达使用点的物流成本，与时域、价值倍数一起在验证年上调参
p.ctdf.decisionModes={'distributed','central','centralCal'}; p.ctdf.holdGrid=[1 0]; p.ctdf.distTol=0.01;
p.ctdf.safeZGrid=[0 1 2];   % 以 M0 为锚的安全改进阈值（配对标准误倍数），验证集选取；0 为不启用
p.ctdf.selectCriterion='worstRegime';   % 验证集常规与干旱两类工况中相对 M0 较差的一类最优（稳健选择，测试前确定）
p.exp.seeds=1:3; p.exp.elementSeeds=1;
p.exp.e1Method='M1'; p.exp.e2Methods={'M0','M1'};
p.exp.e3Methods={'M0','M1','M2','M2o','M3','M4'};   % M2o：完全预见 MPC，上界对照
p.exp.e3MethodSeeds=struct('M3',1,'M2o',1);
p.exp.e3MethodScenarios=struct('M3',{{'normal','drought'}},'M2o',{{'normal','drought'}});
p.exp.e2Extra=struct('name',{'M4'},'c',{[0.5e6 3.5e6]});   % 无守恒流模型在训练质量范围两端与 M1 配对比较
p.exp.e5Scenarios={'normal','drought','outage','stationOut'};
p.exp.cGridN=10; p.exp.cDenseN=0; p.exp.kneeBootB=200;
p.exp.cGridAbs=[0.25 0.5 0.75 1.0 1.25 1.5 1.75 2.0 2.25 2.5 3.0 3.5]*1e6;
p.exp.gtStates=32; p.exp.gtValStates=8; p.exp.gtR=32;
p.exp.gtTcap=400; p.exp.gtSamples=1024;
p.exp.predictionSamples=1024;
p.exp.stepwiseK=8; p.exp.stepwiseTcapCtrl=60; p.exp.stepwiseTcap=400;
p.exp.exactW1Max=512; p.exp.slicedDirs=256;
p.exp.scaleList=[3 6 12]; p.exp.timingReps=5;
p.exp.only=[p.protocol.requiredExperiments,{'figW','fig02','fig03'}];
p.weather.provenanceFile=fullfile(p.weather.era5.dataDir,'provenance.mat');
p=deriveParams(p);
end
