function vp = checkModelProperties(model, ctx, lib, ds, gt, th, opts)
%CHECKMODELPROPERTIES 守恒与模型性质的数值检查，输出补充表 4。
%   模型相关检验（M1，目标网络参数，最终 γ）：
%     生成支撑、自举目标支撑：测试状态与数据集下一状态 s′（自举目标）处的生成样本，越界比例（|1ᵀx − c| > 1e−9·c 或
%                     min x < −1e−9·c）应为 0；同时报告终端投影前的守恒误差与负值比例；
%     流路径内部性：Dirichlet 源与直线路径 X_t = (1−t)X_0 + tX_1 在 t ∈ (0,1) 的样本位于缩放单纯形相对内部的比例（应为 1）；
%     零空间投影：同一批数据上逐样本比较 ‖P·v − u‖² 与 ‖v − u‖²（u = S′ − X_0），比值应不超过 1；
%             双精度下生成 ODE 全程的守恒误差（应为舍入误差量级）；
%     终端投影：W1(Π#q, m) / W1(q, m) ≤ 1（q 为终端投影前样本，m 为真值样本，精确 W1）；
%     精确有限算子：独立于网络的下一状态固定点、γ 收缩与投影检查；
%     网络诊断：相邻目标快照在有限测试集上的最大 W1 变化；
%     固定仿射风险：同一对经验测度上的 |R̃ − R| ≤ L·W1。
%   理论检验（th 字段，来自 capacity/）：massBalance、criticalMass、eventRisk，汇入补充表 4。
%   opts 字段：K（样本数，缺省 min(gtSamples, exactW1Max)）、nBatch（缺省 512）、seed。
%   输出 vp：各项数值与 table（补充表 4：检查项、对应关系、结果、判据、是否满足）。

p = ctx.p;
if nargin < 7
    opts = struct();
end
rs = RandStream('twister', 'Seed', getf(opts, 'seed', p.seed + 71));
norm = model.norm;
n = norm.n;
cfg = model.cfg;
gi = find(abs(gt.gammas - model.gammaFinal) < 1e-9, 1);
if isempty(gi)
    error('checkModelProperties:gamma','A reference at the model discount is required.');
end
K = getf(opts, 'K', min(size(gt.samples{gi}, 2), p.exp.exactW1Max));
nB = min(getf(opts, 'nBatch', 512), nnz(~ds.pert));
mS = size(gt.S0, 2);
tolC = 1e-9;

% ---------- 生成支撑、自举目标支撑：生成样本与自举目标的越界比例 ----------
[smp, raw] = sampleGHM(model, gt.S0, gt.c0, gt.emb0, K, rs);
[vp.viol, vp.consMax, vp.negFrac] = feasStats(smp, gt.c0, n, tolC);
[vp.rawConsMax, vp.rawNegFrac] = rawStats(raw, n);
elig = find(~ds.pert);
pick = elig(randi(rs, numel(elig), 1, nB));
Sp = double(ds.S(:, ds.to(pick)));
cp = ds.c(ds.to(pick));
Ep = embeddingsFromIds(lib, ds.id(:, pick));
[smpB, rawB] = sampleGHM(model, Sp, cp, Ep, 4, rs);
[vp.violBoot, vp.consMaxBoot] = feasStats(smpB, cp, n, tolC);
[vp.rawConsMaxBoot, vp.rawNegFracBoot] = rawStats(rawB, n);

% ---------- 流路径内部性：源分布与直线路径的相对内部 ----------
S0b = double(ds.S(:, ds.from(pick)));
X1 = toModel(Sp, cp, norm);
% 数据集以单精度存储：物料分量按和归一化，消除存储舍入（真实下一状态严格满足 1ᵀx = c）
X1(1:n, :) = n * X1(1:n, :) ./ sum(X1(1:n, :), 1);
X0 = double(sampleSource(model.meta, n, norm.matScale, nB, setfield(cfg, 'precision', 'double'), rs)); %#ok<SFLD>
t = rand(rs, 1, nB) * (1 - 2e-6) + 1e-6;
Xt = (1 - t) .* X0 + t .* X1;
vp.interiorFrac = mean(all(Xt(1:n, :) > 0, 1) & abs(sum(Xt(1:n, :), 1) - n) <= 1e-12 * n);
vp.sourceTangent = max(abs(sum(X1(1:n, :) - X0(1:n, :), 1)));

% ---------- 零空间投影：投影前后损失之比与 ODE 守恒 ----------
lc = log(cp / norm.cRef);
Xs = toModel(S0b, cp, norm);
cond = [Xs; lc];
u = X1 - X0;
pd = toDouble(model.ema);
v = velocityForward(pd, Xt, cond, Ep, t, model.meta);
vP = nullSpaceProj(v, n);
l0 = sum((v - u) .^ 2, 1);
lP = sum((vP - u) .^ 2, 1);
ratio = lP ./ max(l0, realmin);
vp.projLossRatioMax = max(ratio);
vp.projLossRatioMean = mean(ratio);
cfgD = cfg;
cfgD.precision = 'double';
cfgD.nMat = n;
Xode = X0;
h = 1 / cfg.nOde;
tk = zeros(1, nB);
odeErr = 0;
for k = 1:cfg.nOde
    v1 = nullSpaceProj(velocityForward(pd, Xode, cond, Ep, tk, model.meta), n);
    v2 = nullSpaceProj(velocityForward(pd, Xode + h / 2 * v1, cond, Ep, tk + h / 2, model.meta), n);
    Xode = Xode + h * v2;
    tk = tk + h;
    odeErr = max(odeErr, max(abs(sum(Xode(1:n, :), 1) - n)) / n);
end
vp.odeConsErr = odeErr;

% ---------- 终端投影：终端投影的 W1 比值 ----------
ratio5 = zeros(mS, 1);
w1raw = zeros(mS, 1);
w1proj = zeros(mS, 1);
vp.referenceMassResidual = zeros(mS,1);
vp.referenceRepairMax = zeros(mS,1);
referenceTol = getf(opts,'referenceSupportTolerance',1e-6);
for q = 1:mS
    G = toModel(double(gt.samples{gi}(:, 1:K, q)), gt.c0(q), norm);
    vp.referenceMassResidual(q)=max(abs(sum(G(1:n,:),1)-norm.matScale))/norm.matScale;
    if any(~isfinite(G(:)))||vp.referenceMassResidual(q)>referenceTol||any(G(1:n,:)<0,'all')
        error('checkModelProperties:referenceSupport', ...
            'Projection non-expansion requires a nonnegative reference with the same active mass.');
    end
    originalG=G(1:n,:);
    G(1:n, :) = n * G(1:n, :) ./ sum(G(1:n, :), 1);     % 真值样本单精度存储，归一化后严格位于 𝓜(c)
    vp.referenceRepairMax(q)=max(vecnorm(G(1:n,:)-originalG,2,1));
    Q = raw(:, :, q);
    QP = Q;
    QP(1:n, :) = projectSimplex(Q(1:n, :), norm.matScale);
    w1raw(q) = wasserstein1(Q, G, struct('method', 'exact'));
    w1proj(q) = wasserstein1(QP, G, struct('method', 'exact'));
    ratio5(q) = w1proj(q) / max(w1raw(q), realmin);
end
vp.termW1Ratio = ratio5;
vp.termW1RatioMax = max(ratio5);
vp.w1Final = mean(w1proj);

% Independent, finite exact examples. These never use training snapshots.
vp.exactOperator = checkExactOperator();

% ---------- 网络诊断：有限测试集的最大 W1 快照变化 ----------
vp.contraction = struct('d', [], 'ratio', [], 'meanRatio', NaN, 'gamma', model.gammaFinal);
if numel(model.snaps) >= 3
    nSn = numel(model.snaps);
    Kc = min(K, 256);
    X0c = sampleSource(model.meta, n, norm.matScale, Kc * mS, cfg, rs);
    Ssn = cell(1, nSn);
    for a = 1:nSn
        sm = sampleGHM(model, gt.S0, gt.c0, gt.emb0, Kc, rs, model.snaps{a}, X0c);
        Ssn{a} = sm;
    end
    dsup = zeros(1, nSn - 1);
    for a = 1:nSn - 1
        dd = zeros(mS, 1);
        for q = 1:mS
            A1 = toModel(Ssn{a}(:, :, q), gt.c0(q), norm);
            A2 = toModel(Ssn{a + 1}(:, :, q), gt.c0(q), norm);
            dd(q) = wasserstein1(A1, A2, struct('method', 'exact'));
        end
        dsup(a) = max(dd);
    end
    vp.contraction.d = dsup;
    vp.contraction.ratio = dsup(2:end) ./ max(dsup(1:end - 1), realmin);
    vp.contraction.meanRatio = mean(vp.contraction.ratio);
end
vp.neuralDiagnostics.snapshotDistance = vp.contraction;
vp.neuralDiagnostics.snapshotDistance.scope = 'maximum over the recorded finite test set only';
vp.neuralDiagnostics.snapshotDistance.checkType = 'neural_diagnostic';

% ---------- 短缺暴露误差：断供风险误差界 ----------
GFe = full(ctx.margin.GFe);
gFe0 = ctx.margin.gFe0;
th6 = cfg.varthetaDays * max(mean(ctx.stats.deltaDbarP), 1e-6); % Same positive scale as riskValue.
Lc = max(sqrt(sum(GFe .^ 2, 2))) / (4 * th6);
J = find(any(GFe ~= 0, 1));
lhs = zeros(mS, 1);
rhs = zeros(mS, 1);
mc = zeros(mS, 1); % Empirical-measure identity: no sampling allowance is justified.
slack = zeros(mS, 1);
tolRisk = zeros(mS, 1);
for q = 1:mS
    Sm = smp(:, :, q);
    Sg = double(gt.samples{gi}(:, 1:K, q));
    if isempty(J)
        A=zeros(1,K); B=A; G=zeros(size(GFe,1),1);
    else
        A=Sm(J,:); B=Sg(J,:); G=GFe(:,J);
    end
    rb=affineRiskBound(A,ones(1,K)/K,B,ones(1,K)/K, ...
        struct('G',G,'b',gFe0,'theta',th6));
    lhs(q)=rb.lhs;
    rhs(q)=rb.rhs;
    slack(q)=rb.slack;
    tolRisk(q)=rb.tolerance;
end
vp.riskErr = table(lhs, rhs, mc, slack, tolRisk, 'VariableNames', {'RiskErr', 'LW1', 'MCerr','Slack','Tolerance'});
vp.riskErrFrac = mean(lhs <= rhs + tolRisk);
vp.riskErrL = Lc;
vp.riskErrorSpec = struct('type','empirical_measure_identity','metric','exact_w1_raw_margin_coordinates', ...
    'marginKind','dispatched_pipeline');

% ---------- 补充表 4 ----------
rows = {};
if isfield(th, 'massBalance') && ~isempty(th.massBalance)
    l1 = th.massBalance;
    rows(end + 1, :) = {'全网守恒误差 max|1ᵀx − c|/c（随机动作仿真）', '质量守恒', l1.maxConsRel, '≤ 1e−9', l1.maxConsRel <= 1e-9};
    rows(end + 1, :) = {'SOC 日变化恒等式误差（含补铁项）', '质量守恒', l1.maxSocErr, '≤ 1e−9', l1.maxSocErr <= 1e-9};
end
if isfield(th, 'criticalMass') && ~isempty(th.criticalMass)
    rows(end + 1, :) = {'c = M_crit 时对抗序列违约次数', '临界循环质量(a)', sum(th.criticalMass.table.ViolFe(startsWith(th.criticalMass.table.Case, '(a)')) + ...
        th.criticalMass.table.ViolOx(startsWith(th.criticalMass.table.Case, '(a)'))), '= 0', th.criticalMass.summary.aPass};
    rows(end + 1, :) = {'c = (1 − η)M_crit 时存在违约序列', '临界循环质量(b)', double(th.criticalMass.summary.bPass), '= 1', th.criticalMass.summary.bPass};
end
if isfield(th, 'eventRisk') && ~isempty(th.eventRisk)
    rows(end + 1, :) = {'log P_F 拟合斜率 / 理论斜率 ln q/δ^D', '事件风险', th.eventRisk.slopeFit / th.eventRisk.slopeTheory, '≈ 1', ...
        abs(th.eventRisk.slopeFit / th.eventRisk.slopeTheory - 1) <= 0.2};
    rows(end + 1, :) = {'同一固定预留缓冲与公式阈值一致比例', '事件风险', th.eventRisk.thresholdMatch, '= 1', th.eventRisk.thresholdMatch == 1};
end
rows(end + 1, :) = {'生成样本越界比例（测试状态）', '生成支撑', vp.viol, '= 0', vp.viol == 0};
rows(end + 1, :) = {'自举目标越界比例（数据集 s′）', '自举目标支撑', vp.violBoot, '= 0', vp.violBoot == 0};
rows(end + 1, :) = {'投影前生成样本守恒相对误差（单精度网络）', '零空间投影', vp.rawConsMax, '舍入误差量级', vp.rawConsMax <= 1e-4};
rows(end + 1, :) = {'源分布直线路径位于相对内部的比例', '流路径内部性', vp.interiorFrac, '= 1', vp.interiorFrac == 1};
rows(end + 1, :) = {'投影前后流匹配损失之比（最大值）', '零空间投影', vp.projLossRatioMax, '≤ 1', vp.projLossRatioMax <= 1 + 1e-12};
rows(end + 1, :) = {'生成 ODE 全程守恒相对误差（双精度）', '零空间投影', vp.odeConsErr, '≤ 1e−9', vp.odeConsErr <= 1e-9};
rows(end + 1, :) = {'终端投影后负值样本比例', '终端投影', vp.negFrac, '= 0', vp.negFrac == 0};
rows(end + 1, :) = {'投影前后与真值的 W1 距离之比（最大值）', '终端投影', vp.termW1RatioMax, '≤ 1', vp.termW1RatioMax <= 1 + 1e-9};
rows(end + 1, :) = {'精确有限状态算子、固定点与投影检查通过比例', '有限案例', mean(vp.exactOperator.table.Pass), '= 1', vp.exactOperator.pass};
rows(end + 1, :) = {'相邻快照有限测试集最大 W1 变化之比（均值）', '训练诊断', vp.contraction.meanRatio, '—', NaN};
rows(end + 1, :) = {'同一经验测度 |R̃ − R| ≤ L·W1 的状态比例', '短缺暴露误差', vp.riskErrFrac, '= 1', vp.riskErrFrac == 1};
vp.table = cell2table(rows, 'VariableNames', {'Item', 'Property', 'Value', 'Criterion', 'Pass'});
end

function [viol, consMax, negFrac] = feasStats(smp, c, n, tol)
% 原始坐标样本 D×K×M 的守恒与非负检验（相对 c）
[D, K, M] = size(smp);
X = reshape(smp(1:n, :, :), n, K * M);
cc = repelem(reshape(c, 1, []), 1, K);
if isscalar(c)
    cc = c * ones(1, K * M);
end
ce = abs(sum(X, 1) - cc) ./ cc;
ng = min(X, [], 1) ./ cc;
bad = ce > tol | ng < -tol;
viol = mean(bad);
consMax = max(ce);
negFrac = mean(ng < -tol);
if D < n
    error('checkModelProperties:dim', '维数错误。');
end
end

function [consMax, negFrac] = rawStats(raw, n)
% 模型坐标（物料分量和为 n）样本的守恒与非负统计
X = reshape(raw(1:n, :, :), n, []);
consMax = max(abs(sum(X, 1) - n)) / n;
negFrac = mean(min(X, [], 1) < -1e-9 * n);
end

function P = toDouble(P)
fn = fieldnames(P);
for m = 1:numel(fn)
    P.(fn{m}) = double(gather(P.(fn{m})));
end
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = d;
end
end
