function T = predictionAccuracyRows(smp, gt, g, model, ctx, seed, method, plan, rawX)
%PREDICTIONACCURACYROWS Preserve one observed error for each conditioning state.
% W1 is a legacy column name: distanceMethod determines whether it is exact
% Euclidean empirical W1 or sqrt(D)-scaled sliced W1 in model coordinates.
if nargin<9, rawX=[]; end
nS=size(gt.S0,2);
if size(smp,2)~=plan.modelSamples || size(smp,3)~=nS
    error('predictionAccuracyRows:shape','Model samples must match the declared budget and state count.');
end
gam=gt.gammas(g);
distanceMethod="exact";
if max(plan.modelSamples,plan.referenceSamples)>ctx.p.exp.exactW1Max
    distanceMethod="scaled_sliced";
end
solverMethod='exact';
if distanceMethod=="scaled_sliced", solverMethod='sliced'; end
year=nan(nS,1); day=nan(nS,1);
if isfield(gt,'year') && numel(gt.year)==nS, year=gt.year(:); end
if isfield(gt,'day') && numel(gt.day)==nS, day=gt.day(:); end
w1=nan(nS,1); ve=w1; ce=w1; cet=w1; cr=w1; nf=w1; re=w1; pm=w1; pt=w1;
for q=1:nS
    X=smp(:,:,q);
    Y=double(gt.samples{g}(:,:,q)); % Never silently discard reference samples.
    w1(q)=wasserstein1(toModel(X,gt.c0(q),model.norm),toModel(Y,gt.c0(q),model.norm), ...
        struct('method',solverMethod,'nDirs',ctx.p.exp.slicedDirs,'seed',q));
    prices=struct('carbon',gt.S0(ctx.L.xi.carbon,q),'h2',gt.S0(ctx.L.xi.h2,q));
    qm=mean(stateReward(X,ctx,prices))/(1-gam);
    qt=mean(stateReward(Y,ctx,prices))/(1-gam);
    ve(q)=abs(qm-qt)/max(abs(qt),1e-9);
    mat=X(1:ctx.L.n,:);
    cet(q)=max(abs(sum(mat,1)-gt.c0(q)));
    ce(q)=cet(q)/gt.c0(q);
    nf(q)=mean(min(mat,[],1)<-1e-9*gt.c0(q));
    % 断供风险误差：模型与真值样本中“任一电厂铁裕度为负”的概率之差（风险感知决策直接使用该量）
    try
        mF=computeMargins(X,ctx,ctx.margin); tF=computeMargins(Y,ctx,ctx.margin);
        pm(q)=mean(min(mF,[],1)<0); pt(q)=mean(min(tF,[],1)<0); re(q)=abs(pm(q)-pt(q));
    catch
    end
    if ~isempty(rawX)
        cr(q)=max(abs(sum(rawX(1:model.norm.n,:,q),1)-model.norm.matScale))/model.norm.matScale;
    end
end
T=table(repmat({method},nS,1),repmat(gam,nS,1),repmat(1/(1-gam),nS,1),(1:nS)',year,day, ...
    repmat(seed,nS,1),w1,ve,ce,nf,cet,cr,'VariableNames', ...
    {'Method','gamma','Horizon','state','year','day','seed','W1','ValueErr','ConsErr','NegFrac','ConsErrT','RawConsRel'});
T.RiskErr=re; T.RiskModel=pm; T.RiskTrue=pt;
T.distanceMethod=repmat(distanceMethod,nS,1);
fields={'modelSamples','referenceSamples','referenceTcap','modelTcap','referenceTail','modelTail','tailMismatch'};
for k=1:numel(fields), T.(fields{k})=repmat(plan.(fields{k}),nS,1); end
T.samplePolicy=repmat(string(plan.samplePolicy),nS,1);
T.metricSpace=repmat("model_coordinates",nS,1);
paths=NaN;
if isfield(gt,'independentContinuationCount'), paths=gt.independentContinuationCount;
elseif isfield(gt,'R'), paths=gt.R; end
T.independentReferencePaths=repmat(paths,nS,1);
end
