function ps = buildScaledCase(p, nPl)
%BUILDSCALEDCASE E7 规模扩展算例：把改造电厂数扩展到 nPl 座。
%   保留原算例的还原站、枢纽与“还原站—枢纽”线路；电厂 P1..P_nPl 依次接入各枢纽（铁路，正向铁线路 H→P、
%   反向锈线路 P→H，时延 1~3 d 循环，长度 300 + 50·mod(k−1, 10) km）；电厂参数按原算例循环复制。
%   风光装机、负荷、备用容量、还原功率与“还原站—枢纽”线路运力、枢纽容量按电厂总容量之比同比缩放，
%   保持各类资源的相对规模不变（PLACEHOLDER 生成规则，只用于计时）。
%   输出 ps：新的参数结构体（已调用 deriveParams）。

if isempty(p.hub.names)
    error('buildScaledCase:hub', '规模扩展算例要求原算例至少有一个枢纽。');
end
nP0 = numel(p.plant.pmax);
cyc = @(v) v(1 + mod((1:nPl)' - 1, nP0));
ps = p;
names = arrayfun(@(k) sprintf('P%d', k), (1:nPl)', 'UniformOutput', false);
fs = sum(cyc(p.plant.pmax)) / sum(p.plant.pmax);
% 节点
nodes = p.net.nodes;
keep = ~strcmp(nodes(:, 2), 'P');
plantRegion = nodes(strcmp(nodes(:, 2), 'P'), 3);
newP = [names, repmat({'P'}, nPl, 1), plantRegion(1 + mod((1:nPl)' - 1, nP0))];
ps.net.nodes = [nodes(keep, :); newP];
% 线路：保留还原站—枢纽线路，新增枢纽—电厂线路
lines = p.net.lines;
typeOf = containers.Map(nodes(:, 1), nodes(:, 2));
keepL = false(size(lines, 1), 1);
for e = 1:size(lines, 1)
    keepL(e) = ~strcmp(typeOf(lines{e, 1}), 'P') && ~strcmp(typeOf(lines{e, 2}), 'P');
end
base = lines(keepL, :);
for e = 1:size(base, 1)
    base{e, 7} = base{e, 7} * fs;
end
hubs = p.hub.names(:);
nH = numel(hubs);
add = cell(2 * nPl, 7);
for k = 1:nPl
    h = hubs{1 + mod(k - 1, nH)};
    tau = 1 + mod(k - 1, 3);
    Lk = 300 + 50 * mod(k - 1, 10);
    add(2 * k - 1, :) = {h, names{k}, 'Fe', 'rail', tau, Lk, 6.0e4};
    add(2 * k, :) = {names{k}, h, 'Ox', 'rail', tau, Lk, 6.0e4};
end
ps.net.lines = [base; add];
% 电厂参数
fld = {'pmax', 'pmin', 'ramp', 'etaSt', 'loss', 'betaMax', 'cop', 'remainLife', 'bookValueFrac'};
for m = 1:numel(fld)
    ps.plant.(fld{m}) = cyc(p.plant.(fld{m})(:));
end
ps.plant.names = names;
% 资源同比缩放
ps.re.capW = p.re.capW * fs;
ps.re.capS = p.re.capS * fs;
ps.load.mean = p.load.mean * fs;
ps.backup.pmax = p.backup.pmax * fs;
ps.station.pRedMax = p.station.pRedMax * fs;
ps.hub.capFe = p.hub.capFe * fs;
ps.hub.capOx = p.hub.capOx * fs;
ps.retire.selected = 1:nPl;
ps = deriveParams(ps);
end
