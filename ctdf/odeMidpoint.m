function X = odeMidpoint(net, X0, cond, wEmb, tEnd, nSteps, meta, cfg)
%ODEMIDPOINT 中点法积分生成 ODE dX/dt = P·v_θ(X | s, w, t)，从 t = 0 积分到 tEnd（逐样本）。
%   每个样本步长 h = tEnd/nSteps（TD² 自举目标使用 tEnd = t；采样使用 tEnd = 1）：
%       X_{k+1} = X_k + h·v(X_k + (h/2)·v(X_k, t_k), t_k + h/2)。
%   cfg.useNullSpaceProj 为真时速度场经零空间投影，物料分量之和全程保持不变。
%   tEnd：1×B 或标量。

B = size(X0, 2);
if isscalar(tEnd)
    tEnd = tEnd * ones(1, B, 'like', X0);
end
h = tEnd / nSteps;
X = X0;
tk = zeros(1, B, 'like', X0);
nMat = cfg.nMat;
c = velocityCondition(net, cond, wEmb);
for k = 1:nSteps
    v1 = velocityForward(net, X, cond, wEmb, tk, meta, c);
    if cfg.useNullSpaceProj
        v1 = nullSpaceProj(v1, nMat);
    end
    Xm = X + (h / 2) .* v1;
    v2 = velocityForward(net, Xm, cond, wEmb, tk + h / 2, meta, c);
    if cfg.useNullSpaceProj
        v2 = nullSpaceProj(v2, nMat);
    end
    X = X + h .* v2;
    tk = tk + h;
end
end
