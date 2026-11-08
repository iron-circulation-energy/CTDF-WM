function Emin = plantMinEnergy(p, pLast)
%PLANTMINENERGY 开机时全日最小发电量（MWh），计及最小出力与自上一日末小时出力的下爬坡：
%   pLast > 0：Emin = Σ_{t=1}^{24} max(p̲, pLast − t·R)；pLast = 0：Emin = 24·p̲。
%   用于动作可行化（环境第 2 步）与机组组合（策略）。

pmin = p.plant.pmin(:);
R = p.plant.ramp(:);
pLast = pLast(:);
t = 1:24;
Emin = sum(max(pmin, pLast - R .* t), 2);
Emin(pLast <= 0) = 24 * pmin(pLast <= 0);
end
