function topo = buildTopology(p)
%BUILDTOPOLOGY 由 p.net 构造拓扑结构，并做合法性与连通性检查。
%   节点全局编号顺序固定为：还原站 R（1..nR）、电厂 P（nR+1..nR+nP）、枢纽 H（其后）。
%   线路字段：from、to（全局节点号）、mat（1=Fe，2=Ox）、mode（1=rail，2=water）、
%   tau（整数天）、L（km）、Fcap（t/d）。
%
%   合法方向：正向铁线路 R→H、H→P、R→P；反向锈线路 P→H、H→R、P→R。

N = p.net.nodes;
Lc = p.net.lines;
types = N(:, 2);
order = [find(strcmp(types, 'R')); find(strcmp(types, 'P')); find(strcmp(types, 'H'))];
if numel(order) ~= size(N, 1)
    error('buildTopology:type', '节点类型只能是 R、P、H。');
end
N = N(order, :);
topo.nodeNames = N(:, 1);
topo.nodeType = N(:, 2);
topo.nodeRegion = N(:, 3);
topo.nR = sum(strcmp(topo.nodeType, 'R'));
topo.nP = sum(strcmp(topo.nodeType, 'P'));
topo.nH = sum(strcmp(topo.nodeType, 'H'));
topo.nNodes = size(N, 1);
topo.R = (1:topo.nR)';
topo.P = topo.nR + (1:topo.nP)';
topo.H = topo.nR + topo.nP + (1:topo.nH)';

% 电厂、还原站、枢纽参数顺序必须与拓扑一致
if ~isequal(topo.nodeNames(topo.P), p.plant.names(:))
    error('buildTopology:plantOrder', 'p.plant.names 与网络中电厂节点顺序不一致。');
end
if ~isequal(topo.nodeNames(topo.R), p.station.names(:))
    error('buildTopology:stationOrder', 'p.station.names 与网络中还原站节点顺序不一致。');
end
if ~isequal(topo.nodeNames(topo.H), p.hub.names(:))
    error('buildTopology:hubOrder', 'p.hub.names 与网络中枢纽节点顺序不一致。');
end

nE = size(Lc, 1);
topo.nE = nE;
topo.from = zeros(nE, 1);
topo.to = zeros(nE, 1);
topo.mat = zeros(nE, 1);
topo.mode = zeros(nE, 1);
topo.tau = zeros(nE, 1);
topo.L = zeros(nE, 1);
topo.Fcap = zeros(nE, 1);
for e = 1:nE
    f = find(strcmp(topo.nodeNames, Lc{e, 1}));
    t = find(strcmp(topo.nodeNames, Lc{e, 2}));
    if isempty(f) || isempty(t)
        error('buildTopology:node', '线路 %d 的端点不存在。', e);
    end
    topo.from(e) = f;
    topo.to(e) = t;
    switch Lc{e, 3}
        case 'Fe'
            topo.mat(e) = 1;
        case 'Ox'
            topo.mat(e) = 2;
        otherwise
            error('buildTopology:mat', '线路 %d 的物料类型只能是 Fe 或 Ox。', e);
    end
    switch Lc{e, 4}
        case 'rail'
            topo.mode(e) = 1;
        case 'water'
            topo.mode(e) = 2;
        otherwise
            error('buildTopology:mode', '线路 %d 的运输方式只能是 rail 或 water。', e);
    end
    tau = Lc{e, 5};
    if tau < 1 || tau ~= round(tau)
        error('buildTopology:tau', '线路 %d 的时延必须是正整数天。', e);
    end
    topo.tau(e) = tau;
    topo.L(e) = Lc{e, 6};
    topo.Fcap(e) = Lc{e, 7};
end

% 方向合法性检查
ft = topo.nodeType(topo.from);
tt = topo.nodeType(topo.to);
for e = 1:nE
    pair = [ft{e}, tt{e}];
    if topo.mat(e) == 1
        ok = any(strcmp(pair, {'RH', 'HP', 'RP'}));
    else
        ok = any(strcmp(pair, {'PH', 'HR', 'PR'}));
    end
    if ~ok
        error('buildTopology:direction', '线路 %d（%s→%s）的方向与物料类型不符。', ...
            e, topo.nodeNames{topo.from(e)}, topo.nodeNames{topo.to(e)});
    end
end

% 连通性检查：全部节点须处于同一连通分量
G = graph(topo.from, topo.to, ones(nE, 1), topo.nNodes);
comp = conncomp(G);
if numel(unique(comp)) ~= 1
    error('buildTopology:connect', '网络不连通，与“多厂联合”设定不符。');
end

% 每座电厂至少有一条入厂铁线路与一条出厂锈线路；每个还原站至少有一条入站锈线路
for i = 1:topo.nP
    g = topo.P(i);
    if ~any(topo.to == g & topo.mat == 1) || ~any(topo.from == g & topo.mat == 2)
        error('buildTopology:plantLines', '电厂 %s 缺少入厂铁线路或出厂锈线路。', topo.nodeNames{g});
    end
end
for j = 1:topo.nR
    g = topo.R(j);
    if ~any(topo.to == g & topo.mat == 2) || ~any(topo.from == g & topo.mat == 1)
        error('buildTopology:stationLines', '还原站 %s 缺少入站锈线路或出站铁线路。', topo.nodeNames{g});
    end
end
end
