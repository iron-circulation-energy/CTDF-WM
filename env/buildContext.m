function ctx = buildContext(p, topo, idx, Tl, stats)
%BUILDCONTEXT 汇总环境、策略、MPC 与世界模型共用的静态信息。
%   包含：状态布局 L、电厂与还原站份额、名义效率、节点进出线路表、库存容量、
%   铁裕度与锈裕度的仿射系数（—(16)）、荷电状态掩码、内层调度模板与区域映射。
%   stats 可为空（数据采集前），之后由 runExperiments 写入 ctx.stats。

if nargin < 5
    stats = [];
end
ctx.p = p;
ctx.topo = topo;
ctx.idx = idx;
ctx.Tl = Tl;
ctx.H = Tl.H;
ctx.stats = stats;
ctx.L = stateLayout(topo, idx);
ctx.Cref = 1;                                    % 奖励缩放，由数据集日成本均值设定
ctx.shareP = p.plant.pmax(:) / sum(p.plant.pmax);
ctx.shareR = p.station.pRedMax(:) / sum(p.station.pRedMax);
ctx.etaNom = p.plant.etaSt(:);
ctx.eRedNom = p.iron.hFe * p.station.kappa(:) ./ p.station.etaEl(:) + p.station.epsAux(:);

nN = topo.nNodes;
ctx.inFe = cell(nN, 1);
ctx.outFe = cell(nN, 1);
ctx.inOx = cell(nN, 1);
ctx.outOx = cell(nN, 1);
for g = 1:nN
    ctx.inFe{g} = find(topo.to == g & topo.mat == 1)';
    ctx.outFe{g} = find(topo.from == g & topo.mat == 1)';
    ctx.inOx{g} = find(topo.to == g & topo.mat == 2)';
    ctx.outOx{g} = find(topo.from == g & topo.mat == 2)';
end

ctx.capInv = [p.plant.capFe(:); p.plant.capOx(:); p.station.capFe(:); p.station.capOx(:); ...
    p.hub.capFe(:); p.hub.capOx(:)];
ctx.capacityMap = buildCapacityMap(idx);
ctx.safeFe = p.plant.safetyFe(:);
ctx.safeOx = p.station.safetyOx(:);
ctx.ironMask = (idx.matOf == 1);

% 运价（元/t 铁当量）：锈按实际质量计费
ctx.lineCostPerT = zeros(topo.nE, 1);
for e = 1:topo.nE
    if topo.mode(e) == 1
        unit = p.transport.railCost;
    else
        unit = p.transport.waterCost;
    end
    massFactor = 1;
    if topo.mat(e) == 2
        massFactor = p.iron.oxMassRatio;
    end
    ctx.lineCostPerT(e) = unit * topo.L(e) * massFactor;
end

% 裕度仿射系数：μ = G·s + g0（s 为原始状态向量）
L = ctx.L;
H = ctx.H;
GFe = zeros(topo.nP, L.D);
gFe0 = zeros(topo.nP, 1);
for i = 1:topo.nP
    g = topo.P(i);
    GFe(i, idx.IFe(i)) = 1;
    for e = ctx.inFe{g}
        cells = idx.q{e}(1:min(H, topo.tau(e)));
        GFe(i, cells) = 1;
    end
    GFe(i, L.xi.EH) = -ctx.shareP(i) / (ctx.etaNom(i) * p.iron.hFe);
    gFe0(i) = -ctx.safeFe(i);
end
GOx = zeros(topo.nR, L.D);
gOx0 = zeros(topo.nR, 1);
for j = 1:topo.nR
    g = topo.R(j);
    GOx(j, idx.SOx(j)) = 1;
    for e = ctx.inOx{g}
        cells = idx.q{e}(1:min(H, topo.tau(e)));
        GOx(j, cells) = 1;
    end
    GOx(j, L.xi.AH) = -ctx.shareR(j) / ctx.eRedNom(j);
    gOx0(j) = -ctx.safeOx(j);
end
ctx.margin.GFe = sparse(GFe);
ctx.margin.gFe0 = gFe0;
ctx.margin.GOx = sparse(GOx);
ctx.margin.gOx0 = gOx0;
ctx.margin.kind = 'dispatched_pipeline';
ctx.margin.H = H;

% 区域映射与内层调度模板
ctx.grid = buildPTDF(p, topo);
ctx.lpT = buildInnerLPTemplate(p, ctx.grid);
end
