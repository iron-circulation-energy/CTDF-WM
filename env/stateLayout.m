function L = stateLayout(topo, idx)
%STATELAYOUT 原始状态向量 s = [x; ξ; aux; z] 的布局。
%   x   （n 维）物料状态，按 buildStateIndex 顺序，单位 t（铁当量）；
%   ξ   （22+nE+nR 维）外生状态：当日风光与负荷日电量（归一化）、气象状态独热、AR 残差、日序正余弦、
%        碳价、氢价、当日派生量（must0、may0、absorb0、peakMust0、peakMay0），以及
%        前 3 日与前 H 日的必需电量和 E3、EH、可吸收电量和 A3、AH（MWh），以及当日已观测线路/还原可用率；
%        不包含未来故障安排。压力测试的未知故障过程不由正常气象核自动解释。
%   aux （nInv + nE + nP 维）载体品质指数（各库存分量与各线路）与上一日末小时出力；
%   z   上一日物理成本驱动量（MWh、t），价格由 physicalQuantityCost 显式赋权。
%   info.z 仍保留七类货币成本，长度为 L.nCost；模型状态中的 z 不存储价格加权结果。

L.n = idx.n;
L.xiNames = {'EW', 'ES', 'EL', 'reg1', 'reg2', 'reg3', 'eW', 'eS', 'eL', 'sinDoy', 'cosDoy', ...
    'carbon', 'h2', 'must0', 'may0', 'absorb0', 'peakMust0', 'peakMay0', 'E3', 'EH', 'A3', 'AH'};
baseXi = numel(L.xiNames);
L.xiNames = [L.xiNames, arrayfun(@(k)sprintf('lineAvail%d',k),1:topo.nE,'UniformOutput',false), ...
    arrayfun(@(k)sprintf('reductionAvail%d',k),1:topo.nR,'UniformOutput',false)];
L.nXi = numel(L.xiNames);
L.nAux = idx.nInv + topo.nE + topo.nP;
L.costNames = {'op', 'logistics', 'holding', 'makeup', 'curtail', 'shed', 'overflow'};
L.nCost = numel(L.costNames);
L.z.plantMWh = 1:topo.nP;
L.z.backupMWh = topo.nP + 1;
L.z.ammoniaMWh = topo.nP + 2;
L.z.shipmentTonnes = topo.nP + 2 + (1:topo.nE);
k = topo.nP + topo.nE + 2;
L.z.holdingTonnes = k + 1;
L.z.makeupTonnes = k + 2;
L.z.curtailMWh = k + 3;
L.z.shortageMWh = k + 4;
L.z.overflowTonnes = k + 5;
L.zNames = [arrayfun(@(i) sprintf('plantMWh%d', i), 1:topo.nP, 'UniformOutput', false), ...
    {'backupMWh', 'ammoniaMWh'}, ...
    arrayfun(@(i) sprintf('shipmentTonnes%d', i), 1:topo.nE, 'UniformOutput', false), ...
    {'holdingTonnes', 'makeupTonnes', 'curtailMWh', 'shortageMWh', 'overflowTonnes'}];
L.nZ = numel(L.zNames);
L.D = L.n + L.nXi + L.nAux + L.nZ;
L.iX = (1:L.n)';
L.iXi = L.n + (1:L.nXi)';
L.iAux = L.n + L.nXi + (1:L.nAux)';
L.iZ = L.n + L.nXi + L.nAux + (1:L.nZ)';
L.iOther = (L.n + 1:L.D)';
L.xi = struct();
for m = 1:L.nXi
    L.xi.(L.xiNames{m}) = L.iXi(m);
end
L.xi.Fcap = L.iXi(baseXi + (1:topo.nE));
L.xi.rhoAvail = L.iXi(baseXi + topo.nE + (1:topo.nR));
L.aux.gInv = L.iAux(1:idx.nInv);
L.aux.gLine = L.iAux(idx.nInv + (1:topo.nE));
L.aux.pLast = L.iAux(idx.nInv + topo.nE + (1:topo.nP));
end
