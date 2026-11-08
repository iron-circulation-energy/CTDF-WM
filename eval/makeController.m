function ctrl = makeController(type, name, varargin)
%MAKECONTROLLER 构造评估用控制器。
%   ctrl = makeController('fixed', name, w)
%       固定联合策略 π_w（M0 参考策略、临界循环质量基准库存策略等）。
%   ctrl = makeController('gpi', name, model, lib, opts)
%       基于几何时域模型的风险感知 GPI：M1 CTDF-WM、M4 无守恒 TD-Flow 与 E5 各单要素对照模型。
%       opts 字段：lambda（缺省 model.cfg.lambda）、K（缺省 model.cfg.K）、mode（'central'/'distributed'，
%       缺省 model.cfg.gpiMode）、terminalProj（逻辑值，缺省沿用 model.cfg.useTerminalProj；E5 度量终端投影贡献的对照模型置 false）。
%   ctrl = makeController('stepwise', name, model, lib, opts)
%       M3 逐步推演世界模型：一步模型逐步展开 T ~ Geometric(1 − γ_eval) 步（截断于 Tcap），其余与 M1 相同。
%       opts 字段：lambda、K、gammaEval（缺省 0.99）、Tcap、mode。
%   ctrl = makeController('mpc', name, mpcData)
%       M2 随机 MPC（mpcSetup 的输出）。
%   输出 ctrl：type、name 及各类型所需字段。

ctrl.type = lower(type);
ctrl.name = name;
switch ctrl.type
    case 'fixed'
        ctrl.w = varargin{1};
    case {'gpi', 'stepwise'}
        model = varargin{1};
        ctrl.lib = varargin{2};
        opts = struct();
        if numel(varargin) >= 3
            opts = varargin{3};
        end
        if isfield(opts, 'terminalProj') && ~isempty(opts.terminalProj)
            model.cfg.useTerminalProj = logical(opts.terminalProj);
        end
        ctrl.model = model;
        ctrl.lambda = getf(opts, 'lambda', model.cfg.lambda);
        ctrl.K = getf(opts, 'K', model.cfg.K);
        ctrl.mode = getf(opts, 'mode', model.cfg.gpiMode);
        ctrl.gammaEval = getf(opts, 'gammaEval', 0.99);
        ctrl.Tcap = getf(opts, 'Tcap', 200);
    case 'gpicrn'
        % 风险感知 GPI，候选价值用公共随机数估计（gpiSelectCRN）。opts：mode（'central'/'distributed'）、lambda、K、
        % holdDays（选定后保持的天数，缺省 1）、calib（CalibStore，集中式价值校准，缺省无）、offset（固定偏移）、
        % riskMode（'ghm'/'stepwise'）、gammaEval、Tcap、terminalProj（E5 终端投影对照）、
        % safeZ 与 baseId（以基准固定策略为锚的安全改进，见 gpiSelectCRN）。
        model = varargin{1};
        ctrl.lib = varargin{2};
        opts = struct();
        if numel(varargin) >= 3
            opts = varargin{3};
        end
        if isfield(opts, 'terminalProj') && ~isempty(opts.terminalProj)
            model.cfg.useTerminalProj = logical(opts.terminalProj);
        end
        ctrl.model = model;
        ctrl.mode = getf(opts, 'mode', 'central');
        ctrl.lambda = getf(opts, 'lambda', model.cfg.lambda);
        ctrl.K = getf(opts, 'K', model.cfg.K);
        ctrl.holdDays = getf(opts, 'holdDays', 1);
        ctrl.offset = getf(opts, 'offset', []);
        ctrl.calib = getf(opts, 'calib', []);
        ctrl.riskMode = getf(opts, 'riskMode', 'ghm');
        ctrl.gammaEval = getf(opts, 'gammaEval', 0.99);
        ctrl.Tcap = getf(opts, 'Tcap', 200);
        ctrl.safeZ = getf(opts, 'safeZ', 0);
        ctrl.baseId = getf(opts, 'baseId', []);
    case 'mpc'
        ctrl.mpc = varargin{1};
    otherwise
        error('makeController:type', '未知控制器类型 %s。', type);
end
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = d;
end
end
