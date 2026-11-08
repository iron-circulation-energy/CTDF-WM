function a = waterfill(E, cap, wts)
%WATERFILL 按权重分配总量 E，单项不超过上限 cap（注水法），超出部分在未饱和项之间按权重再分配。
%   用于把系统必需电量与可替代电量分配到各电厂。总量超过 Σcap 时截断为 Σcap。

cap = max(cap(:), 0);
wts = max(wts(:), 0);
n = numel(cap);
a = zeros(n, 1);
E = min(max(E, 0), sum(cap));
free = cap > 0 & wts > 0;
rem = E;
for it = 1:n + 1
    if rem <= 1e-9 * max(1, E) || ~any(free)
        break;
    end
    ww = wts .* free;
    add = rem * ww / sum(ww);
    room = cap - a;
    over = free & (add >= room);
    if any(over)
        a(over) = cap(over);
        free = free & ~over;
        rem = E - sum(a);
    else
        a = a + add;
        rem = 0;
    end
end
end
