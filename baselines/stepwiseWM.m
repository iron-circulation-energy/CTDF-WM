function model = stepwiseWM(ds, norm, ctx, lib, cfg, opts)
%STEPWISEWM M3 逐步推演世界模型：网络结构、训练数据、优化器与 GPI 均与 M1 相同，
%   仅令 γ = 0 训练一步流模型（ 只保留第一项），训练步数预算与 M1 的 γ 课程总步数相同。
%   估计价值时由 riskValue 的 'stepwise' 模式抽取 T ~ Geometric(1 − γ_eval)，逐步展开 T 步，
%   每步施加与 M1 相同的终端投影以保持可行（见 riskValue/stepwiseRollout）。
%   输入与 trainCTDF 相同；opts.seed、opts.tag 可选；opts.ckptFile（断点续训检查点）随 opts 原样传给 trainCTDF。
%   输出 model：trainCTDF 的输出，另加 model.kind = 'stepwise'。

if nargin < 6
    opts = struct();
end
cfg.stepsPerStage = cfg.stepsPerStage * numel(cfg.gammaStages);
cfg.useGammaCurriculum = false;
opts.gammaStages = 0;
if ~isfield(opts, 'tag')
    opts.tag = 'M3-stepwise';
end
if isfield(opts, 'gtVal')
    opts = rmfield(opts, 'gtVal');            % γ = 0 的一步模型不与各 γ 的后继测度真值比较（E4 单独评估）
end
model = trainCTDF(ds, norm, ctx, lib, cfg, opts);   % opts.ckptFile（若有）保留，支持断点续训
model.kind = 'stepwise';
end
