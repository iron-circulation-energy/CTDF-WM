function f = eventFloor(e2, method)
%EVENTFLOOR 事件断供频率中与循环质量无关的部分 P_inf：c 位于 [M_crit, 2 M_crit] 时该方法事件断供频率的均值。
%   超过临界质量后继续增加质量不再降低这一部分，它来自电厂侧（单厂储量与放能功率）而非系统循环质量。
%   质量相关部分按 q = (P − P_inf)/(1 − P_inf) 计算，可与几何尾计算值直接比较；反之 P = P_inf + (1 − P_inf)·q_tail。
if nargin < 2 || isempty(method)
    method = 'M1';
end
Sm = e2.summary;
Mc = e2.capacity.M_crit;
m = tcol(Sm, 'method', {});
c = tcol(Sm, 'c');
y = tcol(Sm, 'eventF_mean');
sel = strcmp(m, method) & c >= Mc * (1 - 1e-9) & c <= 2 * Mc * (1 + 1e-9) & isfinite(y);
f = mean(y(sel));
if ~isfinite(f)
    f = 0;
end
f = min(max(f, 0), 0.99);
end
