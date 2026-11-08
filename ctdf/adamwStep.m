function [net, avgG, avgSq, gnorm] = adamwStep(net, grads, avgG, avgSq, iter, lr, cfg, meta)
%ADAMWSTEP AdamW 更新：先对权重矩阵执行解耦权重衰减 θ ← θ − η·λ_wd·θ，再调用 adamupdate。
%   梯度先按全局 2-范数裁剪到 cfg.gradClip。偏置不做权重衰减。

fn = fieldnames(grads);
sq = 0;
for m = 1:numel(fn)
    g = extractdata(grads.(fn{m}));
    sq = sq + sum(g(:) .^ 2);
end
gnorm = sqrt(double(gather(sq)));
if gnorm > cfg.gradClip
    scale = cfg.gradClip / gnorm;
    grads = dlupdate(@(g) g * scale, grads);
end
for m = 1:numel(meta.weightFields)
    f = meta.weightFields{m};
    net.(f) = net.(f) - lr * cfg.wd * net.(f);
end
[net, avgG, avgSq] = adamupdate(net, grads, avgG, avgSq, iter, lr, cfg.beta1, cfg.beta2, cfg.epsAdam);
end
