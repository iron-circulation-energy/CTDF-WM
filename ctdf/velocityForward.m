function V = velocityForward(net, X, cond, wEmb, t, meta, c)
%VELOCITYFORWARD 速度场 v_θ(X_t | s, w, t) 前向计算（列为样本；支持 dlarray 与数值数组）。
%   X：D×B（模型坐标），cond：(D+1)×B，wEmb：dimW×B，t：1×B（流时间 ∈ [0,1]）。
%   输出 V：D×B（未投影；物料分量的零空间投影由 nullSpaceProj 完成）。

if nargin < 7
    c = velocityCondition(net, cond, wEmb);
end
te = sinusoidalEmbed(t, meta.dT);
tau = net.Wt2 * mish(net.Wt1 * te + net.bt1) + net.bt2;
e = [c; tau];
h = net.Win * X + net.bin;
for b = 1:meta.nBlocks
    g = net.(sprintf('Wg%d', b)) * e + net.(sprintf('bg%d', b));
    bt = net.(sprintf('Wb%d', b)) * e + net.(sprintf('bb%d', b));
    hn = layerNormFeat(h) .* (1 + g) + bt;
    u = mish(net.(sprintf('W1%d', b)) * hn + net.(sprintf('b1%d', b)));
    h = h + net.(sprintf('W2%d', b)) * u + net.(sprintf('b2%d', b));
end
V = net.Wout * layerNormFeat(h) + net.bout;
end

function y = mish(x)
sp = max(x, 0) + log(1 + exp(-abs(x)));
y = x .* tanh(sp);
end

function y = layerNormFeat(h)
mu = mean(h, 1);
d = h - mu;
v = mean(d .^ 2, 1);
y = d ./ sqrt(v + 1e-5);
end
