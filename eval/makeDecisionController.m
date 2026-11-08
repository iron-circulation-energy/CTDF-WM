function ctrl = makeDecisionController(dec, name, model, lib, extra)
%MAKEDECISIONCONTROLLER 按验证集选定的决策规则构造学习类方法的控制器（M1、M3、M4 与 E5 各要素对照模型共用）。
%   dec：决策规则（runExperiments 的“决策规则选定”块）：
%     mode   'distributed'、'central' 或 'centralCal'（集中式 + 训练年价值校准）
%     hold   选定后保持的天数；lambda 风险权重；safeZ、baseId 以基准固定策略为锚的安全改进（gpiSelectCRN）
%     truth  TruthStore（centralCal 时使用，各模型共用）；w0 参考固定策略（校准状态取其训练年轨迹）
%     reg    containers.Map，按 extra.key 缓存各模型的 CalibStore，避免重复标定
%   extra：K、riskMode（'ghm'/'stepwise'）、gammaEval、Tcap、terminalProj、key。
%   所有学习类方法使用同一规则，候选价值均以公共随机数估计（gpiSelectCRN）。
if nargin < 5
    extra = struct();
end
if isfield(extra, 'terminalProj') && ~isempty(extra.terminalProj)
    model.cfg.useTerminalProj = logical(extra.terminalProj);
end
K = getf(extra, 'K', model.cfg.K);
riskMode = getf(extra, 'riskMode', 'ghm');
opts = struct('lambda', dec.lambda, 'K', K, 'holdDays', dec.hold, 'riskMode', riskMode, ...
    'gammaEval', getf(extra, 'gammaEval', 0.99), 'Tcap', getf(extra, 'Tcap', 200), ...
    'safeZ', getf(dec, 'safeZ', 0), 'baseId', getf(dec, 'baseId', []));
switch lower(dec.mode)
    case 'distributed'
        opts.mode = 'distributed';
    case 'central'
        opts.mode = 'central';
    case 'centralcal'
        opts.mode = 'central';
        key = getf(extra, 'key', name);
        if isfield(dec, 'reg') && ~isempty(dec.reg) && isKey(dec.reg, key)
            opts.calib = dec.reg(key);
        else
            ropt = struct('mode', riskMode, 'gammaEval', opts.gammaEval, 'Tcap', opts.Tcap);
            opts.calib = CalibStore(dec.truth, model, dec.w0, K, ropt);
            if isfield(dec, 'reg') && ~isempty(dec.reg)
                dec.reg(key) = opts.calib;
            end
        end
    otherwise
        error('makeDecisionController:mode', '未知决策方式 %s。', dec.mode);
end
ctrl = makeController('gpicrn', name, model, lib, opts);
if opts.safeZ ~= 0
    ctrl.cacheTag = sprintf('z%g', opts.safeZ);     % 回合缓存按安全改进阈值区分，z 改变时不误用旧回合
end
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = d;
end
end
