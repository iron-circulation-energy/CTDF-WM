function r = stateReward(S, ctx, prices)
%STATEREWARD 按货币权重对状态中的物理成本数量重新赋值。
%   可选 prices.carbon/h2 替换状态中的碳价与氢价，用于固定物理结果下的奖励换算。
if nargin < 3
    prices = struct();
end
carbon = S(ctx.L.xi.carbon, :);
h2 = S(ctx.L.xi.h2, :);
if isfield(prices, 'carbon'), carbon = prices.carbon; end
if isfield(prices, 'h2'), h2 = prices.h2; end
r = -physicalQuantityCost(S(ctx.L.iZ, :), ctx, carbon, h2) / ctx.Cref;
end
