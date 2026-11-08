function lib = policyLibrary(p, topo, stats, seed)
%POLICYLIBRARY 参数化基准库存型策略库。
%   智能体：每座电厂、每个还原站、一个物流主体。各类智能体的子库由四种命名原型
%   （保守囤铁型、积极发电型、均衡型、基准库存型）与拉丁超立方采样（p.policy.nLhs 个）组成。
%   参数（单位）：（第五个命名原型 anticipatory 为前瞻补货型，其余命名原型 fwd = 0）
%     电厂   kRes（储备，低风光日数，以 δ̄^D_i 为单位）、band（过渡带，低风光日数）、thNH3（掺氨阈值，储备比例）
%     还原站 kapRho（计划还原比例）、kOx（锈目标，富余日数，以 δ̄^U_j 为单位）
%     物流   omega（电厂补货目标，低风光日数）、psi（回运比例）、hubDays（枢纽周转库存，日数）、
%            fwd（前瞻补货系数：电厂补货目标另加 fwd × 未来 H 日必需燃铁量预测，H = ⌈T_loop⌉）
%   联合策略编号 id = [电厂子库编号(nP); 还原站子库编号(nR); 物流子库编号]，
%   策略嵌入为各子库参数按取值范围归一化后的拼接（维数 3·nP + 2·nR + 4）。
%   lib.candidates 为 GPI 候选联合策略（全体同原型 + p.ctdf.nRandCand 个随机组合，种子固定）。

if nargin < 4
    seed = p.seed;
end
rg = p.policy.ranges;
kB = max(4, round(quantileLin(stats.Druns, 0.9)));
names = {'conservative', 'aggressive', 'balanced', 'basestock', 'anticipatory'};
plantProto = [20, 4, 0.8; 0, 1, 0.0; 8, 3, 0.4; kB, 2, 0.5; kB, 2, 0.5];
stationProto = [1.0, 12; 1.0, 5; 1.0, 8; 1.0, 10; 1.0, 10];
logProto = [22, 1.0, 3, 0; 6, 1.0, 1, 0; 12, 0.8, 2, 0; kB, 1.0, 2, 0; kB, 1.0, 2, 1.0];

rs = RandStream('twister', 'Seed', seed + 101);
nL = p.policy.nLhs;
plantLhs = lhsScaled(nL, [rg.kRes; rg.band; rg.thNH3], rs);
stationLhs = lhsScaled(nL, [rg.kapRho; rg.kOx], rs);
logLhs = lhsScaled(nL, [rg.omega; rg.psi; rg.hubDays; rg.fwd], rs);
lhsNames = arrayfun(@(m) sprintf('lhs%d', m), 1:nL, 'UniformOutput', false);

lib.names = [names, lhsNames];
lib.plant = array2table([plantProto; plantLhs], 'VariableNames', {'kRes', 'band', 'thNH3'});
lib.station = array2table([stationProto; stationLhs], 'VariableNames', {'kapRho', 'kOx'});
lib.logistics = array2table([logProto; logLhs], 'VariableNames', {'omega', 'psi', 'hubDays', 'fwd'});
lib.nOpt = numel(lib.names);
lib.nP = topo.nP;
lib.nR = topo.nR;
lib.nAgents = topo.nP + topo.nR + 1;
lib.ranges = rg;
lib.dimEmb = 3 * topo.nP + 2 * topo.nR + 4;
lib.kB = kB;

% GPI 候选：全体同原型 + 随机组合
aligned = zeros(lib.nAgents, numel(names));
for m = 1:numel(names)
    aligned(:, m) = m;
end
nRand = p.ctdf.nRandCand;
randC = randi(rs, lib.nOpt, lib.nAgents, nRand);
lib.candidates = unique([aligned, randC]', 'rows', 'stable')';
lib.alignedIds = aligned;
end

function X = lhsScaled(n, ranges, rs)
% 拉丁超立方采样：每维分 n 层，层内均匀抖动，各维独立置换。
d = size(ranges, 1);
X = zeros(n, d);
if n == 0
    return;
end
for j = 1:d
    perm = randperm(rs, n);
    u = (perm' - rand(rs, n, 1)) / n;
    X(:, j) = ranges(j, 1) + u * (ranges(j, 2) - ranges(j, 1));
end
end
