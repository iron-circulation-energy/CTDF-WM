function plan = predictionSamplingPlan(p, gt, g, method)
%PREDICTIONSAMPLINGPLAN Sample budgets and stopping boundaries are independent of distance choice.
% Every reference sample is retained. Optional exp.predictionSamples controls
% only the number of generated model samples and is recorded explicitly.
plan.referenceSamples = size(gt.samples{g},2);
validateattributes(plan.referenceSamples,{'numeric'},{'scalar','positive','integer'});
plan.modelSamples = plan.referenceSamples;
plan.samplePolicy = 'all reference samples; matched model sample count';
if isfield(p.exp,'predictionSamples') && ~isempty(p.exp.predictionSamples)
    validateattributes(p.exp.predictionSamples,{'numeric'},{'scalar','real','finite','positive','integer'});
    plan.modelSamples = p.exp.predictionSamples;
    plan.samplePolicy = 'all reference samples; explicit exp.predictionSamples model budget';
end
plan.referenceTcap = NaN;
plan.referenceTail = NaN;
if isfield(gt,'Tcap') && ~isempty(gt.Tcap)
    plan.referenceTcap = gt.Tcap;
    plan.referenceTail = gt.gammas(g)^gt.Tcap;
elseif isfield(gt,'truncMass') && numel(gt.truncMass)>=g
    plan.referenceTail = gt.truncMass(g);
end
plan.modelTcap = Inf;
plan.modelTail = 0; % direct geometric-horizon model has no rollout stopping cap
if strcmp(method,'M3')
    validateattributes(p.exp.stepwiseTcap,{'numeric'},{'scalar','real','finite','positive','integer'});
    plan.modelTcap = p.exp.stepwiseTcap;
    plan.modelTail = gt.gammas(g)^plan.modelTcap;
end
plan.tailMismatch = NaN;
if isfinite(plan.referenceTail)
    plan.tailMismatch = double(abs(plan.referenceTail-plan.modelTail)>32*eps(max(1,plan.referenceTail)));
end
end
