function [a, st, dg] = controllerAct(ctrl, obs, ctx, st)
%CONTROLLERACT 控制器单日决策：由观测 obs 给出外层动作 a（字段 o、bcap、beta、rho、f）。
%   st：控制器内部状态（rs 随机流、prevId 上一日联合策略编号），由 runEpisode 初始化并逐日传递。
%   dg：诊断信息（id 联合策略编号、risk 所选策略的断供风险 R_w、Q 价值估计、mpc 求解信息）。
%   所有方法使用同一观测与同一预测器输出（信息公平）。

dg = struct('id', [], 'risk', NaN, 'Q', NaN, 'mpc', []);
switch ctrl.type
    case 'fixed'
        a = policyAct(obs, ctrl.w, ctx);
        dg.id = ctrl.w.id;
    case {'gpi', 'stepwise'}
        if strcmp(ctrl.type, 'gpi')
            rm = 'ghm';
        else
            rm = 'stepwise';
        end
        opts = struct('mode', ctrl.mode, 'lambda', ctrl.lambda, 'K', ctrl.K, 'rs', st.rs, 'riskMode', rm, ...
            'gammaEval', ctrl.gammaEval, 'Tcap', ctrl.Tcap, 'prevId', st.prevId);
        [id, o] = gpiSelect(ctrl.model, obs, ctx, ctrl.lib, opts);
        w = jointPolicy(ctrl.lib, id);
        a = policyAct(obs, w, ctx);
        st.prevId = id;
        dg.id = id;
        dg.risk = o.selected.R;
        dg.Q = o.selected.Q;
    case 'gpicrn'
        if ~isfield(st, 'holdLeft') || isempty(st.holdLeft)
            st.holdLeft = 0;
        end
        if st.holdLeft <= 0 || isempty(st.prevId)
            off = ctrl.offset;
            if isfield(ctrl, 'calib') && ~isempty(ctrl.calib) && strcmpi(ctrl.mode, 'central')
                off = ctrl.calib.offset(obs.c);
            end
            o2 = struct('mode', ctrl.mode, 'lambda', ctrl.lambda, 'K', ctrl.K, 'rs', st.rs, 'offset', off, ...
                'riskMode', ctrl.riskMode, 'gammaEval', ctrl.gammaEval, 'Tcap', ctrl.Tcap);
            if isfield(ctrl, 'safeZ')
                o2.safeZ = ctrl.safeZ;
                o2.baseId = ctrl.baseId;
            end
            [id, o] = gpiSelectCRN(ctrl.model, obs, ctx, ctrl.lib, o2);
            st.holdLeft = ctrl.holdDays;
            dg.risk = o.selected.R;
            dg.Q = o.selected.Q;
        else
            id = st.prevId;
        end
        st.holdLeft = st.holdLeft - 1;
        w = jointPolicy(ctrl.lib, id);
        a = policyAct(obs, w, ctx);
        st.prevId = id;
        dg.id = id;
    case 'mpc'
        [a, mi] = stochasticMPC(obs, ctx, ctrl.mpc, st.rs);
        dg.mpc = mi;
    otherwise
        error('controllerAct:type', '未知控制器类型 %s。', ctrl.type);
end
end
