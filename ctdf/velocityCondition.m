function c = velocityCondition(net, cond, wEmb)
%VELOCITYCONDITION Encode fixed conditioning once per ODE integration.
x = net.Wc1 * [cond; wEmb] + net.bc1;
sp = max(x, 0) + log(1 + exp(-abs(x)));
c = net.Wc2 * (x .* tanh(sp)) + net.bc2;
end
