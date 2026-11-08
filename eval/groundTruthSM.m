function gt = groundTruthSM(ctx, lib, st, gammas, opts)
%GROUNDTRUTHSM 后继测度真值样本。
%   对每个测试状态 s_m（sampleStates 输出）与其联合策略 w_m：
%     1) 由当日隐状态出发，用气象过程生成 R 条相互独立的气象延续（simulateWeather，分支回放），
%        对每条延续重建片段与共用预测器输出（'conditional' 预测只依赖当日隐状态，故重建后的初始状态与 s_m 一致）；
%     2) 自 s_m 的物料、品质、上一日出力与成本分量出发，按 π_{w_m} 在完整环境中运行 Tcap 天；
%     3) 对每个 γ 抽取 nSamples 个停止时刻 T ~ Geometric(1 − γ)（P(T = k+1) = (1−γ)γ^k，T ≥ 1，截断于 Tcap）
%        与回放编号 r ~ U{1..R}，取第 r 条回放的 S_T 作为真值样本。
%   截断概率 γ^Tcap 记入 gt.truncMass；γ=0.99、Tcap=400 时仍约为1.8%，不可称为未截断真值。
%   opts 字段：R、Tcap、nSamples、seed、useParfor、partDir（可选，断点续跑）。
%   断点续跑：给定 opts.partDir 时，每个状态的结果保存为 partDir/state_<q>.mat，再次运行时读取已完成的状态
%   （键不一致或文件损坏时重算）；各状态使用独立随机流（种子 seed·1000 + q），跳过与否不改变结果。
%   All R continuations run to Tcap. Additional outputs retain branchId and
%   stopTime, source year/day, and pathRisk{g} (R-by-state) with an R-based
%   Hoeffding interval. Samples reusing a path are not independent paths.
%   opts.marginSpec optionally fixes GFe/gFe0 for both reference and model
%   evaluation; otherwise the dispatched-pipeline affine proxy is used.

p = ctx.p;
if ~strcmpi(p.forecast.mode, 'conditional')
    error('groundTruthSM:forecast','Normal-kernel reference requires conditional forecasts.');
end
R = opts.R;
Tcap = opts.Tcap;
nS = opts.nSamples;
if ~isreal(gammas)||isempty(gammas)||any(~isfinite(gammas) | gammas < 0 | gammas >= 1)
    error('groundTruthSM:gamma', 'Discounts must satisfy 0 <= gamma < 1.');
end
if any(~isfinite([R,Tcap,nS]))||any([R,Tcap,nS]<1)||any([R,Tcap,nS]~=floor([R,Tcap,nS]))|| ...
        ~isscalar(R)||~isscalar(Tcap)||~isscalar(nS)
    error('groundTruthSM:budget','R, Tcap and nSamples must be positive integers.');
end
alpha=getf(opts,'riskAlpha',.05);
cappedPathRisk(0,0,alpha); % validate the confidence level before simulation
margin=getf(opts,'marginSpec',ctx.margin);
theta=p.ctdf.varthetaDays*max(mean(ctx.stats.deltaDbarP),1e-6);
riskSpec=struct('G',full(margin.GFe),'b',margin.gFe0,'theta',theta);
affineRiskBound(zeros(ctx.L.D,1),1,zeros(ctx.L.D,1),1,riskSpec); % fixed affine domain
normalVerified=isfield(ctx.L.xi,'Fcap')&&isfield(ctx.L.xi,'rhoAvail');
if normalVerified
    cap=st.S0(ctx.L.xi.Fcap,:);
    rho=st.S0(ctx.L.xi.rhoAvail,:);
    expected=double(ctx.topo.Fcap(:)>0);
    if any(~isfinite([cap(:);rho(:)]))||any(abs(cap-expected)>1e-8,'all')||any(abs(rho-1)>1e-8,'all')
        error('groundTruthSM:capacity','Reference requires nominal currently observed line and station capacity.');
    end
end
nG = numel(gammas);
m = size(st.S0, 2);
D = ctx.L.D;
smp = cell(1, m);
extra=cell(1,m);
initErr = zeros(1, m);
useP = getf(opts, 'useParfor', p.data.useParfor) && m > 1 && ~isempty(ver('parallel')) && ...
    license('test', 'Distrib_Computing_Toolbox');
partDir = getf(opts, 'partDir', '');
if ~isempty(partDir) && ~exist(partDir, 'dir')
    mkdir(partDir);
end
codeKey=[];
if ~isempty(partDir)
    codeKey=sourceFingerprint(fileparts(fileparts(mfilename('fullpath'))),p);
end
if useP
    parfor q = 1:m
        [smp{q}, initErr(q),extra{q}] = oneStateCached(ctx, lib, st, q, gammas, R, Tcap, nS, opts.seed, partDir,riskSpec,alpha,codeKey);
    end
else
    for q = 1:m
        [smp{q}, initErr(q),extra{q}] = oneStateCached(ctx, lib, st, q, gammas, R, Tcap, nS, opts.seed, partDir,riskSpec,alpha,codeKey);
    end
end
gt.samples = cell(1, nG);
for g = 1:nG
    A = zeros(D, nS, m, 'single');
    for q = 1:m
        A(:, :, q) = smp{q}{g};
    end
    gt.samples{g} = A;
    gt.branchId{g}=zeros(nS,m);
    gt.stopTime{g}=zeros(nS,m);
    gt.pathRisk{g}=zeros(R,m);
    gt.pathRiskMean{g}=zeros(1,m);
    gt.pathRiskHoeffding{g}=zeros(1,m);
    gt.pathRiskCI{g}=zeros(2,m);
    gt.pathRiskInfiniteHorizonCI{g}=zeros(2,m);
    for q=1:m
        gt.branchId{g}(:,q)=extra{q}.branchId(:,g);
        gt.stopTime{g}(:,q)=extra{q}.stopTime(:,g);
        pr=extra{q}.risk{g};
        gt.pathRisk{g}(:,q)=pr.pathMean;
        gt.pathRiskMean{g}(q)=pr.mean;
        gt.pathRiskHoeffding{g}(q)=pr.hoeffdingHalfWidth;
        gt.pathRiskCI{g}(:,q)=pr.cappedCI(:);
        gt.pathRiskInfiniteHorizonCI{g}(:,q)=pr.infiniteHorizonCI(:);
    end
end
gt.S0 = st.S0;
gt.c0 = st.c0;
gt.emb0 = st.emb0;
gt.ids = st.ids;
gt.year=getf(st,'year',nan(1,m));
gt.day=getf(st,'day',nan(1,m));
gt.gammas = gammas(:)';
gt.truncMass = gammas(:)' .^ Tcap;
gt.riskTruncationBound=gt.truncMass;
gt.initErr = initErr;
gt.R = R;
gt.Tcap = Tcap;
gt.referenceType = 'fitted-weather model reference with capped geometric stopping';
gt.independentContinuationCount = R;
gt.sampleCountPerState = nS;
gt.samplesShareContinuations = true;
gt.truncationRule = 'T = min(Geometric(1-gamma), Tcap); tail mass placed at Tcap';
gt.referenceUncertainty = 'Monte Carlo error is clustered by continuation; nSamples is not the independent path count';
gt.normalCapacityVerified=normalVerified;
gt.kernelScope='normal fixed capacity, conditional fitted-weather process';
if ~normalVerified, gt.kernelScope='legacy state layout: current capacity unverified'; end
gt.riskFunctional=struct('kind',getf(margin,'kind','dispatched_pipeline'),'spec',riskSpec,'alpha',alpha, ...
    'units','raw state coordinates','scope','fixed bounded occupancy, not realised event probability');
gt.schemaVersion=3;
end

function [out, initErr,extra] = oneStateCached(ctx, lib, st, q, gammas, R, Tcap, nS, seed, partDir,riskSpec,alpha,codeKey)
% 带逐状态结果文件的 oneState（断点续跑）。文件读写放在局部函数中，满足 parfor 透明性要求
% （parfor 循环体内不能直接调用 save/load）；先写临时文件再改名，中断时不会留下损坏的结果文件。
if isempty(partDir)
    [out, initErr,extra] = oneState(ctx, lib, st, q, gammas, R, Tcap, nS, seed,riskSpec,alpha);
    return;
end
key = struct('schemaVersion', 3, 'S0', st.S0(:, q), 'c0', st.c0(q), 'id', st.ids(:, q), ...
    'gammas', gammas(:)', 'R', R, 'Tcap', Tcap, 'nS', nS, 'seed', seed, ...
    'p', ctx.p, 'lib', lib, 'layout', ctx.L, 'hidden', st.hs{q}, 'snapshot', st.snap{q}, ...
    'riskSpec',riskSpec,'alpha',alpha,'source',codeKey);
f = fullfile(partDir, sprintf('state_%04d.mat', q));
if isfile(f)
    try
        L = load(f, 'key', 'out', 'initErr','extra');
        if isequaln(L.key, key)&&isfield(L,'extra')
            out = L.out;
            initErr = L.initErr;
            extra=L.extra;
            return;
        end
    catch
        % 文件损坏：重新计算并覆盖
    end
end
[out, initErr,extra] = oneState(ctx, lib, st, q, gammas, R, Tcap, nS, seed,riskSpec,alpha);
tmp = [tempname(partDir), '.mat'];
save(tmp, 'key', 'out', 'initErr','extra');
movefile(tmp, f, 'f');
end

function [out, initErr,extra] = oneState(ctx, lib, st, q, gammas, R, Tcap, nS, seed,riskSpec,alpha)
p = ctx.p;
rs = RandStream('twister', 'Seed', seed * 1000 + q);
rsPath=RandStream('twister','Seed',seed*1000+q+104729);
hs = st.hs{q};
sn = st.snap{q};
w = jointPolicy(lib, st.ids(:, q));
nG = numel(gammas);
D = ctx.L.D;
% 预先抽取停止时刻与回放编号
Tg = zeros(nS, nG);
Rg = zeros(nS, nG);
for g = 1:nG
    U = rand(rs, nS, 1);
    if gammas(g)==0
        Tg(:,g)=1;
    else
        Tg(:, g) = min(1 + floor(log(max(U, realmin)) / log(gammas(g))), Tcap);
    end
    Rg(:, g) = randi(rs, R, nS, 1);
end
out = cell(1, nG);
for g = 1:nG
    out{g} = zeros(D, nS, 'single');
end
wx = simulateWeather(hs, Tcap, R, p, rsPath);
initErr = 0;
riskByTime=zeros(R,Tcap);
for r = 1:R
    lastT=Tcap;
    segT=Tcap;
    seg.reg = [hs.reg, wx.reg(r, 1:segT)];
    seg.eW = [hs.eW, wx.eW(r, 1:segT)];
    seg.eS = [hs.eS, wx.eS(r, 1:segT)];
    seg.eL = [hs.eL, wx.eL(r, 1:segT)];
    seg.doy = [hs.doy, wx.doy(r, 1:segT)];
    seg.EW = [hs.EW, wx.EW(r, 1:segT)];
    seg.ES = [hs.ES, wx.ES(r, 1:segT)];
    seg.EL = [hs.EL, wx.EL(r, 1:segT)];
    seg.carbon = hs.carbon;
    seg.h2 = hs.h2;
    seg.year = 0;
    seg.d0 = 0;
    seg.len = segT + 1;
    seg.N = segT + 1;
    seg.F = forecaster(seg, p);
    env = IronRustEnv(ctx);
    env.reset(seed + q, st.c0(q), 0.5, struct('seg', seg, 'x0', sn.x, 'gInv0', sn.gInv, 'gLine0', sn.gLine));
    env.pLast = sn.pLast;
    env.z = sn.z;
    initErr = max(initErr, max(abs(env.stateVector() - st.S0(:, q))));
    need = cell(1, nG);
    for g = 1:nG
        need{g} = find(Rg(:, g) == r);
    end
    for t = 1:lastT
        env.step(policyAct(env.getObs(), w, ctx));
        sd=env.stateVector();
        s = single(sd);
        riskByTime(r,t)=1/(1+exp(min(riskSpec.G*sd+riskSpec.b)/riskSpec.theta));
        for g = 1:nG
            hit = need{g}(Tg(need{g}, g) == t);
            if ~isempty(hit)
                out{g}(:, hit) = repmat(s, 1, numel(hit));
            end
        end
    end
end
extra.branchId=Rg;
extra.stopTime=Tg;
extra.risk=cell(1,nG);
for g=1:nG, extra.risk{g}=cappedPathRisk(riskByTime,gammas(g),alpha); end
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = d;
end
end
