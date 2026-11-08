function fc = freeCapacity(x, g, mat, ctx, committed)
%FREECAPACITY 仓容减当前库存、全部在途与本次决策已承诺的入库发运（t）。

idx = ctx.idx;
comp = idx.nodeInv(g, mat);
cap = ctx.capInv(comp);
if mat == 1
    lines = ctx.inFe{g};
else
    lines = ctx.inOx{g};
end
intr = 0;
for e = lines
    intr = intr + sum(x(idx.q{e}));
end
if nargin < 5
    committed = zeros(ctx.topo.nE,1);
end
fc = max(cap - x(comp) - intr - sum(committed(lines)), 0);
end
