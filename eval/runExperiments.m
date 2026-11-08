function results = runExperiments(p, opts)
%RUNEXPERIMENTS 实验总控：容量检查、数据采集、模型训练、E1—E7、补充表与全部区域图。
%   results = runExperiments(p) 运行全部实验；opts 字段：
%     only       元胞数组，只运行其中列出的实验块，缺省全部：
%                'train'（数据集、参照分布、全部学习模型、λ 与 MPC 调参）、'capacity'（守恒、临界循环质量与事件风险）、
%                'E1'—'E7'、'checks'（守恒与模型性质检查）、'figW'（气象数据图 F02—F04）、
%                'fig02'（状态向量示意 F20）、'fig03'（测试年 SOC 与节点裕度 F06）；
%     skipTests  为真时跳过单元测试（缺省先运行 tests/ 并要求全部通过）；
%     stamp      时间戳（缺省为当前时间），同一次运行的各实验目录共用；
%     verbose    训练过程输出（缺省 true）；
%     cache      'use'（缺省）、'refresh'、'off'：数据集、真值样本与模型的缓存方式（见“模型缓存”一节）。
%                同一组影响模型的参数只需采集与训练一次，之后的运行自动读取缓存。
%     resume     断点续跑（缺省 false）。true：继续 results/common/ 下最近一次运行（时间戳目录名 yyyyMMdd_HHmmss
%                的字典序最大者）；也可直接给出时间戳字符串，继续指定的运行。要求当前参数与该次运行
%                common/<时间戳>/config.mat 中的 p 完全一致（isequaln），否则报错：参数已改变，请开始新的运行
%                （模型缓存仍自动复用）。续跑时沿用原时间戳目录：M0 选择、λ 调参与 MPC 设置读取 common/<时间戳>/ 下
%                的 M0.mat、lambda.mat、mpc.mat（各模式下都会保存）；容量检查与各实验块若已有 results.mat 则直接读取
%                结果并跳过（不重算、不重新作图）；E1/E2/E3/E5 读取实验目录 episodes/ 中已完成的评估回合，E6 读取
%                variants/ 中已完成的变体。数据采集分块、真值回放逐状态结果与训练检查点保存在缓存目录中，cache 为
%                'use' 时任何模式下都会自动从中断处继续（见 collectDataset、groundTruthSM、trainCTDF）。
%   结果目录：p.exp.resultsRoot/<实验名>/<时间戳>/，各含 config.mat（完整参数、种子与依赖目录）、results.mat、
%   log.txt、ver.txt 及对应图表。公共数据（气象年、数据集分块、模型、真值样本）保存在 common/<时间戳>/。
%   防泄漏：统计量、标准化、行为数据、λ 与 MPC 调参只用训练/验证年份；测试年份只用于最终报告。

if nargin < 2
    opts = struct();
end
allExp = {'train', 'capacity', 'E1', 'E2', 'E3', 'E4', 'E5', 'E6', 'E7', 'checks', 'figW', 'fig02', 'fig03', 'diagGPI', 'diagGPI2', 'diagGPI3', 'diagGPI4', 'diagShed', 'diagMPC', 'diagMass', 'diagSizing'};
only = getf(opts, 'only', getf(p.exp,'only',allExp));
if isstring(only), only=cellstr(only); end
if ~iscellstr(only) || any(~ismember(lower(string(only)),lower(string(allExp)))) || ...
        numel(unique(lower(string(only))))~=numel(only)
    error('runExperiments:only','only must contain distinct supported experiment names: %s.',strjoin(allExp,', '));
end
protocol=[];
if isfield(p,'protocol')
    protocol=paperProtocolPreflight(p,[],struct('mode','prepared','throwOnError',true));
end
runSource = sourceFingerprint(fileparts(fileparts(mfilename('fullpath'))),p);
runtimeInfo = configureRuntime(p);
want = @(name) any(strcmpi(only, name));
verbose = getf(opts, 'verbose', true);
root = p.exp.resultsRoot;
% 断点续跑：确定时间戳，并在 newRunDir 覆盖 config.mat 之前核对参数
resume = getf(opts, 'resume', false);
if isstring(resume)
    resume = char(resume);
end
if ischar(resume)
    stamp = resume;
    resume = true;
elseif resume
    stamp = latestStamp(fullfile(root, 'common'));
else
    stamp = getf(opts, 'stamp', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')));
end
resume = logical(resume);
evalOnlyChange = false;
if ~resume, assertFreshRunDirectory(root,stamp); end
if resume
    checkResume(fullfile(root, 'common', stamp, 'config.mat'), p, stamp);
    sf=fullfile(root,'common',stamp,'source_fingerprint.mat');
    if ~isfile(sf), error('runExperiments:sourceChanged','Legacy run has no source fingerprint; start a new run.'); end
    old=load(sf,'runSource');
    if ~isequaln(old.runSource,runSource)
        if trainingSourceMatches(old.runSource,runSource)
            evalOnlyChange=true;   % 只有评估、核算或作图代码改变：训练相关代码与数据未变，允许续跑
        else
            error('runExperiments:sourceChanged','Training-relevant code or data changed; start a new run.');
        end
    end
end
if ~getf(opts, 'skipTests', false)
    tr = runtests(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'tests'));
    if any([tr.Failed]) || any([tr.Incomplete])
        error('runExperiments:tests', '单元测试未全部通过（失败 %d 项），停止运行。', nnz([tr.Failed]));
    end
end
seeds = p.exp.seeds(:)';
yrTrain = p.weather.train;
yrVal = p.weather.val;
yrTest = p.weather.test;
S = plotStyle(p);
results = struct('stamp', stamp,'requestedExperiments',{only},'runtime',runtimeInfo);

% ================= 公共部分 =================
R0 = newRunDir(root, 'common', stamp, p, struct('seeds', seeds));
save(fullfile(R0.dir,'source_fingerprint.mat'),'runSource');
if resume
    logMsg(R0.fid, '断点续跑：继续运行 %s（参数与原运行一致，已完成的部分直接读取）。', stamp);
    if evalOnlyChange
        logMsg(R0.fid, ['续跑说明：评估、核算或作图代码已更新，训练相关代码、数据与模型参数未变；', ...
            '已训练的模型继续使用，尚未完成的实验块按更新后的代码计算。']);
    end
end
tAll = tic;
C = buildCase(p);
if ~isempty(protocol)
    protocol=paperProtocolPreflight(p,C.W,struct('mode','prepared','throwOnError',true));
    results.protocol=protocol;
    save(fullfile(R0.dir,'paper_protocol.mat'),'protocol');
    writetable(protocol.checks,fullfile(R0.dir,'paper_preflight.csv'),'Encoding','UTF-8');
    writetable(protocol.budget,fullfile(R0.dir,'paper_planned_budget.csv'),'Encoding','UTF-8');
end
ctx = C.ctx;
cm = C.cm;
logMsg(R0.fid, '算例 %s：电厂 %d、还原站 %d、枢纽 %d、线路 %d；物料维数 n = %d，状态维数 D = %d。', p.caseName, ...
    C.topo.nP, C.topo.nR, C.topo.nH, C.topo.nE, C.idx.n, ctx.L.D);
logMsg(R0.fid, 'T_loop = %.2f d（H = %d）；Φ̄ = %.1f t/d，δ^D = %.1f，δ^U = %.1f，D_max = %d，U_max = %d，q̂ = %.3f。', ...
    C.Tl.mean, C.Tl.H, C.stats.Phi, C.stats.deltaD, C.stats.deltaU, C.stats.Dmax, C.stats.Umax, C.stats.qhat);
logMsg(R0.fid, 'M_LL = %.0f t，M_crit = %.0f t，M_0 = %.0f t，M_crit(ε=%.2f) = %.0f t，名义 c = %.0f t。', ...
    cm.M_LL, cm.M_crit, cm.M_0, cm.eps, cm.M_eps, C.cNominal);
W = C.W; %#ok<NASGU>
save(fullfile(R0.dir, 'case.mat'), 'W', 'cm', '-v7.3');
lib = policyLibrary(p, C.topo, C.stats, p.seed);
results.case = struct('Tl', C.Tl, 'stats', rmfield(C.stats, 'bootRaw'), 'cm', rmfield(cm, {'PF', 'Meps'}), ...
    'cNominal', C.cNominal);

% ================= 容量检查（质量守恒、临界循环质量、事件风险）=================
th = struct('massBalance', [], 'criticalMass', [], 'eventRisk', []);
if want('capacity') || want('checks')
    [done, thDone] = loadDone(resume, root, 'capacity', stamp, 'th', R0.fid);
    if done
        th = thDone;
    else
        Rt = newRunDir(root, 'capacity', stamp, p, struct('common', R0.dir));
        t0 = tic;
        th.massBalance = checkMassBalance(ctx, C.W, yrTrain, C.cNominal, p.exp.verifyDays, p.seed + 11);
        logMsg(Rt.fid, '质量守恒：%d 天，max|1ᵀx − c|/c = %.2e，SOC 恒等式误差 = %.2e（补铁项量级 %.2e），满足 = %d。', ...
            th.massBalance.nDays, th.massBalance.maxConsRel, th.massBalance.maxSocErr, th.massBalance.maxMakeupTerm, th.massBalance.pass);
        th.criticalMass = checkCriticalMass(ctx, C.stats, cm);
        th.exactOperator = checkExactOperator();
        logMsg(Rt.fid, '临界循环质量：M_crit = %.0f t；(a) 满足 = %d；(b) 满足 = %d；最大守恒误差 %.2e t。', ...
            th.criticalMass.Mcrit, th.criticalMass.summary.aPass, th.criticalMass.summary.bPass, th.criticalMass.summary.maxConsErr);
        th.eventRisk = checkEventRisk(ctx, C.stats, cm, p.exp.riskEvents, p.seed + 13);
        logMsg(Rt.fid, '事件风险：拟合斜率 %.3e，几何尾斜率 %.3e，阈值一致比例 %.2f。', th.eventRisk.slopeFit, ...
            th.eventRisk.slopeTheory, th.eventRisk.thresholdMatch);
        th.criticalMassNet = checkCriticalMassNetwork(ctx, C.W, yrVal, cm, lib);
        logMsg(Rt.fid, '完整网络环境检查完成（%s）。用时 %.1f s。', th.criticalMassNet.note, toc(t0));
        save(fullfile(Rt.dir, 'results.mat'), 'th');
        writetable(th.criticalMass.table, fullfile(Rt.dir, 'critical_mass.csv'), 'Encoding', 'UTF-8');
        writetable(th.criticalMass.recovery,fullfile(Rt.dir,'critical_mass_recovery.csv'),'Encoding','UTF-8');
        writetable(th.exactOperator.table,fullfile(Rt.dir,'exact_operator_checks.csv'),'Encoding','UTF-8');
        writetable(th.eventRisk.table, fullfile(Rt.dir, 'event_risk.csv'), 'Encoding', 'UTF-8');
        writetable(th.criticalMassNet.table, fullfile(Rt.dir, 'critical_mass_network.csv'), 'Encoding', 'UTF-8');
        fclose(Rt.fid);
    end
    results.capacity = th;
end

% ================= 依赖判断 =================
learned = {'M1','M3','M4'};
requestedMethods = {};
if want('E3'), requestedMethods=[requestedMethods,p.exp.e3Methods]; end
if want('E2'), requestedMethods=[requestedMethods,p.exp.e2Methods]; end
if want('E2') && isfield(p.exp,'e2Extra') && ~isempty(p.exp.e2Extra), requestedMethods=[requestedMethods,{p.exp.e2Extra.name}]; end
if want('E1') || want('fig03'), requestedMethods=[requestedMethods,{p.exp.e1Method}]; end
if want('E4'), requestedMethods=[requestedMethods,learned]; end
if want('E5') || want('checks'), requestedMethods=[requestedMethods,{'M1'}]; end
if want('diagGPI') || want('diagGPI2') || want('diagGPI3') || want('diagGPI4'), requestedMethods=[requestedMethods,{'M1'}]; end
if want('train'), requestedMethods=[requestedMethods,learned,p.exp.e3Methods]; end
needModels=intersect(learned,requestedMethods,'stable');
% Lambda is selected on M1 validation trajectories for all learned comparisons.
if ~isempty(needModels), needModels=union({'M1'},needModels,'stable'); end
needM1=~isempty(needModels);
needMPC=any(strcmp(requestedMethods,'M2')) || any(strcmp(requestedMethods,'M2o')) || want('diagMPC');
needGT=want('E4') || want('E5') || want('checks') || want('train');
needData=needM1;
needAbl=want('E5') || want('train');
ablSeeds=intersect(seeds,getf(p.exp,'elementSeeds',seeds),'stable');

% ================= M0 参考策略（验证年份）=================
% 选择结果保存为 common/<时间戳>/M0.mat；续跑时直接读取
t0 = tic;
fRef = fullfile(R0.dir, 'M0.mat');
if resume && isfile(fRef)
    L = load(fRef, 'ref');
    ref = L.ref;
    logMsg(R0.fid, 'M0 参考策略：%s（续跑，读取 M0.mat）。', ref.name);
else
    ref = referencePolicy(ctx, C.W, lib, yrVal, C.cNominal, seeds(1));
    saveAtomic(fRef, struct('ref', ref));
    logMsg(R0.fid, 'M0 参考策略：%s（验证集平均成本最低），用时 %.1f s。', ref.name, toc(t0));
end
w0 = ref.w;
writetable(ref.table, fullfile(R0.dir, 'M0_selection.csv'), 'Encoding', 'UTF-8');
results.M0 = ref;

% ================= 模型缓存 =================
% 数据集、后继测度真值与训练好的模型只取决于“影响模型的参数”（物理、成本、气象、预测、统计、策略库、数据与训练
% 设置、种子与真值设置，见 modelFingerprint）。缓存目录 results/cache/<时间戳>/ 内保存 fingerprint.mat；再次运行时
% 若找到指纹完全相同的缓存则直接读取，任一相关参数改变都会自动新建缓存并重新采集与训练。
% opts.cache：'use'（缺省，读写缓存）、'refresh'（忽略已有内容，重新计算并覆盖）、'off'（不使用缓存目录）。
% 断点续训/续跑的中间文件（数据分块 data/parts_*、真值逐状态结果 gt_parts_*、训练检查点 ckpt/）也在缓存目录中，
% 只在 'use' 模式下读取；'refresh'/'off' 模式先删除旧的中间文件再重新计算。完成后分块与逐状态文件即被删除。
cacheMode = lower(getf(opts, 'cache', 'use'));
canRead = strcmp(cacheMode, 'use');
if strcmp(cacheMode, 'off')
    store = R0.dir;
else
    [store, hit] = locateCache(fullfile(root, 'cache'), modelFingerprint(p), stamp);
    if hit
        msg = '找到指纹相同的缓存';
    else
        msg = '新建缓存';
    end
    logMsg(R0.fid, '模型缓存目录：%s（%s，模式 %s）。', store, msg, cacheMode);
end
results.cacheDir = store;

% ================= 数据采集 =================
ds = [];
nrm = [];
if needData
    t0 = tic;
    dataDir = fullfile(store, 'data');
    if canRead && isfile(fullfile(dataDir, 'train_index.mat')) && isfile(fullfile(dataDir, 'val_index.mat'))
        ds = loadChunked(dataDir, 'train');
        dsVal = loadChunked(dataDir, 'val');
        src = '读取缓存';
    else
        cRangeAbs = [p.data.cCover(1) * 0.5 * cm.M_LL, p.data.cCover(2) * 2 * cm.M_crit];
        if isfield(p.data, 'cRangeAbs') && numel(p.data.cRangeAbs) == 2
            cRangeAbs = p.data.cRangeAbs;               % 设计点下明确给定的质量采样区间，覆盖 E2 网格与质量扫描
        end
        partTrain = fullfile(dataDir, 'parts_train');      % 断点续跑：逐块保存的回合输出，写入数据缓存后删除
        partVal = fullfile(dataDir, 'parts_val');
        if ~canRead
            removeDir(partTrain);                          % 'refresh'/'off'：不使用旧的分块文件
            removeDir(partVal);
        end
        ds = collectDataset(ctx, C.W, lib, yrTrain, cRangeAbs, p.seed + 1, partTrain);
        pv = ctx.p;
        pv.data.nTransitions = max(pv.data.episodeLen, round(p.data.valFrac * p.data.nTransitions));
        ctxV = ctx;
        ctxV.p = pv;
        dsVal = collectDataset(ctxV, C.W, lib, yrVal, cRangeAbs, p.seed + 2, partVal);
        saveChunked(ds, dataDir, 'train', p.data.chunkCols);
        saveChunked(dsVal, dataDir, 'val', p.data.chunkCols);
        removeDir(partTrain);
        removeDir(partVal);
        src = '新采集';
    end
    ctx.Cref = mean(ds.cost(~ds.pert));
    C.ctx = ctx;
    nrm = buildNormalizer(ds, ctx);
    cr = ds.info.cNominal;
    logMsg(R0.fid, '数据集（%s）：训练 %d 条转移（未扰动 %d），验证 %d 条；c 采样区间 %s t；C_ref = %.4g 元/日；用时 %.1f s。', ...
        src, numel(ds.from), ds.info.nUnperturbed, numel(dsVal.from), mat2str(round(cr)), ctx.Cref, toc(t0));
    covT = array2table(ds.info.policyCoverage, 'VariableNames', lib.names);
    writetable(covT, fullfile(R0.dir, 'policy_coverage.csv'), 'Encoding', 'UTF-8');
end

% ================= 测试状态与后继测度真值 =================
gtTest = [];
gtVal = [];
if needGT
    t0 = tic;
    gtFile = fullfile(store, 'groundTruth.mat');
    if canRead && isfile(gtFile)
        L = load(gtFile, 'gtTest', 'gtVal');
        gtTest = L.gtTest;
        gtVal = L.gtVal;
        src = '读取缓存';
    else
        gam = p.ctdf.gammaStages;
        gtPartTest = fullfile(store, 'gt_parts_test');     % 断点续跑：逐状态保存的真值样本，groundTruth.mat 保存后删除
        gtPartVal = fullfile(store, 'gt_parts_val');
        if ~canRead
            removeDir(gtPartTest);                         % 'refresh'/'off'：不使用旧的逐状态文件
            removeDir(gtPartVal);
        end
        stTest = sampleStates(ctx, C.W, lib, yrTest, p.exp.gtStates, w0, C.cNominal, p.seed + 3);
        gtTest = groundTruthSM(ctx, lib, stTest, gam, struct('R', p.exp.gtR, 'Tcap', p.exp.gtTcap, ...
            'nSamples', p.exp.gtSamples, 'seed', p.seed + 4, 'partDir', gtPartTest));
        stVal = sampleStates(ctx, C.W, lib, yrVal, p.exp.gtValStates, w0, C.cNominal, p.seed + 5);
        gtVal = groundTruthSM(ctx, lib, stVal, gam, struct('R', p.exp.gtR, 'Tcap', p.exp.gtTcap, ...
            'nSamples', p.exp.gtSamples, 'seed', p.seed + 6, 'partDir', gtPartVal));
        saveAtomic(gtFile, struct('gtTest', gtTest, 'gtVal', gtVal), '-v7.3');
        removeDir(gtPartTest);
        removeDir(gtPartVal);
        src = '新生成';
    end
    logMsg(R0.fid, '后继测度真值（%s）：测试状态 %d、验证状态 %d，每状态 %d 条回放 × %d 天；截断概率 %s；初始状态重建误差 %.2e；用时 %.1f s。', ...
        src, size(gtTest.S0, 2), size(gtVal.S0, 2), p.exp.gtR, p.exp.gtTcap, mat2str(gtTest.truncMass, 3), ...
        max([gtTest.initErr, gtVal.initErr]), toc(t0));
    results.reference=struct('type',gtTest.referenceType,'kernelScope',gtTest.kernelScope, ...
        'independentPaths',gtTest.independentContinuationCount,'samplesPerState',gtTest.sampleCountPerState, ...
        'samplesShareContinuations',true,'Tcap',gtTest.Tcap,'gammas',gtTest.gammas, ...
        'riskTailBound',gtTest.riskTruncationBound,'riskFunctional',gtTest.riskFunctional, ...
        'pathRiskMean',{gtTest.pathRiskMean},'pathRiskInfiniteHorizonCI',{gtTest.pathRiskInfiniteHorizonCI});
end

% ================= 模型训练（各种子；已缓存的模型直接读取）=================
% 断点续训：每个模型训练完立即写入 models_seed<种子>.mat；训练中的模型检查点为 ckpt/<模型名>_seed<种子>.mat
% （见 trainCTDF），中断后再次运行时从检查点继续，训练完成后检查点自动删除。
models = struct();
for nm={'M1','M3','M4','noNull','gauss','noCurr'}, models.(nm{1})=cell(1,numel(seeds)); end
trainTime = struct('M1', nan(1, numel(seeds)), 'M3', nan(1, numel(seeds)), 'M4', nan(1, numel(seeds)));
if needM1
    need = needModels;
    ckDir = fullfile(store, 'ckpt');
    if ~exist(ckDir, 'dir')
        mkdir(ckDir);
    end
    for si = 1:numel(seeds)
        s = seeds(si);
        need=needModels;
        if needAbl && ismember(s,ablSeeds), need=[need,{'noNull','gauss','noCurr'}]; end
        fM = fullfile(store, sprintf('models_seed%d.mat', s));
        mdl = struct();
        if canRead && isfile(fM)
            L = load(fM, 'mdl');
            mdl = L.mdl;
        end
        loaded = intersect(need, fieldnames(mdl), 'stable');
        for k = 1:numel(need)
            nm = need{k};
            if ~isfield(mdl, nm)
                t0 = tic;
                ckFile = fullfile(ckDir, sprintf('%s_seed%d.mat', nm, s));
                if ~canRead && isfile(ckFile)
                    delete(ckFile);                        % 'refresh'/'off'：不使用旧检查点
                end
                mdl.(nm) = trainNamed(nm, ds, nrm, ctx, lib, p.ctdf, s, gtVal, verbose, ckFile);
                if isfield(trainTime, nm)
                    trainTime.(nm)(si) = toc(t0);
                end
                saveAtomic(fM, struct('mdl', mdl), '-v7.3');   % 每训练完一个模型立即保存（原子写入）
            end
            models.(nm){si} = refreshDecisionCfg(mdl.(nm), p.ctdf);
        end
        logMsg(R0.fid, '种子 %d：读取缓存模型 [%s]；新训练 [%s]；新训练用时 M1 %.1f s、M3 %.1f s、M4 %.1f s。', s, ...
            strjoin(loaded, ' '), strjoin(setdiff(need, loaded, 'stable'), ' '), trainTime.M1(si), trainTime.M3(si), ...
            trainTime.M4(si));
    end
    results.trainTime = trainTime;
end
sIdx = @(s) find(seeds == s, 1);

% ================= 决策规则选定与 λ 调参（验证年份，M1 种子 1）=================
% 预先约定的规则（p.protocol.decisionBoundary）：候选价值一律以公共随机数估计；
%   1) 在验证年 × {常规, 干旱} 上，以 λ = 0 评估 决策方式 {分布式, 集中式, 集中式 + 训练年价值校准} × 保持天数 p.ctdf.holdGrid
%      （0 表示 H = ⌈T_loop⌉）；
%   2) 若分布式的最低验证成本不高于全部配置最低成本的 (1 + p.ctdf.distTol) 倍，取分布式（与多主体分属的现实一致），
%      否则取验证成本最低的配置；
%   3) 在选定配置上按 p.ctdf.lambdaGrid 调 λ。结果保存为 common/<时间戳>/decision.mat，续跑时直接读取；
%      之后不再根据测试年结果改动。价值校准只用训练年（TruthStore 的固定策略回合缓存于 common/<时间戳>/calib_truth）。
lam = p.ctdf.lambda;
dec = struct('mode', p.ctdf.gpiMode, 'hold', 1, 'lambda', lam, 'truth', [], 'w0', w0, ...
    'reg', containers.Map('KeyType', 'char', 'ValueType', 'any'), 'safeZ', 0, 'baseId', ref.id);
if needM1
    t0 = tic;
    dec.truth = TruthStore(ctx, C.W, lib, yrTrain, seeds(1), fullfile(R0.dir, 'calib_truth'));
    fDec = fullfile(R0.dir, 'decision.mat');
    if resume && isfile(fDec)
        L = load(fDec, 'decSaved');
        dec.mode = L.decSaved.mode;
        dec.hold = L.decSaved.hold;
        dec.lambda = L.decSaved.lambda;
        decTable = L.decSaved.table;
        lamTable = L.decSaved.lamTable;
        if isfield(L.decSaved, 'safeZ'), dec.safeZ = L.decSaved.safeZ; end
        if isfield(L.decSaved, 'zTable') && strncmpi(dec.mode, 'central', 7)
            % 以已保存的 z 网格验证结果按保守选取规则确定 z（不重新评估验证回合）
            zT = L.decSaved.zTable;
            zNew = pickSafeZ(zT.safeZ, zT.score, getf(p.ctdf, 'safeZTol', 0.005));
            if zNew ~= dec.safeZ
                logMsg(R0.fid, '安全改进阈值按保守规则重选（验证准则在最优值 %.1f%% 以内取最大 z）：准则值 %s，z 由 %g 改为 %g。', ...
                    100 * getf(p.ctdf, 'safeZTol', 0.005), mat2str(zT.score', 4), dec.safeZ, zNew);
                dec.safeZ = zNew;
            end
        end
        logMsg(R0.fid, '决策规则（续跑，读取 decision.mat）：%s，保持 %d 天，λ = %.3g，安全改进阈值 z = %g。', dec.mode, ...
            dec.hold, dec.lambda, dec.safeZ);
    else
        specsV = makeEvalSpecs(p, yrVal, seeds(1), {'normal', 'drought'}, C.cNominal);
        epDec = fullfile(R0.dir, 'decision_episodes');
        modes = getf(p.ctdf, 'decisionModes', {p.ctdf.gpiMode});
        holds = getf(p.ctdf, 'holdGrid', 1);
        holds(holds <= 0) = C.Tl.H;
        holds = unique(holds, 'stable');
        % 选择准则 p.ctdf.selectCriterion：'mean'（验证回合平均成本）或 'worstRegime'（各工况平均成本相对 M0 的比值取最大，
        % 即在常规与干旱两类工况中表现较差的一类上不劣于、并尽量优于固定策略；稳健选择，测试前确定）
        crit = getf(p.ctdf, 'selectCriterion', 'mean');
        [~, T0v] = evalEpisodes(ctx, C.W, specsV, makeController('fixed', 'M0', w0), [], epDec);
        regs = unique(T0v.scenario, 'stable');
        base0 = cellfun(@(r) mean(T0v.cost(strcmp(T0v.scenario, r))), regs);
        scoreOf = @(T) decisionScore(T, regs, base0, crit);
        logMsg(R0.fid, '决策规则选择准则 %s；M0 验证成本 %s 元（%s）。', crit, mat2str(base0', 4), strjoin(regs', '、'));
        rowsD = {};
        for mi = 1:numel(modes)
            for hd = holds(:)'
                dk = dec;
                dk.mode = modes{mi};
                dk.hold = hd;
                dk.lambda = 0;
                ctrl = makeDecisionController(dk, sprintf('dec_%s_h%d_l0', modes{mi}, hd), models.M1{1}, lib, ...
                    struct('K', p.ctdf.K, 'key', 'M1_s1'));
                [~, T] = evalEpisodes(ctx, C.W, specsV, ctrl, [], epDec);
                rowsD(end + 1, :) = {modes{mi}, hd, mean(T.cost), mean(T.shedMWh), mean(T.eventF, 'omitnan'), ...
                    mean(T.decTime), scoreOf(T)}; %#ok<AGROW>
                logMsg(R0.fid, '决策规则候选：%s，保持 %d 天，λ = 0：验证成本 %.4g 元，失负荷 %.4g MWh，事件断供 %.3f，决策 %.2f s/日，准则值 %.4f。', ...
                    modes{mi}, hd, rowsD{end, 3}, rowsD{end, 4}, rowsD{end, 5}, rowsD{end, 6}, rowsD{end, 7});
            end
        end
        decTable = cell2table(rowsD, 'VariableNames', {'mode', 'hold', 'cost', 'shedMWh', 'eventF', 'decTime', 'score'});
        [best, ib] = min(decTable.score);
        isDist = strcmpi(decTable.mode, 'distributed');
        pick = ib;
        if any(isDist)
            [bd, idd] = min(decTable.score(isDist));
            if bd <= (1 + getf(p.ctdf, 'distTol', 0)) * best
                fd = find(isDist);
                pick = fd(idd);
            end
        end
        dec.mode = decTable.mode{pick};
        dec.hold = decTable.hold(pick);
        grid = p.ctdf.lambdaGrid;
        vc = nan(size(grid));
        vs = nan(size(grid));
        for g = 1:numel(grid)
            if grid(g) == 0
                vc(g) = decTable.cost(pick);
                vs(g) = decTable.score(pick);
                continue;
            end
            dk = dec;
            dk.lambda = grid(g);
            ctrl = makeDecisionController(dk, sprintf('dec_%s_h%d_l%g', dec.mode, dec.hold, grid(g)), models.M1{1}, lib, ...
                struct('K', p.ctdf.K, 'key', 'M1_s1'));
            [~, T] = evalEpisodes(ctx, C.W, specsV, ctrl, [], epDec);
            vc(g) = mean(T.cost);
            vs(g) = scoreOf(T);
        end
        [~, bl] = min(vs);
        dec.lambda = grid(bl);
        lamTable = table(grid(:), vc(:), vs(:), 'VariableNames', {'lambda', 'cost', 'score'});
        % 安全改进阈值 z（以 M0 为锚，只在集中式下生效）：z = 0 即上面已评估的配置，其余取值在同一验证回合上比较
        zGrid = getf(p.ctdf, 'safeZGrid', 0);
        zc = nan(size(zGrid));
        zs = nan(size(zGrid));
        for g = 1:numel(zGrid)
            if zGrid(g) == 0 || ~strncmpi(dec.mode, 'central', 7)
                zc(g) = vc(bl);
                zs(g) = vs(bl);
                continue;
            end
            dk = dec;
            dk.safeZ = zGrid(g);
            ctrl = makeDecisionController(dk, sprintf('dec_%s_h%d_l%g_z%g', dec.mode, dec.hold, dec.lambda, zGrid(g)), ...
                models.M1{1}, lib, struct('K', p.ctdf.K, 'key', 'M1_s1'));
            [~, T] = evalEpisodes(ctx, C.W, specsV, ctrl, [], epDec);
            zc(g) = mean(T.cost);
            zs(g) = scoreOf(T);
        end
        % 保守选取：验证准则不劣于最优值 (1 + safeZTol) 倍的取值中取最大 z（与设计点的一倍标准误规则同一思路，偏向固定策略锚）
        dec.safeZ = pickSafeZ(zGrid, zs, getf(p.ctdf, 'safeZTol', 0.005));
        zTable = table(zGrid(:), zc(:), zs(:), 'VariableNames', {'safeZ', 'cost', 'score'});
        logMsg(R0.fid, '安全改进阈值：z 网格 %s，验证成本 %s，准则值 %s，选取 z = %g。', mat2str(zGrid), mat2str(zc, 4), ...
            mat2str(zs, 4), dec.safeZ);
        decSaved = struct('mode', dec.mode, 'hold', dec.hold, 'lambda', dec.lambda, 'table', decTable, 'lamTable', lamTable, ...
            'safeZ', dec.safeZ, 'zTable', zTable);
        saveAtomic(fDec, struct('decSaved', decSaved));
        writetable(decTable, fullfile(R0.dir, 'decision_selection.csv'), 'Encoding', 'UTF-8');
        logMsg(R0.fid, '决策规则选定：%s，保持 %d 天；λ 网格 %s，验证成本 %s，准则值 %s，选取 λ = %.3g；用时 %.1f s。', ...
            dec.mode, dec.hold, mat2str(grid), mat2str(vc, 4), mat2str(vs, 4), dec.lambda, toc(t0));
    end
    lam = dec.lambda;
    results.decision = struct('mode', dec.mode, 'hold', dec.hold, 'lambda', dec.lambda, 'table', decTable, 'lamTable', lamTable, ...
        'safeZ', dec.safeZ);
    results.lambda = struct('grid', lamTable.lambda', 'valCost', lamTable.cost', 'lambda', lam);
end
C.decision = dec;

% ================= M2 随机 MPC（验证集调参）=================
% MPC 设置（含调参结果）保存为 common/<时间戳>/mpc.mat；续跑时直接读取（MPC 调参不使用逐回合缓存）
mpc = [];
if needMPC
    fMpc = fullfile(R0.dir, 'mpc.mat');
    if resume && isfile(fMpc)
        L = load(fMpc, 'mpc');
        mpc = L.mpc;
        logMsg(R0.fid, 'M2 随机 MPC 设置（续跑，读取 mpc.mat）：S = %d，H_MPC = %d d。', mpc.S, mpc.Hm);
    else
        mpc = mpcSetup(ctx, C.W, yrTrain);
        if p.mpc.tune
            t0 = tic;
            best = inf;
            specs = makeEvalSpecs(p, yrVal, seeds(1), {'normal'}, C.cNominal);
            ivGrid = getf(p.mpc, 'tuneIronValue', getf(p.mpc, 'ironValueMult', 1));
            netGrid = getf(p.mpc, 'tuneTerminalNet', getf(p.mpc, 'terminalNet', false));
            for sS = p.mpc.tuneS
                for hf = p.mpc.tuneHorizon
                    for iv = ivGrid(:)'
                        for tn = logical(netGrid(:)')
                            mc = mpcSetup(ctx, C.W, yrTrain, struct('S', sS, 'horizonFactor', hf, 'ironValueMult', iv, ...
                                'terminalNet', tn));
                            [~, T] = evalEpisodes(ctx, C.W, specs, makeController('mpc', 'M2', mc));
                            logMsg(R0.fid, ['M2 验证集调参候选：S = %d，H_MPC = %d d，储量价值倍数 %g，终端扣除物流成本 %d：', ...
                                '平均成本 %.4g 元，失负荷 %.4g MWh，弃电率 %.3f。'], sS, mc.Hm, iv, tn, mean(T.cost), ...
                                mean(T.shedMWh), mean(T.curRate));
                            if mean(T.cost) < best
                                best = mean(T.cost);
                                mpc = mc;
                            end
                        end
                    end
                end
            end
            logMsg(R0.fid, 'M2 验证集调参：S = %d，H_MPC = %d d，储量价值倍数 %g，终端扣除物流成本 %d，用时 %.1f s。', mpc.S, ...
                mpc.Hm, getf(mpc, 'ironValueMult', 1), getf(mpc, 'terminalNet', false), toc(t0));
        end
        saveAtomic(fMpc, struct('mpc', mpc));
    end
    results.mpc = struct('S', mpc.S, 'Hm', mpc.Hm);
end

% ================= 方法工厂 =================
fac.M0 = @(s) makeController('fixed', 'M0', w0);
if needM1
    gF = models.M1{1}.gammaFinal;
    % 学习类方法统一使用验证集选定的决策规则（公共随机数；见“决策规则选定”块与 makeDecisionController）
    fac.M1 = @(s) makeDecisionController(dec, 'M1', models.M1{sIdx(s)}, lib, struct('K', p.ctdf.K, ...
        'key', sprintf('M1_s%d', s)));
    fac.M3 = @(s) makeDecisionController(dec, 'M3', models.M3{sIdx(s)}, lib, struct('K', p.exp.stepwiseK, ...
        'riskMode', 'stepwise', 'gammaEval', gF, 'Tcap', p.exp.stepwiseTcapCtrl, 'key', sprintf('M3_s%d', s)));
    fac.M4 = @(s) makeDecisionController(dec, 'M4', models.M4{sIdx(s)}, lib, struct('K', p.ctdf.K, ...
        'key', sprintf('M4_s%d', s)));
end
ctxByMethod = struct();
if ~isempty(mpc)
    fac.M2 = @(s) makeController('mpc', 'M2', mpc);
    if any(strcmp(requestedMethods, 'M2o'))
        % 完全预见 MPC（上界对照，只用于说明信息价值与 MPC 模型本身的上限）：同一 LP，单场景，
        % 预测器改为完全预见（p.forecast.mode = 'oracle'，只作用于该方法的回合），前 Hf 天全部为真实日电量
        mpcO = mpc;
        mpcO.S = 1;
        mpcO.Hf = max(1, min(mpc.Hm - 1, p.forecast.Hmax - 1));
        ctxO = ctx;
        ctxO.p.forecast.mode = 'oracle';
        fac.M2o = @(s) makeController('mpc', 'M2o', mpcO);
        ctxByMethod.M2o = ctxO;
    end
end

% ================= 决策层诊断（只用验证年份；opts.only = {'diagGPI'}）=================
if want('diagGPI')
    R = newRunDir(root, 'diagGPI', stamp, p, struct('common', R0.dir, 'lambda', lam));
    t0 = tic;
    dg = runDiagGPI(C, models.M1{1}, lib, w0, lam, yrVal, seeds(1), runCacheDir(R.dir, 'episodes', true));
    save(fullfile(R.dir, 'results.mat'), 'dg');
    writetable(dg.closedSummary, fullfile(R.dir, 'diag_closed_summary.csv'), 'Encoding', 'UTF-8');
    writetable(dg.closed, fullfile(R.dir, 'diag_closed_episodes.csv'), 'Encoding', 'UTF-8');
    writetable(dg.probe, fullfile(R.dir, 'diag_probe.csv'), 'Encoding', 'UTF-8');
    for v = 1:height(dg.closedSummary)
        r = dg.closedSummary(v, :);
        logMsg(R.fid, '诊断 A %s：成本 %.4g 元，失负荷 %.4g MWh，事件断供 %.3f，pF %.3f，弃电率 %.3f，决策 %.2f s/日。', ...
            r.variant{1}, r.cost, r.shedMWh, r.eventF, r.pF, r.curRate, r.decTime);
    end
    ps = dg.probeSummary;
    logMsg(R.fid, ['诊断 B（%d 个状态，%d 个候选，M0 为第 %g 个）：Q 排序 Spearman 中位数 %.2f，候选间离散度/抽样标准误 %.2f，', ...
        'M0 价值第一的比例 %.2f、名次中位数 %g；R 候选间极差中位数 %.3f，R 最小值中位数 %.3f。用时 %.1f s。'], ...
        ps.nStates, ps.nCand, ps.iM0, ps.medianSpearman, ps.medianSNR, ps.fracM0Top1, ps.medianRankM0, ...
        ps.medianRrange, ps.medianRmin, toc(t0));
    fclose(R.fid);
    results.diagGPI = dg;
end
if want('diagGPI2')
    R = newRunDir(root, 'diagGPI2', stamp, p, struct('common', R0.dir, 'lambda', lam));
    t0 = tic;
    dg2 = runDiagGPI2(C, models.M1{1}, lib, ref, lam, yrVal, seeds(1), runCacheDir(R.dir, 'episodes', true));
    save(fullfile(R.dir, 'results.mat'), 'dg2');
    writetable(dg2.closedSummary, fullfile(R.dir, 'diag2_closed_summary.csv'), 'Encoding', 'UTF-8');
    writetable(dg2.probe, fullfile(R.dir, 'diag2_probe.csv'), 'Encoding', 'UTF-8');
    writetable(dg2.meanQ, fullfile(R.dir, 'diag2_meanQ.csv'), 'Encoding', 'UTF-8');
    for v = 1:height(dg2.closedSummary)
        r = dg2.closedSummary(v, :);
        logMsg(R.fid, '诊断 A2 %s：成本 %.4g 元，失负荷 %.4g MWh，事件断供 %.3f，pF %.3f，弃电率 %.3f，决策 %.2f s/日。', ...
            r.variant{1}, r.cost, r.shedMWh, r.eventF, r.pF, r.curRate, r.decTime);
    end
    ps = dg2.probeSummary;
    logMsg(R.fid, ['诊断 B2（%d 个状态，%d 个候选）：CRN 下 Q 排序 Spearman 中位数 %.2f，离散度/标准误 %.2f，M0 名次中位数 %g；', ...
        '平均 Q 与验证年实际成本排序的 Spearman %.2f，M0 按平均 Q 排第 %g。用时 %.1f s。'], ps.nStates, ps.nCand, ...
        ps.medianSpearmanCRN, ps.medianSNRCRN, ps.medianRankM0, ps.spearmanMeanQvsTrue, ps.rankM0byMeanQ, toc(t0));
    fclose(R.fid);
    results.diagGPI2 = dg2;
end
if want('diagGPI3')
    R = newRunDir(root, 'diagGPI3', stamp, p, struct('common', R0.dir, 'lambda', lam));
    t0 = tic;
    dg3 = runDiagGPI3(C, models.M1{1}, lib, ref, lam, yrTrain, yrVal, seeds(1), runCacheDir(R.dir, 'episodes', true));
    save(fullfile(R.dir, 'results.mat'), 'dg3');
    writetable(dg3.closedSummary, fullfile(R.dir, 'diag3_closed_summary.csv'), 'Encoding', 'UTF-8');
    writetable(dg3.calib, fullfile(R.dir, 'diag3_calib.csv'), 'Encoding', 'UTF-8');
    for v = 1:height(dg3.closedSummary)
        r = dg3.closedSummary(v, :);
        logMsg(R.fid, '诊断 3 %s：成本 %.4g 元，失负荷 %.4g MWh，事件断供 %.3f，pF %.3f，弃电率 %.3f，决策 %.2f s/日。', ...
            r.variant{1}, r.cost, r.shedMWh, r.eventF, r.pF, r.curRate, r.decTime);
    end
    cs = dg3.calibSummary;
    logMsg(R.fid, ['诊断 3 校准（%d 个训练年状态）：训练年与验证年实测排序 Spearman %.2f；校准前模型平均价值与训练年实测排序 ', ...
        'Spearman %.2f；M0 在训练年实测中排第 %g；价值离散度 实测 %.3g、模型 %.3g。用时 %.1f s。'], cs.nStates, ...
        cs.spearmanTrainVsVal, cs.spearmanQmodVsTrain, cs.rankM0Train, cs.scaleQtrue, cs.scaleQmod, toc(t0));
    fclose(R.fid);
    results.diagGPI3 = dg3;
end
if want('diagGPI4')
    R = newRunDir(root, 'diagGPI4', stamp, p, struct('common', R0.dir));
    t0 = tic;
    dg4 = runDiagGPI4(C, models.M1{1}, lib, ref, yrTrain, seeds(1), runCacheDir(fullfile(root, 'diagGPI3', stamp), 'episodes', true));
    save(fullfile(R.dir, 'results.mat'), 'dg4');
    writetable(dg4.components, fullfile(R.dir, 'diag4_components.csv'), 'Encoding', 'UTF-8');
    writetable(dg4.truth, fullfile(R.dir, 'diag4_truth.csv'), 'Encoding', 'UTF-8');
    writetable(dg4.model, fullfile(R.dir, 'diag4_model.csv'), 'Encoding', 'UTF-8');
    for k = 1:height(dg4.components)
        r = dg4.components(k, :);
        logMsg(R.fid, '诊断 4 %s：Spearman %.2f，离散度比（模型/实测）%.2f，水平比 %.2f，占实测成本离散度 %.2f，实测日均 %.4g。', ...
            r.component{1}, r.spearman, r.spreadRatio, r.levelRatio, r.shareOfTrueSpread, r.trueDailyMean);
    end
    hr = dg4.headroom;
    logMsg(R.fid, '诊断 4 改进余地：按年事后最优候选相对 M0 节省 %.2f%%（M0 年均 %.4g 元，事后最优 %.4g 元），M0 恰为当年最优的年份占 %.2f（%d 年）。', ...
        hr.savingPct, hr.M0mean, hr.oracleYearMean, hr.fracYearsM0Best, hr.nYears);
    logMsg(R.fid, '诊断 4 完成（%d 个训练年状态），用时 %.1f s。', dg4.nStates, toc(t0));
    fclose(R.fid);
    results.diagGPI4 = dg4;
end
if want('diagShed')
    R = newRunDir(root, 'diagShed', stamp, p, struct('common', R0.dir));
    t0 = tic;
    ds5 = runDiagShed(C, ref, [yrTrain(:); yrVal(:)]', seeds(1), runCacheDir(R.dir, 'episodes', true));
    save(fullfile(R.dir, 'results.mat'), 'ds5');
    writetable(ds5.byYear, fullfile(R.dir, 'diagShed_byYear.csv'), 'Encoding', 'UTF-8');
    q5 = ds5.summary;
    logMsg(R.fid, ['失负荷来源（%d 年）：改造电厂总出力 %.0f MW，备用电源 %.0f MW；年均负荷 %.2f TWh，M0 年均失负荷 %.3f TWh', ...
        '（占负荷 %.2f%%）；容量下界占实际失负荷 %.1f%%；峰值缺口 均值 %.0f MW、最大 %.0f MW；电厂必需电量 %.2f TWh，富余绿电 %.2f TWh；用时 %.1f s。'], ...
        q5.years, q5.plantPmaxMW, q5.backupPmaxMW, q5.meanLoadTWh, q5.meanShedM0TWh, q5.shedShareOfLoadPct, ...
        q5.capShedShareOfShedPct, q5.meanPeakDeficitMW, q5.maxPeakDeficitMW, q5.mustTWh, q5.surplusTWh, toc(t0));
    s5 = ds5.split;
    logMsg(R.fid, ['失负荷拆分：发生在电厂缺铁日的份额 %.1f%%，可归因于缺铁的电量 %.1f%%；年均失负荷日 %.1f 天，其中无缺铁的 %.1f 天；', ...
        '失负荷日的失负荷占当日电厂必需电量 %.1f%%；必需电量为零之日的失负荷份额 %.1f%%。'], s5.shedOnIronShortDaysPct, ...
        s5.ironAttributablePct, s5.shedDaysPerYear, s5.shedDaysWithoutIronShortPerYear, s5.shedToMustOnShedDaysPct, ...
        s5.shedOnZeroMustDaysPct);
    fclose(R.fid);
    results.diagShed = ds5;
end
if want('diagMPC')
    % 改进空间检查：随机 MPC（不受策略库限制）与 M0 在验证年 × 常规工况 × 名义质量上的对比
    R = newRunDir(root, 'diagMPC', stamp, p, struct('common', R0.dir));
    t0 = tic;
    specsV = makeEvalSpecs(p, yrVal, seeds(1), {'normal'}, C.cNominal);
    epD = runCacheDir(R.dir, 'episodes', true);
    [~, T0] = evalEpisodes(ctx, C.W, specsV, makeController('fixed', 'M0', w0), [], epD);
    [~, T2] = evalEpisodes(ctx, C.W, specsV, makeController('mpc', 'M2', mpc), [], epD);
    vm = {'cost', 'shedMWh', 'eventF', 'pF', 'curRate'};
    for v = {'M0', 'M2'}
        if strcmp(v{1}, 'M0'), Tm = T0; else, Tm = T2; end
        logMsg(R.fid, '改进空间检查 %s：成本 %.4g 元，失负荷 %.4g MWh，事件断供 %.3f，pF %.3f，弃电率 %.3f。', v{1}, ...
            mean(Tm.(vm{1})), mean(Tm.(vm{2})), mean(Tm.(vm{3}), 'omitnan'), mean(Tm.(vm{4})), mean(Tm.(vm{5})));
    end
    logMsg(R.fid, '改进空间检查完成（MPC：S = %d，H = %d d），用时 %.1f min。', mpc.S, mpc.Hm, toc(t0) / 60);
    T0.variant = repmat({'M0'}, height(T0), 1);
    T2.variant = repmat({'M2'}, height(T2), 1);
    writetable([T0; T2], fullfile(R.dir, 'diagMPC_episodes.csv'), 'Encoding', 'UTF-8');
    fclose(R.fid);
    results.diagMPC = struct('M0', T0, 'M2', T2);
end
if want('diagMass')
    R = newRunDir(root, 'diagMass', stamp, p, struct('common', R0.dir));
    t0 = tic;
    dm = runDiagMass(C, ref, yrVal, seeds(1), getf(opts, 'massPMult', []), getf(opts, 'massC', []));
    save(fullfile(R.dir, 'results.mat'), 'dm');
    writetable(dm.share, fullfile(R.dir, 'diagMass_share.csv'), 'Encoding', 'UTF-8', 'WriteRowNames', true);
    sm = dm.summary;
    logMsg(R.fid, ['质量分布（%d 年，失负荷日 %d）：总质量 %.0f kt；还原能力 %.0f t/d，实际还原 均值 %.0f t/d、失负荷日 %.0f t/d；', ...
        '平均通量 %.0f t/d，δ^D %.0f t/d；料仓容量 电厂 %.0f kt、枢纽 %.0f kt、还原站 %.0f kt；用时 %.1f s。'], sm.years, sm.shedDays, ...
        sm.totalKt, sm.rhoMaxSumTpd, sm.rhoActualMeanTpd, sm.rhoActualOnShedDaysTpd, sm.PhiTpd, sm.deltaDTpd, ...
        sm.plantCapFeKt, sm.hubCapFeKt, sm.stationCapFeKt, toc(t0));
    logMsg(R.fid, '  参考策略：%s；功率倍数 %s，循环质量 %s t。', dm.refName, mat2str(getf(opts, 'massPMult', 1)), mat2str(getf(opts, 'massC', C.cNominal)));
    nmR = dm.share.Properties.RowNames;
    for k = 1:numel(nmR)
        logMsg(R.fid, '  %s：全部日 %.1f%%，失负荷日 %.1f%%，失负荷前 3 日 %.1f%%，平均 %.0f kt。', nmR{k}, ...
            100 * dm.share.allDays(k), 100 * dm.share.shedDays(k), 100 * dm.share.pre3Days(k), dm.share.meanKt(k));
    end
    fclose(R.fid);
    results.diagMass = dm;
end
if want('diagSizing')
    R = newRunDir(root, 'diagSizing', stamp, p, struct('common', R0.dir));
    t0 = tic;
    dz = runDiagSizing(C, yrVal, seeds(1), getf(opts, 'sizingMults', [1, 1.5, 2, 3]), fullfile(R.dir, 'episodes'), ...
        getf(opts, 'sizingCs', []));
    save(fullfile(R.dir, 'results.mat'), 'dz');
    writetable(dz.table, fullfile(R.dir, 'diagSizing.csv'), 'Encoding', 'UTF-8');
    for k = 1:height(dz.table)
        r = dz.table(k, :);
        logMsg(R.fid, ['还原功率 ×%g（%.0f MW，%.0f t/d）、循环质量 %.0f kt：最优候选成本 %.4g 元，失负荷 %.4g MWh，事件断供 %.3f，pF %.3f，', ...
            '弃电率 %.3f，锈阻塞 %.4g MWh；全部候选平均成本 %.4g 元、失负荷 %.4g MWh。'], r.mult, r.pRedMW, r.rhoMaxTpd, r.cKt, ...
            r.bestCost, r.bestShedMWh, r.bestEventF, r.bestPF, r.bestCurRate, r.bestRustBlockMWh, r.meanCost, r.meanShedMWh);
    end
    logMsg(R.fid, '还原功率规模扫描完成，用时 %.1f min。', toc(t0) / 60);
    fclose(R.fid);
    results.diagSizing = dz;
end
if all(ismember(lower(only), {'diaggpi', 'diaggpi2', 'diaggpi3', 'diaggpi4', 'diagshed', 'diagmpc', 'diagmass', 'diagsizing'}))
    fclose(R0.fid);
    return;                                      % 只做诊断时不改写 results_all.mat 与表格导出
end
mk = @(names) struct('name', names, 'factory', cellfun(@(n) fac.(n), names, 'UniformOutput', false));

% ================= E2 临界循环质量扫描 =================
% 续跑模式下，已有 results.mat 的实验块直接读取结果（loadDone），不重算、不重新作图；E1/E2/E3/E5 的已完成评估回合
% 缓存在实验目录 episodes/，E6 的已完成变体缓存在 variants/（runCacheDir；非续跑时先清空同名旧目录）。
if want('E2')
    [done, e2] = loadDone(resume, root, 'E2', stamp, 'e2', R0.fid);
    if ~done
        R = newRunDir(root, 'E2', stamp, p, struct('common', R0.dir, 'seeds', seeds));
        t0 = tic;
        names2 = intersect(p.exp.e2Methods, fieldnames(fac), 'stable');
        ex2 = [];
        if isfield(p.exp, 'e2Extra') && ~isempty(p.exp.e2Extra)
            for q = 1:numel(p.exp.e2Extra)
                if isfield(fac, p.exp.e2Extra(q).name)
                    ex2 = [ex2, struct('name', p.exp.e2Extra(q).name, 'factory', fac.(p.exp.e2Extra(q).name), ...
                        'cList', p.exp.e2Extra(q).c)]; %#ok<AGROW>
                end
            end
        end
        e2 = runE2CriticalMass(C, mk(names2), yrTest, seeds, runCacheDir(R.dir, 'episodes', resume), ex2);
        for m = 1:height(e2.designOpt)
            d2 = e2.designOpt(m, :);
            logMsg(R.fid, 'E2 %s 最优配置（运行成本 + 循环铁资金成本）：质量 %.0f kt，年化 %.4g 元（运行 %.4g，铁资金 %.4g）。', ...
                d2.method{1}, d2.cOpt / 1e3, d2.totalAnnual, d2.opAnnual, d2.ironCapitalAnnual);
        end
        if ~isempty(e2.extra.paired)
            for m = 1:height(e2.extra.paired)
                q2 = e2.extra.paired(m, :);
                logMsg(R.fid, 'E2 %s 对 %s（质量 %.0f kt，%d 对）：成本 %.4g 对 %.4g 元，差 %+.2f%%，配对 t 检验 p = %.3g。', ...
                    q2.method{1}, q2.ref{1}, q2.c / 1e3, q2.n, q2.cost, q2.refCost, 100 * q2.dRel, q2.pValue);
            end
            writetable(e2.extra.paired, fullfile(R.dir, 'E2_extra_paired.csv'), 'Encoding', 'UTF-8');
        end
        writetable(e2.designOpt, fullfile(R.dir, 'E2_designOpt.csv'), 'Encoding', 'UTF-8');
        for m = 1:numel(e2.knee)
            k = e2.knee(m);
            logMsg(R.fid, 'E2 %s：拐点（两段线性）%.0f t [%.0f, %.0f]，（最大曲率）%.0f t [%.0f, %.0f]；与几何尾计算值的偏差 %.1f%% / %.1f%%。', ...
                k.method, k.twoSeg, k.twoSegCI(1), k.twoSegCI(2), k.curv, k.curvCI(1), k.curvCI(2), 100 * k.devTwoSeg, ...
                100 * k.devCurv);
        end
        for m = 1:numel(e2.local)
            logMsg(R.fid, 'E2 %s：c ≥ M_crit 时局部断供 %d 次、局部锈裕度为负 %d 次、局部锈阻塞 %d 次（%d 个回合）。', ...
                e2.local(m).method, e2.local(m).localFe, e2.local(m).localOx, e2.local(m).localRB, e2.local(m).episodes);
        end
        save(fullfile(R.dir, 'results.mat'), 'e2');
        writetable(e2.summary, fullfile(R.dir, 'E2_summary.csv'), 'Encoding', 'UTF-8');
        F05_criticalRidges(e2, S, fullfile(R.dir, 'F05_criticalMass'));
        logMsg(R.fid, 'E2 完成，用时 %.1f s。', toc(t0));
        fclose(R.fid);
    end
    results.e2 = e2;
end

% ================= E3 常规与极端工况对比 =================
if want('E3')
    [done, e3] = loadDone(resume, root, 'E3', stamp, 'e3', R0.fid);
    if ~done
        R = newRunDir(root, 'E3', stamp, p, struct('common', R0.dir, 'seeds', seeds, 'lambda', lam));
        t0 = tic;
        names = intersect(p.exp.e3Methods, fieldnames(fac), 'stable');
        m3 = mk(names);
        [m3.ctx] = deal([]);
        for m = 1:numel(m3)
            if isfield(ctxByMethod, m3(m).name)
                m3(m).ctx = ctxByMethod.(m3(m).name);
            end
            m3(m).seeds = seeds;
            if isfield(p.exp.e3MethodSeeds, m3(m).name)
                m3(m).seeds = intersect(seeds, p.exp.e3MethodSeeds.(m3(m).name), 'stable');
            end
        end
        e3 = runE3Comparison(C, m3, yrTest, seeds, runCacheDir(R.dir, 'episodes', resume));
        save(fullfile(R.dir, 'results.mat'), 'e3');
        writetable(e3.summary, fullfile(R.dir, 'E3_summary.csv'), 'Encoding', 'UTF-8');
        writetable(e3.paired, fullfile(R.dir, 'E3_paired.csv'), 'Encoding', 'UTF-8');
        writetable(e3.episodes,fullfile(R.dir,'E3_episodes.csv'),'Encoding','UTF-8');
        F07_parallelMetrics(e3, S, fullfile(R.dir, 'F07_parallelMetrics'));
        F08_dailyCostBox(e3, S, fullfile(R.dir, 'F08_dailyCost'));
        F09_droughtWaterfall(e3, p, S, fullfile(R.dir, 'F09_droughtWaterfall'));
        F13_policyHexbin(e3, S, fullfile(R.dir, 'F13_policyResponse'));
        F16_corrMatrix(e3, S, fullfile(R.dir, 'F16_corrMatrix'));
        F01_corridorMap(flowsByYear(e3, yrTest), p, S, fullfile(R.dir, 'F01_corridorMap'));
        logMsg(R.fid, 'E3 完成（方法 %s），用时 %.1f s。', strjoin(names, '、'), toc(t0));
        fclose(R.fid);
    end
    results.e3 = e3;
end

% ================= E4 长时域预测精度 =================
if want('E4')
    [done, e4] = loadDone(resume, root, 'E4', stamp, 'e4', R0.fid);
    if ~done
        R = newRunDir(root, 'E4', stamp, p, struct('common', R0.dir, 'seeds', seeds));
        t0 = tic;
        tabs = cell(1, numel(seeds));
        rawTabs = cell(1,numel(seeds));
        for si = 1:numel(seeds)
            e4s = runE4Horizon(C, gtTest, struct('M1', models.M1{si}, 'M3', models.M3{si}, 'M4', models.M4{si}), ...
                seeds(si));
            e4s.table.Seed = repmat(seeds(si), height(e4s.table), 1);
            tabs{si} = e4s.table;
            rawTabs{si}=e4s.raw;
            if si == 1
                e4 = e4s;
            end
        end
        e4.allSeeds = vertcat(tabs{:});
        e4.raw=vertcat(rawTabs{:});
        [e4.table,e4.metadata]=summarizePredictionAccuracy(e4.raw);
        save(fullfile(R.dir, 'results.mat'), 'e4');
        writetable(e4.table, fullfile(R.dir, 'E4_table.csv'), 'Encoding', 'UTF-8');
        writetable(e4.allSeeds,fullfile(R.dir,'E4_per_seed.csv'),'Encoding','UTF-8');
        writetable(e4.raw,fullfile(R.dir,'E4_per_state.csv'),'Encoding','UTF-8');
        F10_horizonBubbles(e4, S, fullfile(R.dir, 'F10_horizonAccuracy'));
        for q = 1:height(e4.table)
            t4 = e4.table(q, :);
            rk = NaN;
            if ismember('RiskErr', t4.Properties.VariableNames), rk = t4.RiskErr; end
            logMsg(R.fid, 'E4 %s γ = %.2f：分布距离 %.3f [%.3f, %.3f]，价值误差 %.3f，守恒误差 %.2e，含负库存样本 %.1f%%，断供概率误差 %.3f。', ...
                t4.Method{1}, t4.gamma, t4.W1, t4.W1lo, t4.W1hi, t4.ValueErr, t4.ConsErr, 100 * t4.NegFrac, rk);
        end
        logMsg(R.fid, 'E4 完成，用时 %.1f s（图 F10 先在天气年内汇总状态和种子，再按年份计算区间）。', toc(t0));
        fclose(R.fid);
    end
    results.e4 = e4;
end

% ================= E5 各要素贡献 =================
if want('E5')
    [done, e5] = loadDone(resume, root, 'E5', stamp, 'e5', R0.fid);
    if ~done
        R = newRunDir(root, 'E5', stamp, p, struct('common', R0.dir, 'seeds', seeds, 'lambda', lam));
        t0 = tic;
        abl = struct('name', {'full', 'noNull', 'noTerminal', 'gauss', 'noCurr'}, ...
            'label', {'CTDF-WM', '速度投影', '终端投影（训练相同，仅推理不同）', 'Dirichlet 源', '时域课程'}, ...
            'factory', {@(s) setLam(models.M1{sIdx(s)}, lam), @(s) setLam(models.noNull{sIdx(s)}, lam), ...
            @(s) setLam(models.M1{sIdx(s)}, lam), @(s) setLam(models.gauss{sIdx(s)}, lam), ...
            @(s) setLam(models.noCurr{sIdx(s)}, lam)}, ...
            'terminalProj', {[], [], false, [], []});
        e5 = runE5Elements(C, gtTest, abl, lib, yrTest, ablSeeds, runCacheDir(R.dir, 'episodes', resume));
        save(fullfile(R.dir, 'results.mat'), 'e5');
        writetable(e5.raw, fullfile(R.dir, 'E5_raw.csv'), 'Encoding', 'UTF-8');
        writetable(e5.predictionRaw,fullfile(R.dir,'E5_prediction_per_state.csv'),'Encoding','UTF-8');
        F11_elementGain(e5, S, fullfile(R.dir, 'F11_elements'));
        logMsg(R.fid, 'E5 完成，用时 %.1f s。', toc(t0));
        fclose(R.fid);
    end
    results.e5 = e5;
end

% ================= 守恒与模型性质检查（补充表 4）=================
if want('checks')
    [done, vp] = loadDone(resume, root, 'checks', stamp, 'vp', R0.fid);
    if ~done
        R = newRunDir(root, 'checks', stamp, p, struct('common', R0.dir));
        t0 = tic;
        vp = checkModelProperties(models.M1{1}, ctx, lib, ds, gtTest, th);
        save(fullfile(R.dir, 'results.mat'), 'vp');
        ps = vp.table.Pass;
        if iscell(ps)
            nFail = nnz(cellfun(@(v) isequal(v, false), ps));
            nUnknown = nnz(cellfun(@(v) isnumeric(v) && isscalar(v) && isnan(v), ps));
        else
            nFail = nnz(ps == 0);
            nUnknown = nnz(isnan(ps));
        end
        logMsg(R.fid, '补充表 4 检查完成，用时 %.1f s；未满足项 %d，未计算项 %d。', toc(t0), nFail, nUnknown);
        fclose(R.fid);
    end
    results.vp = vp;
end

% ================= E1 改造与退役 =================
if want('E1')
    [done, e1] = loadDone(resume, root, 'E1', stamp, 'e1', R0.fid);
    if ~done
        R = newRunDir(root, 'E1', stamp, p, struct('common', R0.dir, 'seeds', seeds, 'method', p.exp.e1Method));
        t0 = tic;
        if ~isfield(fac, p.exp.e1Method)
            error('runExperiments:e1Method', 'E1 指定的方法 %s 不可用。', p.exp.e1Method);
        end
        o1 = struct('epDir', runCacheDir(R.dir, 'episodes', resume), 'altType', true);
        if isfield(results, 'e2') && ~isempty(results.e2)
            o1.e2 = results.e2;                      % 可靠性—保留价值曲线（E2 各质量点）
        end
        e1 = runE1Retirement(C, fac.(p.exp.e1Method), yrTest, seeds, o1);
        save(fullfile(R.dir, 'results.mat'), 'e1');
        writetable(e1.res.costs, fullfile(R.dir, 'E1_costs.csv'), 'Encoding', 'UTF-8');
        F17_retireHeatmap(e1, S, fullfile(R.dir, 'F17_retirement'));
        logMsg(R.fid, 'E1（%s）：替代功率 %.0f MW，保留资产价值 %.3f 亿元（容量 %.3f，电量 %.3f），弃电率 %.2f%% → %.2f%%，匹配 = %d；用时 %.1f s。', ...
            p.exp.e1Method, e1.res.P, e1.res.RV / 1e8, e1.res.capValue / 1e8, e1.res.enValue / 1e8, ...
            100 * e1.res.curRateRet, 100 * e1.res.curRateRetro, e1.res.matched, toc(t0));
        logMsg(R.fid, 'E1 会计期：共同会计期 %.0f 年 %.3f 亿元；按电厂剩余寿命 %.3f 亿元。', ...
            e1.res.detail.Nrem, e1.res.RV / 1e8, e1.res.RVplant / 1e8);
        if isfield(e1, 'resAlts')
            for k = 1:numel(e1.resAlts)
                ra = e1.resAlts{k};
                logMsg(R.fid, 'E1 替代方案 %s：替代功率 %.0f MW，保留资产价值 %.3f 亿元，匹配 = %d。', ...
                    ra.type, ra.P, ra.RV / 1e8, ra.matched);
            end
        end
        if isfield(e1, 'acct')
            logE1Comprehensive(R.fid, e1.acct, R.dir);
        end
        if isfield(e1, 'resForesight')
            rf = e1.resForesight;
            logMsg(R.fid, ['E1 替代方案有限预见（滚动 %g 天，储能量价值 %.2f × 备用燃料与碳成本，评估期内选取）：替代功率 %.0f MW', ...
                '（完全预见 %.0f MW），保留资产价值 %.3f 亿元（完全预见 %.3f 亿元），匹配 = %d。'], rf.foresight.days, ...
                rf.foresight.vMult, rf.P, e1.res.P, rf.RV / 1e8, e1.res.RV / 1e8, rf.matched);
            if isfield(e1, 'acctForesight')
                logMsg(R.fid, 'E1 有限预见下的全面核算如下（口径与上文相同）。');
                logE1Comprehensive(R.fid, e1.acctForesight, []);
            end
        end
        if isfield(e1, 'curve') && ~isempty(e1.curve)
            writetable(e1.curve, fullfile(R.dir, 'E1_reliability_curve.csv'), 'Encoding', 'UTF-8');
            for q = 1:height(e1.curve)
                cq = e1.curve(q, :);
                logMsg(R.fid, ['E1 可靠性曲线：质量 %.0f kt，改造失负荷 %.3f%%，替代功率 %.0f MW，保留资产价值 %.2f 亿元', ...
                    '（核心 %.2f，核心 + 设计 2030 %.2f，全部 2030 %.2f），匹配 = %d。'], cq.c / 1e3, 100 * cq.eueShare, ...
                    cq.Prep, cq.RV / 1e8, cq.RVcore / 1e8, cq.RVdesign2030 / 1e8, cq.RVall2030 / 1e8, cq.matched);
            end
            F24_reliabilityValue(e1, S, fullfile(R.dir, 'F24_reliabilityValue'));
        end
        fclose(R.fid);
    end
    results.e1 = e1;
end

% ================= E6 敏感性 =================
if want('E6')
    [done, e6] = loadDone(resume, root, 'E6', stamp, 'e6', R0.fid);
    if ~done
        R = newRunDir(root, 'E6', stamp, p, struct('common', R0.dir, 'seeds', seeds, 'refId', ref.id));
        t0 = tic;
        e6 = runE6Sensitivity(p, C.W, ref.id, yrTest, seeds, runCacheDir(R.dir, 'variants', resume));
        save(fullfile(R.dir, 'results.mat'), 'e6');
        writetable(e6.tornado, fullfile(R.dir, 'E6_tornado.csv'), 'Encoding', 'UTF-8');
        F12_sensSurface(e6, S, fullfile(R.dir, 'F12_sensSurface'));
        F14_breakeven(e6, p, S, fullfile(R.dir, 'F14_breakeven'));
        F18_tornadoHeatmap(e6, S, fullfile(R.dir, 'F18_tornado'));
        logMsg(R.fid, 'E6 完成：盈亏平衡运距 铁路 %.0f km、水运 %.0f km；用时 %.1f s。', e6.breakeven.dRail, ...
            e6.breakeven.dWater, toc(t0));
        if isfield(e6.breakeven, 'firm')
            bf = e6.breakeven.firm;
            logMsg(R.fid, ['E6 季节性可靠供电口径（特高压按利用 %g h 回收投资，等效 %.3f 元/kWh；铁锈回程运价 × %.2f）：', ...
                '盈亏平衡运距 铁路 %.0f km、水运 %.0f km；线路利用 %s h 时铁路 %s km、水运 %s km。'], bf.uhvHours, bf.uhv, ...
                bf.backhaulFrac, bf.dRail, bf.dWater, mat2str(bf.hours), mat2str(round(bf.dRailH)), mat2str(round(bf.dWaterH)));
        end
        fclose(R.fid);
    end
    results.e6 = e6;
end

% ================= E7 规模扩展与学习诊断 =================
if want('E7')
    [done, e7] = loadDone(resume, root, 'E7', stamp, 'e7', R0.fid);
    if ~done
        R = newRunDir(root, 'E7', stamp, p, struct('common', R0.dir));
        t0 = tic;
        pE7 = p;
        pE7.ctdf.chosenMode = dec.mode;          % 计时采用验证集选定的决策方式
        e7 = runE7Scaling(pE7, p.seed + 7);
        save(fullfile(R.dir, 'results.mat'), 'e7');
        writetable(e7.table, fullfile(R.dir, 'E7_scaling.csv'), 'Encoding', 'UTF-8');
        writetable(e7.repetitions,fullfile(R.dir,'E7_repetitions.csv'),'Encoding','UTF-8');
        F19_scaling(e7, S, fullfile(R.dir, 'F19_scaling'));
        if needM1
            F15_gradVarSurface(models.M1{1}, S, fullfile(R.dir, 'F15_learningDiag'));
        end
        logMsg(R.fid, 'E7 完成，用时 %.1f s。', toc(t0));
        fclose(R.fid);
    end
    results.e7 = e7;
end

% ================= 气象数据图 F02—F04 =================
if want('figW')
    R = newRunDir(root, 'figW', stamp, p, struct('common', R0.dir));
    mh = [];
    if isfield(p.weather, 'era5') && strcmpi(p.weather.source, 'csv')
        fr = fullfile(p.weather.era5.dataDir, 'fit_report.mat');
        if isfile(fr)
            Lr = load(fr, 'rep');
            if isfield(Lr.rep, 'monthHourW')
                mh = Lr.rep.monthHourW;
            end
        end
    end
    F02_resourceSurface(mh, C.W, p, S, fullfile(R.dir, 'F02_windSurface'));
    F03_yearRidges(C.W, p, S, fullfile(R.dir, 'F03_yearRidges'));
    F04_reLoadJoint(C.W, p, S, fullfile(R.dir, 'F04_reLoadJoint'));
    logMsg(R.fid, '气象数据图 F02—F04 完成。');
    fclose(R.fid);
end

% ================= 图 F20（状态向量示意）、F06（测试年 SOC 与节点裕度） =================
if want('fig02') || want('fig03')
    R = newRunDir(root, 'figs', stamp, p, struct('common', R0.dir));
    if want('fig02')
        seg = buildSegment(C.W(yrTest(1)), 1, 3, p);
        env = IronRustEnv(ctx);
        env.reset(p.seed, C.cNominal, p.exp.initSOC, struct('seg', seg));
        x0 = env.x;
        env.step(policyAct(env.getObs(), w0, ctx));
        F20_stateVector(ctx, x0, env.x, S, fullfile(R.dir, 'F20_stateVector'));
    end
    if want('fig03')
        nm = p.exp.e1Method;
        if ~isfield(fac, nm)
            nm = 'M0';
        end
        sp = makeEvalSpecs(p, yrTest(1), seeds(1), {'normal'}, C.cNominal, struct('keepTrace', true));
        ep = runEpisode(ctx, C.W, sp, fac.(nm)(seeds(1)));
        yrLab = sprintf('测试年（第 %d 年）', yrTest(1));
        if isfield(p.weather, 'era5') && strcmpi(p.weather.source, 'csv')
            yrLab = sprintf('%d 年', p.weather.era5.years(yrTest(1)));
        end
        F06_socHeatmap(ep.trace, p, S, fullfile(R.dir, 'F06_socHeatmap'), yrLab);
    end
    fclose(R.fid);
end

% ================= 表格导出 =================
Rt = newRunDir(root, 'tables', stamp, p, struct('common', R0.dir));
files = exportTables(results, p, Rt.dir);
logMsg(Rt.fid, '已导出 %d 个表格文件。', numel(files));
fclose(Rt.fid);
logMsg(R0.fid, '全部实验完成，总用时 %.1f min。', toc(tAll) / 60);
fclose(R0.fid);
save(fullfile(R0.dir, 'results_all.mat'), 'results', '-v7.3');
end

function m = setLam(m, lam)
m.cfg.lambda = lam;
end

function fl = flowsByYear(e3, years)
% 图 F01 的线路年物流量：本文方法（无 M1 时取第一个方法）常规工况，各测试年对种子取平均，日均发运量 × 365（t/年）
fl = [];
if ~isfield(e3, 'daily') || isempty(e3.daily)
    return;
end
D = e3.daily(strcmp({e3.daily.scenario}, 'normal'));
ms = unique({D.method}, 'stable');
main = 'M1';
if ~any(strcmp(ms, main))
    main = ms{1};
end
D = D(strcmp({D.method}, main));
F = zeros(numel(D(1).flow), numel(years));
for k = 1:numel(years)
    s = [D.year] == years(k);
    if any(s)
        F(:, k) = mean([D(s).flow], 2) * 365;
    end
end
fl = struct('F', F, 'years', years, 'method', main);
end

function m = trainNamed(nm, ds, nrm, ctx, lib, cfg, s, gtVal, verbose, ckptFile)
% 按名称训练学习类模型（M1、M3、M4 与 E5 单要素对照模型），训练设置见补充说明 5；ckptFile 为断点续训检查点文件
switch nm
    case 'M1'
        m = trainCTDF(ds, nrm, ctx, lib, cfg, struct('seed', s, 'tag', 'M1', 'gtVal', gtVal, 'verbose', verbose, ...
            'ckptFile', ckptFile));
    case 'M3'
        m = stepwiseWM(ds, nrm, ctx, lib, cfg, struct('seed', s, 'verbose', verbose, 'ckptFile', ckptFile));
    case 'M4'
        cfg.sourceType = 'gaussian';
        cfg.useNullSpaceProj = false;
        cfg.useTerminalProj = false;
        m = trainCTDF(ds, nrm, ctx, lib, cfg, struct('seed', s, 'tag', 'M4', 'gtVal', gtVal, 'verbose', verbose, ...
            'ckptFile', ckptFile));
    case 'noNull'
        cfg.useNullSpaceProj = false;
        m = trainCTDF(ds, nrm, ctx, lib, cfg, struct('seed', s, 'tag', 'E5-noNull', 'verbose', verbose, ...
            'ckptFile', ckptFile));
    case 'gauss'
        cfg.sourceType = 'gaussian';
        m = trainCTDF(ds, nrm, ctx, lib, cfg, struct('seed', s, 'tag', 'E5-gauss', 'verbose', verbose, ...
            'ckptFile', ckptFile));
    case 'noCurr'
        cfg.useGammaCurriculum = false;
        m = trainCTDF(ds, nrm, ctx, lib, cfg, struct('seed', s, 'tag', 'E5-noCurr', 'verbose', verbose, ...
            'ckptFile', ckptFile));
    otherwise
        error('runExperiments:model', '未知模型 %s。', nm);
end
end

function m = refreshDecisionCfg(m, c)
% 决策时设置（λ、K、GPI 模式、ϑ、GPU）不影响训练，读取缓存模型后以当前参数为准
f = {'lambda', 'lambdaGrid', 'K', 'gpiMode', 'varthetaDays', 'useGPU'};
for k = 1:numel(f)
    if isfield(c, f{k})
        m.cfg.(f{k}) = c.(f{k});
    end
end
end

function fp = modelFingerprint(p)
% 影响数据集、真值样本与训练结果的全部参数（去掉只影响评估、作图与经济核算的字段；断点续训/续跑的
% ckptEvery、blockEpisodes 不影响结果，也去掉，已有缓存的指纹不变）
fp = rmfield(p, intersect(fieldnames(p), {'exp', 'plot', 'mpc', 'retire', 'caseName'}));
fp.ctdf = rmfield(fp.ctdf, intersect(fieldnames(fp.ctdf), {'lambda', 'lambdaGrid', 'K', 'gpiMode', 'varthetaDays', ...
    'useGPU', 'ckptEvery'}));
fp.data = rmfield(fp.data, intersect(fieldnames(fp.data), {'useParfor', 'chunkCols', 'blockEpisodes'}));
fp.plant = rmfield(fp.plant, intersect(fieldnames(fp.plant), {'remainLife', 'newCapex', 'retrofitFrac', 'bookValueFrac'}));
fp.station = rmfield(fp.station, intersect(fieldnames(fp.station), {'capexRedPerKwFe', 'capexElPerKw', 'life'}));
fp.transport = rmfield(fp.transport, intersect(fieldnames(fp.transport), {'uhvCostPerKwh', 'uhvCostPer1000km'}));
fp.source = sourceFingerprint(fileparts(fileparts(mfilename('fullpath'))),p);
fp.expSeeds = p.exp.seeds;
% The path-risk reference depends on smoothing even though network fitting does not.
fp.expGTRisk = struct('schemaVersion',3,'varthetaDays',p.ctdf.varthetaDays);
fp.expGT = [p.exp.gtStates, p.exp.gtValStates, p.exp.gtR, p.exp.gtSamples, p.exp.gtTcap, p.exp.exactW1Max, ...
    p.exp.warmup, p.exp.evalDays, p.exp.initSOC];
end

function [dirOut, hit] = locateCache(cacheRoot, fp, stamp)
% 在 cacheRoot 下查找指纹相同的缓存目录（最新优先）；没有则新建并保存指纹
if ~exist(cacheRoot, 'dir')
    mkdir(cacheRoot);
end
d = dir(cacheRoot);
d = d([d.isdir] & ~ismember({d.name}, {'.', '..'}));
[~, ord] = sort([d.datenum], 'descend');
for k = ord(:)'
    f = fullfile(cacheRoot, d(k).name, 'fingerprint.mat');
    if isfile(f)
        L = load(f, 'fp');
        if isequaln(L.fp, fp)
            dirOut = fullfile(cacheRoot, d(k).name);
            hit = true;
            return;
        end
    end
end
for k = ord(:)'
    f = fullfile(cacheRoot, d(k).name, 'fingerprint.mat');
    if isfile(f)
        L = load(f, 'fp');
        if isfield(L.fp, 'source') && isfield(fp, 'source') && ...
                isequaln(rmfield(L.fp, 'source'), rmfield(fp, 'source')) && trainingSourceMatches(L.fp.source, fp.source)
            dirOut = fullfile(cacheRoot, d(k).name);
            hit = true;
            fprintf('模型缓存：评估或作图代码已更新，训练相关代码与参数未变，沿用 %s。\n', dirOut);
            return;
        end
    end
end
dirOut = fullfile(cacheRoot, stamp);
if isfolder(dirOut) || isfile(dirOut)
    error('runExperiments:cacheCollision', ...
        'Unmatched cache directory %s already exists; refusing to relabel old artifacts. Use a new run stamp.',dirOut);
end
mkdir(dirOut);
save(fullfile(dirOut, 'fingerprint.mat'), 'fp');
hit = false;
end

function stamp = latestStamp(d)
% 续跑：d（results/common）下最近一次运行的时间戳；目录名为 yyyyMMdd_HHmmss，取字典序最大者
names = {};
s = dir(d);
if ~isempty(s)
    names = {s([s.isdir]).name};
    names = names(~cellfun('isempty', regexp(names, '^\d{8}_\d{6}$', 'once')));
end
if isempty(names)
    error('runExperiments:resume', '续跑失败：%s 下没有可继续的运行（时间戳目录）。请设置 resume = false 开始新的运行。', d);
end
names = sort(names);
stamp = names{end};
end

function checkResume(fc, p, stamp)
% 续跑前核对参数：common/<时间戳>/config.mat 中保存的 p 须与当前 p 完全一致
if ~isfile(fc)
    error('runExperiments:resume', '续跑失败：未找到运行 %s 的参数文件 %s。请设置 resume = false 开始新的运行。', stamp, fc);
end
L = load(fc, 'p');
if isfield(L, 'p') && ~isequaln(L.p, p) && isequaln(modelParamKey(L.p), modelParamKey(p))
    warning('runExperiments:resumeEvalParams', ['续跑：只有评估或核算参数改变（实验设置、作图、MPC、退役对照、' ...
        '投资与寿命等），模型相关参数未变，继续运行；已完成的实验块保持原结果，未完成的按新参数计算。']);
    return;
end
if ~isfield(L, 'p') || ~isequaln(L.p, p)
    error('runExperiments:resume', ['续跑失败：当前参数与运行 %s 保存的参数（%s）不一致——参数已改变，不能续跑。' ...
        '请设置 resume = false 开始新的运行（模型缓存仍会自动复用：影响模型的参数未改变时不会重新采集与训练）。'], ...
        stamp, fc);
end
end

function [tf, v] = loadDone(resume, root, expName, stamp, vname, fid)
% 续跑模式下读取已完成实验块的结果：<root>/<实验名>/<时间戳>/results.mat 存在且可读取时返回 true
% （调用方据此跳过该实验块，不重算、不重新作图）；文件无法读取时警告并返回 false（重新运行该实验块）
tf = false;
v = [];
f = fullfile(root, expName, stamp, 'results.mat');
if ~resume || ~isfile(f)
    return;
end
try
    L = load(f, vname);
    v = L.(vname);
    tf = true;
    logMsg(fid, '续跑：%s 已完成，读取 %s（不重算、不重新作图）。', expName, f);
catch
    warning('runExperiments:resume', '续跑：读取 %s 失败（文件损坏或缺少结果变量），重新运行 %s。', f, expName);
end
end

function d = runCacheDir(base, name, resume)
% 实验目录下的逐回合 / 逐变体结果目录（断点续跑用）；非续跑模式先清空同名旧目录，避免误用其他运行的结果
d = fullfile(base, name);
if ~resume
    removeDir(d);
end
end

function saveAtomic(f, S, varargin)
% 原子保存：S 的各字段保存为同名变量，先写同目录临时文件再改名覆盖（中断时不会留下损坏的目标文件）
[fd, nm] = fileparts(f);
tmp = fullfile(fd, [nm, '.tmp.mat']);
save(tmp, '-struct', 'S', varargin{:});
movefile(tmp, f, 'f');
end

function removeDir(d)
% 删除中间结果目录（不存在时忽略）
if exist(d, 'dir')
    rmdir(d, 's');
end
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = d;
end
end

function tf = trainingSourceMatches(a, b)
% 只比较决定数据集、环境动力学、行为策略、模型与训练的源代码（baselines、capacity、ctdf、data、env、policies、
% topo、utils）及外部气象文件；评估、核算、配置文件与作图代码的改动不影响已训练模型。
tf = false;
if ~isstruct(a) || ~isstruct(b) || ~isfield(a, 'sourceFiles') || ~isfield(b, 'sourceFiles')
    return;
end
[na, ha] = trainingFiles(a);
[nb, hb] = trainingFiles(b);
tf = isequal(na, nb) && isequal(ha, hb) && isequaln(getf(a, 'weatherSHA256', ''), getf(b, 'weatherSHA256', ''));
end

function [n, h] = trainingFiles(s)
keep = {'baselines', 'capacity', 'ctdf', 'data', 'env', 'policies', 'topo', 'utils'};
top = cellfun(@firstPart, s.sourceFiles, 'UniformOutput', false);
m = ismember(top, keep);
n = s.sourceFiles(m);
h = s.sourceHashes(m);
n = strrep(n, '\', '/');
[n, ix] = sort(n);
h = h(ix);
end

function t = firstPart(r)
r = strrep(r, '\', '/');
i = find(r == '/', 1);
if isempty(i)
    t = '';
else
    t = r(1:i - 1);
end
end

function k = modelParamKey(p)
% 与 modelFingerprint 相同的参数部分（不含源代码指纹），用于判断续跑时参数改变是否影响模型
k = rmfield(p, intersect(fieldnames(p), {'exp', 'plot', 'mpc', 'retire', 'caseName'}));
k.ctdf = rmfield(k.ctdf, intersect(fieldnames(k.ctdf), {'lambda', 'lambdaGrid', 'K', 'gpiMode', 'varthetaDays', ...
    'useGPU', 'ckptEvery'}));
k.data = rmfield(k.data, intersect(fieldnames(k.data), {'useParfor', 'chunkCols', 'blockEpisodes'}));
k.plant = rmfield(k.plant, intersect(fieldnames(k.plant), {'remainLife', 'newCapex', 'retrofitFrac', 'bookValueFrac'}));
k.station = rmfield(k.station, intersect(fieldnames(k.station), {'capexRedPerKwFe', 'capexElPerKw', 'life'}));
k.transport = rmfield(k.transport, intersect(fieldnames(k.transport), {'uhvCostPerKwh', 'uhvCostPer1000km'}));
k.expSeeds = p.exp.seeds;
k.expGT = [p.exp.gtStates, p.exp.gtValStates, p.exp.gtR, p.exp.gtSamples, p.exp.gtTcap, p.exp.exactW1Max, ...
    p.exp.warmup, p.exp.evalDays, p.exp.initSOC];
end

function z = pickSafeZ(zGrid, zs, tol)
% 安全改进阈值的保守选取：验证准则 zs 不超过最小值 (1 + tol) 倍的候选中取最大的 z
zGrid = zGrid(:);
zs = zs(:);
ok = isfinite(zs) & zs <= (1 + tol) * min(zs);
z = max(zGrid(ok));
end

function v = decisionScore(T, regs, base0, crit)
% 决策规则的选择准则：'mean' 为全部验证回合平均成本；'worstRegime' 为各工况平均成本 / M0 同工况平均成本的最大值
if strcmpi(crit, 'worstRegime')
    rr = zeros(numel(regs), 1);
    for k = 1:numel(regs)
        rr(k) = mean(T.cost(strcmp(T.scenario, regs{k}))) / max(base0(k), eps);
    end
    v = max(rr);
else
    v = mean(T.cost);
end
end
