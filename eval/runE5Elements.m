function e5 = runE5Elements(C, gt, abl, lib, years, seeds, epDir)
%RUNE5ELEMENTS E5 各要素贡献：CTDF-WM 与四个单要素对照模型，分别用于度量
%   速度零空间投影、终端投影、Dirichlet 源与 γ 课程带来的提升。对每个模型与种子：
%     守恒误差      最终样本（含该设置下的终端投影与否）的 max|1ᵀx − c|，单位 t（另报投影前的相对误差）；
%     负值样本比例  含负物料分量（< −1e−9·c）的样本比例；
%     分布距离      最终 γ 下的经验 W1 或 scaled_sliced 距离（模型坐标；算法另列）；
%     断供风险      以该模型做风险感知 GPI 的闭环断供概率 pF（工况 p.exp.e5Scenarios，测试年份 × 种子）。
%   abl：结构体数组，字段 name、label、factory（@(seed) 模型）、terminalProj（逻辑值或 []）。
%   epDir（可选）：断点续跑的逐回合缓存目录（见 evalEpisodes；控制器名为 abl(a).name）。
%   输出 e5.table（补充表 3，天气年份均值与 95% 置信区间）、e5.raw（逐种子结果），
%   predictionRaw（逐状态预测记录）及 predictionSummary（先种子、再状态、再年份聚合）。

if nargin < 7
    epDir = '';
end
p = C.p;
ctx = C.ctx;
ctx.p=p;
gi = numel(gt.gammas);
raw = {};
episodeTables={};
predictionTables={};
for a = 1:numel(abl)
    for s = seeds(:)'
        model = abl(a).factory(s);
        if ~isempty(abl(a).terminalProj)
            model.cfg.useTerminalProj = logical(abl(a).terminalProj);
        end
        rs = RandStream('twister', 'Seed', 1000 * s + a);
        plan=predictionSamplingPlan(p,gt,gi,abl(a).name);
        [smp, rawX] = sampleGHM(model, gt.S0, gt.c0, gt.emb0, plan.modelSamples, rs);
        P=predictionAccuracyRows(smp,gt,gi,model,ctx,s,abl(a).name,plan,rawX);
        P.Label=repmat({abl(a).label},height(P),1);
        predictionTables{end+1}=P; %#ok<AGROW>
        PS=summarizePredictionAccuracy(P);
        if isfield(C, 'decision') && ~isempty(C.decision)
            % 与 M1 相同的决策规则（公共随机数；分布式/集中式与价值校准按验证集选定），各对照模型分别标定
            ctrl = makeDecisionController(C.decision, abl(a).name, model, lib, struct('K', p.ctdf.K, ...
                'terminalProj', abl(a).terminalProj, 'key', sprintf('%s_s%d', abl(a).name, s)));
        else
            ctrl = makeController('gpi', abl(a).name, model, lib, struct('terminalProj', abl(a).terminalProj));
        end
        specs = makeEvalSpecs(p, years, s, p.exp.e5Scenarios, C.cNominal);
        [~, T] = evalEpisodes(ctx, C.W, specs, ctrl, [], epDir);
        T.element=repmat({abl(a).name},height(T),1);
        episodeTables{end+1}=T; %#ok<AGROW>
        raw(end + 1, :) = {abl(a).name, abl(a).label, s, max(P.ConsErrT), max(P.RawConsRel), ...
            PS.NegFrac, PS.W1, mean(T.pF), mean(T.shedMWh), mean(T.cost), PS.distanceMethod}; %#ok<AGROW>
    end
end
R = cell2table(raw, 'VariableNames', {'Name', 'Label', 'Seed', 'ConsErrT', 'RawConsRel', 'NegFrac', 'W1', ...
    'pF', 'ShedMWh', 'Cost', 'DistanceMethod'});
e5.raw = R;
e5.predictionRaw=vertcat(predictionTables{:});
[e5.predictionSummary,e5.predictionMetadata]=summarizePredictionAccuracy(e5.predictionRaw);
methods=unique(e5.predictionSummary.distanceMethod);
e5.DistanceMethod="mixed";
if numel(methods)==1, e5.DistanceMethod=methods; end
e5.episodes=vertcat(episodeTables{:});
e5.annualSummary=statsUtils('summaryTable',e5.episodes,{'element','scenario'},{'pF','eventF','shedMWh','cost'});
annualOverall=statsUtils('summaryTable',e5.episodes,{'element'},{'pF','shedMWh'});
e5.note='Prediction and closed-loop intervals use weather years; exact and sliced distances are reported separately; noTerminal removes the projection at inference.';
rows = cell(0, 14);
for a = 1:numel(abl)
    sel = strcmp(R.Name, abl(a).name);
    pred=e5.predictionSummary(strcmp(e5.predictionSummary.Method,abl(a).name),:);
    mw=NaN; lw=NaN; hw=NaN; dm="mixed";
    if height(pred)==1
        mw=pred.W1; lw=pred.W1lo; hw=pred.W1hi; dm=pred.distanceMethod;
    end
    annual=annualOverall(strcmp(annualOverall.element,abl(a).name),:);
    rows(end + 1, :) = {abl(a).name, abl(a).label, max(R.ConsErrT(sel)), max(R.RawConsRel(sel)), ...
        100 * mean(R.NegFrac(sel)), mw, lw, hw, annual.pF_mean, annual.pF_lo, annual.pF_hi, ...
        annual.shedMWh_mean, nnz(sel), dm}; %#ok<AGROW>
end
e5.table = cell2table(rows, 'VariableNames', {'Name', 'Label', 'ConsErrT', 'RawConsRel', 'NegPct', 'W1', 'W1lo', ...
    'W1hi', 'pF', 'pFlo', 'pFhi', 'ShedMWh', 'nSeeds', 'DistanceMethod'});
end
