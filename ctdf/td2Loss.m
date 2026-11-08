function [loss, grads, l1, l2] = td2Loss(net, Xt1, u1, Xt2, u2, cond, wEmb, t, gamma, meta, cfg)
%TD2LOSS 守恒约束 TD²-CFM 损失及其对网络参数的梯度（供 dlfeval 调用）。
%   L(θ) = (1−γ)·E‖P·v_θ(X_t | s, w, t) − (S′ − X_0)‖² + γ·E‖P·v_θ(X̂_t | s, w, t) − P·v_θ̄(X̂_t | s′, w, t)‖²
%   第一项：X_t = (1−t)·X_0 + t·S′（直线路径），回归一步转移的条件速度；
%   第二项：X̂_t 为目标网络在条件 (s′, w) 下自 X_0 积分到 t 的状态，回归目标网络的投影速度（自举）。
%   Dirichlet 源下两项目标满足 1ᵀu_mat = 0，投影不增加损失。
%   采用 Gaussian 源的对照模型，其一步目标不满足该条件。
%   γ = 0 时只含第一项（逐步推演模型 M3 的一步模型）。损失按维数 D 平均。
%   输入 Xt1、u1、Xt2、u2、cond、wEmb、t 为数值数组；net 为 dlarray 参数结构体。

D = meta.dimX;
c = velocityCondition(net, cond, wEmb);
v1 = velocityForward(net, Xt1, cond, wEmb, t, meta, c);
if cfg.useNullSpaceProj
    v1 = nullSpaceProj(v1, cfg.nMat);
end
l1 = mean(sum((v1 - u1) .^ 2, 1)) / D;
if gamma > 0
    v2 = velocityForward(net, Xt2, cond, wEmb, t, meta, c);
    if cfg.useNullSpaceProj
        v2 = nullSpaceProj(v2, cfg.nMat);
    end
    l2 = mean(sum((v2 - u2) .^ 2, 1)) / D;
    loss = (1 - gamma) * l1 + gamma * l2;
else
    l2 = 0 * l1;
    loss = l1;
end
grads = dlgradient(loss, net);
end
