function model = trainCTDF(ds, norm, ctx, lib, cfg, opts)
%TRAINCTDF 训练守恒约束时序差分流世界模型（CTDF-WM）。
%   训练样本为未扰动转移 (s, w, s′)（a = π_w(s)），以策略嵌入 w 为条件学习 m^{π_w}(·|s)。
%   每步：抽取批量，t ~ U(0,1)（逐样本）；
%     第一项：X_0 ~ m_0，X_t = (1−t)·X_0 + t·S′，目标 S′ − X_0；
%     第二项：X_0′ ~ m_0，X̂_t = 目标网络在 (s′, w) 下自 X_0′ 以中点法（步长 t/nOde）积分到 t，
%             目标为目标网络在 (X̂_t, s′, w, t) 的投影速度；在线网络在 (X̂_t, s, w, t) 求值；
%   AdamW（解耦权重衰减）+ 梯度裁剪；目标网络按 EMA 更新（系数 cfg.ema）。
%   γ 课程：cfg.useGammaCurriculum 为真时依次训练 cfg.gammaStages 并热启动；否则只训练最后一个 γ，
%   总步数相同（单要素对照 E5）。
%   学习诊断（补充图 10）：每 diagEvery 步把批量拆为 nMicro 个微批分别求梯度，以 Tr Cov 估计梯度方差；
%   每阶段末在验证状态上计算模型样本与后继测度真值的切片 W1（opts.gtVal，可选）。
%   分布收缩经验检验：最后阶段每 snapEvery 步保存目标网络快照（至多 maxSnaps 个）。
%   断点续训（opts.ckptFile 非空时）：每 cfg.ckptEvery 步（按累计步数 iter）与每个 γ 阶段结束时保存检查点——在线网络
%   （移回 CPU）、目标网络、Adam 一阶/二阶矩、累计步数、刚完成的阶段序号 stageIdx 与该阶段内步序号 stepIdx、
%   阶段末处理是否已完成 stageDone、两个随机流的状态、诊断量、快照、各阶段结果与键（tag、种子、训练设置、可用转移数、
%   γ 阶段与各阶段步数）。先写同目录临时文件再改名（原子写入）。启动时若检查点存在且键一致，则恢复全部状态并从下一步
%   继续（CPU 上与不中断的训练逐位一致）；键不一致或文件无法读取时警告、删除旧检查点并从头训练。正常结束后删除检查点。
%
%   opts 字段：seed、tag、gtVal（可选，见 groundTruthSM）、verbose、gammaStages（可覆盖 cfg）、
%             ckptFile（可选，检查点文件路径；缺省不保存检查点）。
%   输出 model：ema（数值参数，采样用）、net（dlarray 在线参数）、meta、cfg、norm、gammaFinal、
%              stage（各阶段 γ 与 EMA 快照）、snaps、diag。

if nargin < 6
    opts = struct();
end
seed = getOpt(opts, 'seed', ctx.p.seed);
tag = getOpt(opts, 'tag', 'CTDF-WM');
verbose = getOpt(opts, 'verbose', true);
stages = getOpt(opts, 'gammaStages', cfg.gammaStages);
ckptFile = getOpt(opts, 'ckptFile', '');
rs = RandStream('twister', 'Seed', seed);
rsEval = RandStream('twister', 'Seed', seed + 7919);   % 诊断评估用独立随机流，不扰动训练随机数（单要素对照可比）

n = norm.n;
D = norm.D;
cfg.nMat = n;
B = cfg.batch;
[net, meta] = buildVelocityNet(D, lib.dimEmb, cfg, seed);
useGPU = decideGPU(cfg.useGPU);
if useGPU
    net = dlupdate(@gpuArray, net);
end
ema = paramsToNumeric(net);

elig = find(~ds.pert);
if isempty(elig)
    error('trainCTDF:data', '没有可用于训练的未扰动转移。');
end
Wemb = single(embeddingsFromIds(lib, ds.id(:, elig)));
cFrom = ds.c(ds.from(elig));

if cfg.useGammaCurriculum
    stageList = stages;
    stepsList = cfg.stepsPerStage * ones(1, numel(stages));
else
    stageList = stages(end);
    stepsList = cfg.stepsPerStage * numel(stages);
end
if any(stageList > 0) && 1 / (1 - stageList(end)) < ctx.Tl.mean
    warning('trainCTDF:horizon', '最终有效时域 %.1f d 短于闭环周转时间 %.1f d。', 1 / (1 - stageList(end)), ctx.Tl.mean);
end

avgG = [];
avgSq = [];
iter = 0;
dgn.loss = [];
dgn.l1 = [];
dgn.l2 = [];
dgn.gnorm = [];
dgn.gradVar = zeros(0, 3);          % [阶段, 步, Tr Cov]
dgn.stageGamma = stageList;
dgn.horizonW1 = nan(numel(stageList), 1);
snaps = {};
stage = struct('gamma', {}, 'ema', {});
prec = cfg.precision;

% ---------------- 断点续训：读取检查点 ----------------
% 检查点记录最近完成的阶段序号 stageIdx 与该阶段内的步序号 stepIdx；stageDone 表示该阶段的阶段末处理（记录阶段
% 快照、阶段末 W1）是否已执行：为真时从第 stageIdx + 1 阶段的第 1 步开始，否则从第 stageIdx 阶段的第 stepIdx + 1 步
% 继续（stepIdx 等于该阶段步数时内层循环为空，只执行一次尚未执行的阶段末处理）。
useCk = ~isempty(ckptFile);
ckEvery = getOpt(cfg, 'ckptEvery', inf);
stepCk = useCk && isfinite(ckEvery) && ckEvery >= 1;
key = struct('tag', tag, 'seed', seed, 'cfg', trainingCfg(cfg), 'nElig', numel(elig), 'stageList', stageList, ...
    'stepsList', stepsList);
if useCk
    key.schemaVersion = 2;
    key.dataset = datasetSignature(ds);
    key.normalizer = norm;
    key.library = lib;
end
s0 = 1;                 % 开始（继续）训练的阶段
it0 = 0;                % 该阶段已完成的步数
if useCk && isfile(ckptFile)
    ck = readCkpt(ckptFile, key, tag);
    if ~isempty(ck)
        net = ck.net;
        avgG = ck.avgG;
        avgSq = ck.avgSq;
        if useGPU
            net = dlupdate(@gpuArray, net);
            if ~isempty(avgG)
                avgG = dlupdate(@gpuArray, avgG);
                avgSq = dlupdate(@gpuArray, avgSq);
            end
        end
        ema = paramsToDevice(ck.ema, useGPU, cfg.precision);
        iter = ck.iter;
        rs.State = ck.rsState;
        rsEval.State = ck.rsEvalState;
        dgn = ck.dgn;
        snaps = ck.snaps;
        stage = ck.stage;
        if ck.stageDone
            s0 = ck.stageIdx + 1;
        else
            s0 = ck.stageIdx;
            it0 = ck.stepIdx;
        end
        if verbose
            fprintf('[%s] 从检查点恢复（%s）：累计已完成 %d 步。\n', tag, ckptFile, iter);
        end
    end
end

for sIdx = s0:numel(stageList)
    gamma = stageList(sIdx);
    itStart = 1;
    if sIdx == s0
        itStart = it0 + 1;              % 续训：跳过检查点之前已完成的步
    end
    for it = itStart:stepsList(sIdx)
        iter = iter + 1;
        pos = randi(rs, numel(elig), 1, B);
        bi = elig(pos);
        c = cFrom(pos);
        S0 = double(ds.S(:, ds.from(bi)));
        S1 = double(ds.S(:, ds.to(bi)));
        Xs = toModel(S0, c, norm);
        X1 = toModel(S1, c, norm);
        lc = log(c / norm.cRef);
        condS = [Xs; lc];
        condSp = [X1; lc];
        wE = double(Wemb(:, pos));
        t = rand(rs, 1, B);
        X0a = double(sampleSource(meta, n, norm.matScale, B, cfg, rs));
        Xt1 = (1 - t) .* X0a + t .* X1;
        u1 = X1 - X0a;
        Xt1D = toDev(Xt1, useGPU, prec);
        u1D = toDev(u1, useGPU, prec);
        condSD = toDev(condS, useGPU, prec);
        wED = toDev(wE, useGPU, prec);
        tD = toDev(t, useGPU, prec);
        if gamma > 0
            X0b = sampleSource(meta, n, norm.matScale, B, cfg, rs);
            condSpD = toDev(condSp, useGPU, prec);
            Xhat = odeMidpoint(ema, toDev(X0b, useGPU, prec), condSpD, wED, tD, cfg.nOde, meta, cfg);
            u2 = velocityForward(ema, Xhat, condSpD, wED, tD, meta);
            if cfg.useNullSpaceProj
                u2 = nullSpaceProj(u2, n);
            end
        else
            Xhat = Xt1D;
            u2 = zeros(size(Xt1), 'like', Xhat);
        end
        [loss, grads, l1, l2] = dlfeval(@td2Loss, net, Xt1D, u1D, Xhat, u2, condSD, wED, tD, gamma, meta, cfg);
        [net, avgG, avgSq, gn] = adamwStep(net, grads, avgG, avgSq, iter, cfg.lr, cfg, meta);
        ema = emaUpdate(ema, net, cfg.ema);
        metrics = double(gather([extractdata(loss), extractdata(l1), extractdata(l2)]));
        dgn.loss(end + 1) = metrics(1);
        dgn.l1(end + 1) = metrics(2);
        dgn.l2(end + 1) = metrics(3);
        dgn.gnorm(end + 1) = gn;

        % 梯度方差诊断
        if mod(it, cfg.diagEvery) == 0 || it == stepsList(sIdx)
            mB = floor(B / cfg.nMicro);
            s1 = 0;
            s2 = 0;
            for mm = 1:cfg.nMicro
                cols = (mm - 1) * mB + (1:mB);
                [~, gm] = dlfeval(@td2Loss, net, Xt1D(:, cols), u1D(:, cols), Xhat(:, cols), u2(:, cols), ...
                    condSD(:, cols), wED(:, cols), tD(cols), gamma, meta, cfg);
                gv = flattenGrads(gm);
                s1 = s1 + gv;
                s2 = s2 + sum(gv .^ 2);
            end
            gbar = s1 / cfg.nMicro;
            trCov = s2 / cfg.nMicro - sum(gbar .^ 2);        % 微批梯度协方差的迹（Welford 等价形式）
            dgn.gradVar(end + 1, :) = [sIdx, it, double(gather(trCov))];
        end
        % 分布收缩快照（最后阶段）
        if sIdx == numel(stageList) && mod(it, cfg.snapEvery) == 0
            snaps{end + 1} = paramsToCPU(ema); %#ok<AGROW>
            if numel(snaps) > cfg.maxSnaps
                snaps(1) = [];
            end
        end
        if verbose && (it == 1 || mod(it, max(1, floor(stepsList(sIdx) / 5))) == 0)
            fprintf('[%s] γ=%.2f 步 %d/%d  损失 %.4e（一步项 %.4e，自举项 %.4e）\n', tag, gamma, it, ...
                stepsList(sIdx), dgn.loss(end), dgn.l1(end), dgn.l2(end));
        end
        % 断点续训：本步全部状态更新（含诊断与快照）之后保存检查点
        if stepCk && mod(iter, ckEvery) == 0
            saveCkpt(ckptFile, key, net, ema, avgG, avgSq, iter, sIdx, it, false, rs, rsEval, dgn, snaps, stage);
        end
    end
    stage(sIdx).gamma = gamma;
    stage(sIdx).ema = paramsToCPU(ema);
    % 阶段末预测误差（相对后继测度真值）
    if isfield(opts, 'gtVal') && ~isempty(opts.gtVal)
        gv = opts.gtVal;
        gi = find(abs(gv.gammas - gamma) < 1e-9, 1);
        if ~isempty(gi)
            tmpModel = struct('ema', ema, 'meta', meta, 'cfg', cfg, 'norm', norm, 'gammaFinal', gamma, 'useGPU', useGPU);
            dgn.horizonW1(sIdx) = evalAgainstGT(tmpModel, gv, gi, rsEval, ctx);
        end
    end
    % 断点续训：阶段末保存检查点（stageDone = true，续训时从下一阶段开始，本阶段的阶段末处理不会重复执行）
    if useCk
        saveCkpt(ckptFile, key, net, ema, avgG, avgSq, iter, sIdx, stepsList(sIdx), true, rs, rsEval, dgn, snaps, stage);
    end
end

model.net = dlupdate(@gather, net);          % 在线网络参数移回 CPU，缓存的模型可在无 GPU 的机器上读取
model.ema = paramsToCPU(ema);
model.meta = meta;
model.cfg = cfg;
model.norm = norm;
model.gammaFinal = stageList(end);
model.stage = stage;
model.snaps = snaps;
model.diag = dgn;
model.useGPU = useGPU;
model.tag = tag;
% 训练正常结束：删除检查点（及中断时可能残留的临时文件）
if useCk
    deleteIfExists(ckptFile);
    deleteIfExists(ckptTmpName(ckptFile));
end
end

% ---------------- 局部函数 ----------------
function v = getOpt(s, f, d)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = d;
end
end

function tf = decideGPU(flag)
if ischar(flag) || isstring(flag)
    tf = strcmpi(flag, 'auto') && canUseGPU();
else
    tf = logical(flag) && canUseGPU();
end
end

function A = toDev(A, useGPU, prec)
if isa(A, 'dlarray')
    return;
end
A = cast(A, prec);
if useGPU && ~isa(A, 'gpuArray')
    A = gpuArray(A);
end
end

function P = paramsToNumeric(net)
fn = fieldnames(net);
P = struct();
for m = 1:numel(fn)
    P.(fn{m}) = extractdata(net.(fn{m}));
end
end

function P = paramsToDevice(P, useGPU, prec)
if ~useGPU
    return;
end
fn = fieldnames(P);
for m = 1:numel(fn)
    P.(fn{m}) = gpuArray(cast(P.(fn{m}), prec));
end
end

function P = paramsToCPU(P)
P = structfun(@gather, P, 'UniformOutput', false);
end

function ema = emaUpdate(ema, net, tau)
fn = fieldnames(ema);
for m = 1:numel(fn)
    ema.(fn{m}) = (1 - tau) * ema.(fn{m}) + tau * extractdata(net.(fn{m}));
end
end

function g = flattenGrads(grads)
fn = fieldnames(grads);
parts = cell(numel(fn), 1);
for m = 1:numel(fn)
    v = extractdata(grads.(fn{m}));
    parts{m} = double(v(:));
end
g = vertcat(parts{:});
end

function w1 = evalAgainstGT(model, gv, gi, rs, ctx)
nS = size(gv.S0, 2);
vals = zeros(nS, 1);
for m = 1:nS
    gt = gv.samples{gi}(:, :, m);
    K = size(gt, 2);
    smp = sampleGHM(model, gv.S0(:, m), gv.c0(m), gv.emb0(:, m), K, rs);
    Xg = toModel(gt, gv.c0(m), model.norm);
    Xm = toModel(smp, gv.c0(m), model.norm);
    vals(m) = wasserstein1(Xm, Xg, struct('method', 'sliced', 'nDirs', ctx.p.exp.slicedDirs, 'seed', m));
end
w1 = mean(vals);
end

function c = trainingCfg(cfg)
% 检查点键中的训练设置：去掉不影响训练数值的字段（检查点间隔；决策设置与设备选择，与模型缓存指纹一致）
c = rmfield(cfg, intersect(fieldnames(cfg), {'ckptEvery', 'lambda', 'lambdaGrid', 'K', 'gpiMode', 'varthetaDays', ...
    'useGPU'}));
end

function ck = readCkpt(f, key, tag)
% 读取检查点；键不一致（训练设置、数据、种子或阶段已改变）或文件无法读取时警告、删除旧文件并返回空（从头训练）
ck = [];
try
    L = load(f, 'ck');
    if isequaln(L.ck.key, key)
        ck = L.ck;
        return;
    end
    warning('trainCTDF:ckpt', '[%s] 检查点 %s 与当前训练设置不一致，删除后从头训练。', tag, f);
catch
    warning('trainCTDF:ckpt', '[%s] 检查点 %s 无法读取（文件损坏或格式不符），删除后从头训练。', tag, f);
end
delete(f);
end

function saveCkpt(f, key, net, ema, avgG, avgSq, iter, sIdx, it, stageDone, rs, rsEval, dgn, snaps, stage)
% 原子写入检查点：先保存到同目录的临时文件，再改名覆盖（中断时不会留下损坏的检查点）
ck.key = key;
ck.net = dlupdate(@gather, net);          % 在线网络移回 CPU
ck.ema = paramsToCPU(ema);
ck.avgG = avgG;
ck.avgSq = avgSq;
if ~isempty(avgG)
    ck.avgG = dlupdate(@gather, avgG);
    ck.avgSq = dlupdate(@gather, avgSq);
end
ck.iter = iter;
ck.stageIdx = sIdx;                       % 最近完成的阶段序号
ck.stepIdx = it;                          % 该阶段内最近完成的步序号
ck.stageDone = stageDone;                 % 该阶段的阶段末处理是否已完成
ck.rsState = rs.State;
ck.rsEvalState = rsEval.State;
ck.dgn = dgn;
ck.snaps = snaps;
ck.stage = stage;
fd = fileparts(f);
if ~isempty(fd) && ~exist(fd, 'dir')
    mkdir(fd);
end
tmp = ckptTmpName(f);
save(tmp, 'ck', '-v7.3');
movefile(tmp, f, 'f');
end

function t = ckptTmpName(f)
[fd, nm] = fileparts(f);
t = fullfile(fd, [nm, '.tmp.mat']);
end

function deleteIfExists(f)
if isfile(f)
    delete(f);
end
end
