function [total, components] = physicalQuantityCost(Z, ctx, carbon, h2)
%PHYSICALQUANTITYCOST Price physical daily quantities without changing the transition kernel.
%   Z has the stateLayout z ordering, one column per sample. Prices are scalars
%   or row vectors. Revaluation is valid for fixed physical outcomes; changing
%   dispatch prices may change those outcomes and requires renewed evaluation.
p = ctx.p;
q = ctx.L.z;
carbon = reshape(carbon, 1, []);
h2 = reshape(h2, 1, []);
op = p.plant.cop(:)' * Z(q.plantMWh, :) + ...
    (p.backup.fuelCost + p.backup.ef * carbon) .* Z(q.backupMWh, :) + ...
    (p.cost.nh3Base + p.cost.nh3PerH2 * h2) .* Z(q.ammoniaMWh, :);
components = [op; ctx.lineCostPerT(:)' * Z(q.shipmentTonnes, :); ...
    p.cost.cHold * Z(q.holdingTonnes, :); p.cost.cMk * Z(q.makeupTonnes, :); ...
    p.cost.piCur * Z(q.curtailMWh, :); p.cost.piShed * Z(q.shortageMWh, :); ...
    p.cost.overflowPenalty * Z(q.overflowTonnes, :)];
total = sum(components, 1);
end
