function o = minCover(need, pmax, pmin, ok, enumMax)
%MINCOVER 机组组合：选择总最小出力最小、且总容量不低于 need（MW）的电厂集合。
%   ok 为可开机电厂（铁与掺氨足以满足全日最小发电量）。可开机容量不足时全部开机。
%   电厂数不超过 enumMax 时枚举全部子集，否则按容量降序贪心加入、再按容量升序剔除冗余。

pmax = pmax(:);
pmin = pmin(:);
ok = logical(ok(:));
n = numel(pmax);
o = false(n, 1);
cand = find(ok);
if isempty(cand) || need <= 0
    return;
end
if sum(pmax(cand)) < need
    o(cand) = true;
    return;
end
m = numel(cand);
if m <= enumMax
    best = inf;
    bestMask = [];
    for code = 1:(2 ^ m - 1)
        mask = bitget(code, 1:m)' == 1;
        S = cand(mask);
        if sum(pmax(S)) >= need
            v = sum(pmin(S)) + 1e-6 * numel(S);
            if v < best
                best = v;
                bestMask = S;
            end
        end
    end
    o(bestMask) = true;
else
    [~, ord] = sort(pmax(cand), 'descend');
    capOn = 0;
    for r = 1:m
        if capOn >= need
            break;
        end
        o(cand(ord(r))) = true;
        capOn = capOn + pmax(cand(ord(r)));
    end
    on = find(o);
    [~, ord2] = sort(pmax(on), 'ascend');
    for r = 1:numel(on)
        i = on(ord2(r));
        if capOn - pmax(i) >= need
            o(i) = false;
            capOn = capOn - pmax(i);
        end
    end
end
end
