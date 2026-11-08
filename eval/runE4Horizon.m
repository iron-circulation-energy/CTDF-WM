function e4 = runE4Horizon(C, gt, models, seed)
%RUNE4HORIZON E4 长时域预测精度：γ ∈ gt.gammas 下比较 M1、M3、M4。
%   M1、M4：取 γ 课程中训练到该 γ 的阶段目标网络（model.stage(g).ema）一次采样；
%   M3：一步模型逐步展开 T ~ Geometric(1 − γ) 步（截断于 p.exp.stepwiseTcap），每步施加终端投影；
%   与 groundTruthSM 的真值样本比较：
%     W1        保留的兼容列名；distanceMethod 区分精确经验 W1 与 sqrt(D) 缩放切片距离；
%     valueErr  |Q̃ − Q| / |Q|，Q = mean r(X)/(1 − γ)，r = −1ᵀz/C_ref；
%     consErr   最终样本的最大守恒相对误差 max|1ᵀx − c|/c；negFrac 含负分量的样本比例。
%   models：结构体，字段 M1、M3、M4（缺失的方法跳过）。
%   输出 e4.raw：逐状态/年/种子/γ 记录；e4.table：先种子再状态再天气年份聚合，
%   95% CI 基于天气年份均值；无来源年份或不足两年时 CI 为 NaN。

p = C.p;
ctx = C.ctx;
rs = RandStream('twister', 'Seed', seed + 401);
mS = size(gt.S0, 2);
ctx.p=p;
rawTables = {};
names = intersect({'M1', 'M3', 'M4'}, fieldnames(models), 'stable');
for g = 1:numel(gt.gammas)
    gam = gt.gammas(g);
    for a = 1:numel(names)
        mdl = models.(names{a});
        if isempty(mdl)
            continue;
        end
        gi = [];
        if ~strcmp(names{a}, 'M3')
            gi = find(abs([mdl.stage.gamma] - gam) < 1e-9, 1);
            if isempty(gi)
                continue;                      % 该模型未训练到此 γ（例如时域课程的对照模型）
            end
        end
        plan=predictionSamplingPlan(p,gt,g,names{a});
        K=plan.modelSamples;
        samples=zeros(size(gt.S0,1),K,mS);
        for q = 1:mS
            switch names{a}
                case 'M3'
                    rv = riskValue(mdl, gt.S0(:, q), gt.c0(q), gt.emb0(:, q), ctx, rs, ...
                        struct('mode', 'stepwise', 'gammaEval', gam, 'Tcap', p.exp.stepwiseTcap, 'K', K, 'keepSamples', true));
                    smp = rv.samples(:, :, 1);
                otherwise
                    smp = sampleGHM(mdl, gt.S0(:, q), gt.c0(q), gt.emb0(:, q), K, rs, mdl.stage(gi).ema);
            end
            samples(:,:,q)=smp;
        end
        rawTables{end+1}=predictionAccuracyRows(samples,gt,g,mdl,ctx,seed,names{a},plan); %#ok<AGROW>
    end
end
if isempty(rawTables)
    error('runE4Horizon:noModels','No model stage matches the requested discounts.');
end
e4.raw=vertcat(rawTables{:});
[e4.table,e4.metadata]=summarizePredictionAccuracy(e4.raw);
e4.Tloop = C.Tl.mean;
e4.truncMass = nan(size(gt.gammas));
if isfield(gt,'truncMass'), e4.truncMass=gt.truncMass; end
e4.note='All reference samples retained; exactW1Max selects the distance algorithm only. Tail mismatches are reported without truncating either comparison sample set.';
end
