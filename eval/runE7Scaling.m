function e7 = runE7Scaling(p, seed)
%RUNE7SCALING E7 规模扩展的单次决策时间：电厂数取 p.exp.scaleList。
%   每个规模：由 buildScaledCase 构造算例并生成 1 个气象年（只用于统计量与场景库），按基准库存原型运行若干天得到
%   典型状态，分别计时：
%     M1：风险感知 GPI 的单次决策（候选数 = 全体同原型 + nRandCand，K 个样本，nOde 步中点法 + 终端投影）。
%         M1 与 M3 采用与正文相同结构的网络计时，前向计算时间与权重取值无关；
%     M2：随机 MPC 的单次求解（同一场景数与时域规则，含建模与求解时间）。
%     M3：同架构的一步随机网络，按 stepwiseK/stepwiseTcapCtrl 执行逐步 GPI。
%   每个规模重复 p.exp.timingReps 天取均值。
%   输出逐规模均值、逐重复/方法的实际预算与时间、合成拓扑与网络设置。

reps = p.exp.timingReps;
% 决策方式与正式实验一致（验证集选定的 p.ctdf.chosenMode；价值校准偏移不影响计时）
decMode = 'central';
if isfield(p.ctdf, 'chosenMode') && strcmpi(p.ctdf.chosenMode, 'distributed')
    decMode = 'distributed';
elseif ~isfield(p.ctdf, 'chosenMode') && strcmpi(p.ctdf.gpiMode, 'distributed')
    decMode = 'distributed';
end
budgets=[reps,p.ctdf.K,p.exp.stepwiseK,p.exp.stepwiseTcapCtrl];
if any(~isfinite(budgets))||any(budgets<1)||any(budgets~=floor(budgets))
    error('runE7Scaling:budget','Timing repetitions, sample counts and stepwise cap must be positive integers.');
end
rows = cell(0, 12);
raw=cell(0,11);
for nPl = p.exp.scaleList(:)'
    ps = buildScaledCase(p, nPl);
    ps.weather.source = 'synthetic'; % timing fixture, never publication weather
    ps.weather.Y = 1;
    ps.weather.train = 1;
    ps.weather.val = 1;
    ps.weather.test = 1;
    ps.stats.bootB = 50;
    ps.stats.cNominalMode = 'eps';   % 合成规模算例按自身统计量取名义质量（设计点固定质量只适用于浩吉算例）
    Wsc = genWeatherYears(ps, ps.seed);
    C = buildCase(ps, Wsc);
    lib = policyLibrary(ps, C.topo, C.stats, ps.seed);
    ctx = C.ctx;
    warm = 5;
    seg = buildSegment(Wsc(1), 100, warm + reps + 2, ps);
    env = IronRustEnv(ctx);
    env.reset(seed, C.cNominal, ps.exp.initSOC, struct('seg', seg));
    w0 = jointPolicy(lib, lib.alignedIds(:, 4));
    for t = 1:warm
        env.step(policyAct(env.getObs(), w0, ctx));
    end
    cfg = ps.ctdf;
    cfg.nMat = C.idx.n;
    [net, meta] = buildVelocityNet(ctx.L.D, lib.dimEmb, cfg, seed);
    fn = fieldnames(net);
    ema = struct();
    for m = 1:numel(fn)
        ema.(fn{m}) = extractdata(net.(fn{m}));
    end
    nm = struct('n', C.idx.n, 'matScale', C.idx.n, 'mu', zeros(ctx.L.D - C.idx.n, 1), ...
        'sd', ones(ctx.L.D - C.idx.n, 1), 'cRef', C.cNominal, 'D', ctx.L.D);
    model = struct('ema', ema, 'meta', meta, 'cfg', cfg, 'norm', nm, 'gammaFinal', cfg.gammaStages(end), ...
        'useGPU', (ischar(cfg.useGPU) && strcmpi(cfg.useGPU, 'auto')) || isequal(cfg.useGPU, true));
    model1=model;
    model1.gammaFinal=0; % an untrained one-step model, evaluated at the declared successor discount
    mpc = mpcSetup(ctx, Wsc, 1);
    rsM1 = RandStream('twister', 'Seed', seed + nPl);
    rsM2 = RandStream('twister', 'Seed', seed + nPl + 104729);
    rsM3 = RandStream('twister', 'Seed', seed + nPl + 209759);
    tM1 = zeros(reps, 1);
    tM2 = zeros(reps, 1);
    tM3 = zeros(reps, 1);
    nVar = 0;
    for r = 1:reps
        obs = env.getObs();
        t0 = tic;
        [~,g1]=gpiSelectCRN(model, obs, ctx, lib, struct('rs', rsM1, 'mode', decMode, 'K', cfg.K));
        tM1(r) = toc(t0);
        t0 = tic;
        [~, mi] = stochasticMPC(obs, ctx, mpc, rsM2);
        tM2(r) = toc(t0);
        t0=tic;
        [~,g3]=gpiSelectCRN(model1,obs,ctx,lib,struct('rs',rsM3,'mode',decMode, ...
            'riskMode','stepwise','K',ps.exp.stepwiseK,'Tcap',ps.exp.stepwiseTcapCtrl, ...
            'gammaEval',model.gammaFinal));
        tM3(r)=toc(t0);
        raw(end+1,:)={nPl,r,'M1',tM1(r),cfg.K,Inf,g1.nEval,cfg.nOde,NaN,model.gammaFinal,decMode}; %#ok<AGROW>
        raw(end+1,:)={nPl,r,'M2',tM2(r),NaN,mpc.Hm,1,NaN,mpc.S,mpc.gamma,'scenario_programme'}; %#ok<AGROW>
        raw(end+1,:)={nPl,r,'M3',tM3(r),ps.exp.stepwiseK,ps.exp.stepwiseTcapCtrl,g3.nEval, ...
            cfg.nOde,NaN,model.gammaFinal,decMode}; %#ok<AGROW>
        nVar = mi.nVar;
        env.step(policyAct(obs, w0, ctx));
    end
    rows(end + 1, :) = {nPl, C.idx.n, ctx.L.D, size(lib.candidates, 2), mean(tM1), mean(tM2),mean(tM3), nVar, ...
        mpc.Hm,cfg.K,ps.exp.stepwiseK,ps.exp.stepwiseTcapCtrl}; %#ok<AGROW>
end
e7.table = cell2table(rows, 'VariableNames', {'nPlants', 'nMat', 'D', 'nCand', 'tM1', 'tM2','tM3', 'nVarM2', 'HmM2', ...
    'KM1','KM3','TcapM3'});
e7.repetitions=cell2table(raw,'VariableNames',{'nPlants','Repeat','Method','Seconds','K','Tcap', ...
    'nEvaluated','nOde','ScenarioCount','gamma','DecisionRule'});
e7.timingScope=struct('type','synthetic_forward_timing_fixture','networksTrained',false, ...
    'topology','generated scaled topology','weather','synthetic one-year fixture', ...
    'statePath','shared reference-policy states; timed decisions are not executed', ...
    'measurement','tic/toc decision calls including sampling/model transfer or MPC assembly and solve; setup excluded', ...
    'interpretation','descriptive forward workload, not trained-controller latency or a runtime guarantee');
end
