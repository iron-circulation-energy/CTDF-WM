function [A,b] = mpcCapacityBlock(ctx,mpc)
%MPCCAPACITYBLOCK Conservative silo reservations at every within-day stage.
% Block X is the end-of-day material state. Undo all shipments to check the
% post-conversion/pre-shipping state, then check each destination immediately
% after its shipment in the same fixed line order used by IronRustEnv.step.
C = ctx.capacityMap;
D = C*mpc.M.Mf;
idx = ctx.idx;
lay = mpc.lay;
nInv = idx.nInv;
nE = ctx.topo.nE;
A = sparse(nInv+nE,lay.nb);
A(1:nInv,lay.iX) = C;
A(1:nInv,lay.iF) = -D;
b = [ctx.capInv;ctx.capInv(idx.lineTgt)];
for e = 1:nE
    row = nInv+e;
    dst = idx.lineTgt(e);
    A(row,lay.iX) = C(dst,:);
    later = e+1:nE;
    A(row,lay.iF(later)) = -D(dst,later);
end
end
