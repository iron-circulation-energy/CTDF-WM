function ds = collectDataset(ctx, W, lib, years, cNominal, seed, partDir)
%COLLECTDATASET 用行为策略在指定气象年中采集转移数据 {(s_k, w, s_{k+1})}。
%   每个回合：随机抽取气象年与起始日，循环铁总质量 c ~ cNominal·U(cRange)（cNominal 为标量时），
%   或 c ~ U(cNominal(1), cNominal(2))（cNominal 为 1×2 绝对区间时，使数据覆盖 E2 的 c 网格），
%   初始荷电状态 ~ U(socRange)，
%   物料随机初始化（initMaterial 'random'），按行为策略运行 episodeLen 天。
%   存储方式：各回合状态轨迹拼接为 ds.S（D×M，single），转移由 (from, to) 下标给出，避免重复存储 s′。
%   pert = true 的转移（行为扰动日）不满足 a = π_w(s)，训练时只作为状态来源。
%   使用 parfor（p.data.useParfor 且可用时），每回合独立随机流（种子 seed·7 + 回合号），结果可复现。
%   断点续跑：回合按块运行（每块 p.data.blockEpisodes 个，块内 parfor）。给定 partDir（可选）时，每块完成后把该块
%   各回合的输出保存为 partDir/part_<块号>.mat；再次运行时读取已有分块并跳过这些块（键不一致或文件损坏时重算该块）。
%   各回合的随机流只取决于回合号，分块与否、从哪一块继续都不改变输出。
%
%   输出 ds：S、from、to、id（(nP+nR+1)×T）、c（1×M，状态对应的循环铁质量）、pert（1×T）、
%            year、day（1×T）、ep（1×T）、cost（1×T，元/日）、info（采集设置）。

if nargin < 7
    partDir = '';
end
p = ctx.p;
L = p.data.episodeLen;
nEp = ceil(p.data.nTransitions / L);
D = ctx.L.D;
nA = lib.nAgents;
Scell = cell(nEp, 1);
idCell = cell(nEp, 1);
pertCell = cell(nEp, 1);
costCell = cell(nEp, 1);
metaCell = cell(nEp, 1);
useP = p.data.useParfor && ~isempty(ver('parallel')) && license('test', 'Distrib_Computing_Toolbox');
blk = nEp;
if isfield(p.data, 'blockEpisodes') && ~isempty(p.data.blockEpisodes)
    blk = max(1, round(p.data.blockEpisodes));
end
usePart = ~isempty(partDir);
if usePart && ~exist(partDir, 'dir')
    mkdir(partDir);
end
for b = 1:ceil(nEp / blk)
    e1 = (b - 1) * blk + 1;
    e2 = min(nEp, b * blk);
    key = struct('schemaVersion', 2, 'seed', seed, 'episodes', [e1, e2], 'nEp', nEp, 'L', L, ...
        'years', years, 'cNominal', cNominal, 'p', p, 'lib', lib, 'layout', ctx.L, 'weather', W(years));
    fPart = '';
    if usePart
        fPart = fullfile(partDir, sprintf('part_%04d.mat', b));
        P = loadPart(fPart, key);
        if ~isempty(P)                   % 该块已完成：直接读取
            Scell(e1:e2) = P.S;
            idCell(e1:e2) = P.id;
            pertCell(e1:e2) = P.pert;
            costCell(e1:e2) = P.cost;
            metaCell(e1:e2) = P.meta;
            continue;
        end
    end
    if useP
        parfor ep = e1:e2
            [Scell{ep}, idCell{ep}, pertCell{ep}, costCell{ep}, metaCell{ep}] = ...
                runOneEpisode(ep, ctx, W, lib, years, cNominal, seed, L, D, nA);
        end
    else
        for ep = e1:e2
            [Scell{ep}, idCell{ep}, pertCell{ep}, costCell{ep}, metaCell{ep}] = ...
                runOneEpisode(ep, ctx, W, lib, years, cNominal, seed, L, D, nA);
        end
    end
    if usePart                           % 块级保存（在 parfor 循环体之外）
        savePart(fPart, struct('key', key, 'S', {Scell(e1:e2)}, 'id', {idCell(e1:e2)}, ...
            'pert', {pertCell(e1:e2)}, 'cost', {costCell(e1:e2)}, 'meta', {metaCell(e1:e2)}));
    end
end
M = nEp * (L + 1);
ds.S = zeros(D, M, 'single');
ds.c = zeros(1, M);
T = nEp * L;
ds.from = zeros(1, T);
ds.to = zeros(1, T);
ds.id = zeros(nA, T);
ds.pert = false(1, T);
ds.year = zeros(1, T);
ds.day = zeros(1, T);
ds.ep = zeros(1, T);
ds.cost = zeros(1, T);
for ep = 1:nEp
    base = (ep - 1) * (L + 1);
    ds.S(:, base + (1:L + 1)) = single(Scell{ep});
    ds.c(base + (1:L + 1)) = metaCell{ep}.c;
    tb = (ep - 1) * L;
    ds.from(tb + (1:L)) = base + (1:L);
    ds.to(tb + (1:L)) = base + (2:L + 1);
    ds.id(:, tb + (1:L)) = idCell{ep};
    ds.pert(tb + (1:L)) = pertCell{ep};
    ds.year(tb + (1:L)) = metaCell{ep}.year;
    ds.day(tb + (1:L)) = metaCell{ep}.d0 + (0:L - 1);
    ds.ep(tb + (1:L)) = ep;
    ds.cost(tb + (1:L)) = costCell{ep};
    Scell{ep} = [];                     % Release trajectory storage as the final dataset is assembled.
    idCell{ep} = []; pertCell{ep} = []; costCell{ep} = [];
end
ds.info = struct('nEp', nEp, 'episodeLen', L, 'years', years, 'cNominal', cNominal, 'seed', seed, ...
    'nUnperturbed', nnz(~ds.pert), 'policyCoverage', accumarray(ds.id(:), 1, [lib.nOpt, 1])');
end

function [S, ids, pert, cost, meta] = runOneEpisode(ep, ctx, W, lib, years, cNominal, seed, L, D, nA)
p = ctx.p;
rs = RandStream('twister', 'Seed', seed * 7 + ep);
y = years(randi(rs, numel(years)));
starts = validWeatherStarts(W(y), p, L + 1, years);
if isempty(starts)
    error('collectDataset:window', 'Year %d has no complete episode within the requested split.', y);
end
d0 = starts(randi(rs, numel(starts)));
seg = buildSegment(W(y), d0, L, p);
if numel(cNominal) == 2
    c = cNominal(1) + diff(cNominal) * rand(rs);
else
    c = cNominal * (p.data.cRange(1) + diff(p.data.cRange) * rand(rs));
end
soc = p.data.socRange(1) + diff(p.data.socRange) * rand(rs);
env = IronRustEnv(ctx);
env.reset(seed * 7 + ep, c, soc, struct('seg', seg, 'initMode', 'random'));
S = zeros(D, L + 1, 'single');
ids = zeros(nA, L);
pert = false(1, L);
cost = zeros(1, L);
bs = struct();
S(:, 1) = env.stateVector();
for t = 1:L
    obs = env.getObs();
    [a, pt, bs] = behaviorPolicy(obs, bs, lib, ctx, rs);
    info = env.step(a);
    S(:, t + 1) = env.stateVector();
    ids(:, t) = bs.id;
    pert(t) = pt;
    cost(t) = info.cost;
end
meta = struct('c', c, 'year', y, 'd0', d0);
end

function P = loadPart(f, key)
% 读取已完成的分块；文件不存在、无法读取或键（种子、回合范围、回合长度、年份、c 区间）不一致时返回空
P = [];
if ~isfile(f)
    return;
end
try
    S = load(f);
    if isfield(S, 'key') && isequaln(S.key, key)
        P = S;
    end
catch
    P = [];
end
end

function savePart(f, P)
% 原子保存分块：先写同目录临时文件，再改名覆盖
[fd, nm] = fileparts(f);
tmp = fullfile(fd, [nm, '.tmp.mat']);
save(tmp, '-struct', 'P', '-v7.3');
movefile(tmp, f, 'f');
end
