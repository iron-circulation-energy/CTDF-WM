function dg = runDiagGPI(C, model, lib, w0, lam, years, seed, epDir)
%RUNDIAGGPI CTDF-WM 决策层诊断（只用验证年份，不训练、不改模型参数）。
%   A 闭环对比：验证年 × 常规工况 × 名义循环质量，比较
%       M0          固定参考策略（候选集内验证成本最低者）
%       M1dist      论文设置：分布式最优响应，K = p.ctdf.K，λ = 调参值
%       M1cen       集中式：每日在全部候选联合策略中取 Q̃ − λR 最大者
%       M1cenK4     集中式，K 取 4 倍（检验价值估计的抽样噪声）
%     集中式候选集包含 M0 本身，若价值排序可靠，M1cen 不应差于 M0。
%   B 价值排序探针：沿 M0 轨迹（第一个验证年）每隔 probeEvery 天取一个状态，对全部候选
%     用两组独立随机流各估计一次 Q̃ 与 R，报告：两次排序的 Spearman 相关（价值排序可重复性）、
%     候选间 Q̃ 的离散度与抽样标准误之比、M0 在候选中的名次、R 在候选间的极差（风险项是否饱和）。
%   epDir：逐回合缓存目录（断点续跑）。输出 dg：closed（逐回合表）、closedSummary、probe（逐状态表）、probeSummary。

p = C.p;
ctx = C.ctx;
W = C.W;
c = C.cNominal;
K = p.ctdf.K;
specs = makeEvalSpecs(p, years, seed, {'normal'}, c);

% ---------- A 闭环对比 ----------
vars = struct('name', {'M0', 'M1dist', 'M1cen', 'M1cenK4'}, ...
    'ctrl', {makeController('fixed', 'M0', w0), ...
    makeController('gpi', 'M1dist', model, lib, struct('lambda', lam, 'K', K, 'mode', 'distributed')), ...
    makeController('gpi', 'M1cen', model, lib, struct('lambda', lam, 'K', K, 'mode', 'central')), ...
    makeController('gpi', 'M1cenK4', model, lib, struct('lambda', lam, 'K', 4 * K, 'mode', 'central'))});
Tall = {};
for v = 1:numel(vars)
    t0 = tic;
    [~, T] = evalEpisodes(ctx, W, specs, vars(v).ctrl, [], epDir);
    T.variant = repmat({vars(v).name}, height(T), 1);
    Tall{end + 1} = T; %#ok<AGROW>
    fprintf('诊断 A：%s 完成（%d 回合，%.1f min）。\n', vars(v).name, height(T), toc(t0) / 60);
end
E = vertcat(Tall{:});
dg.closed = E;
nm = {vars.name}';
mcols = {'cost', 'shedMWh', 'eventF', 'pF', 'curRate', 'rustBlockMWh', 'decTime'};
S = zeros(numel(nm), numel(mcols));
for v = 1:numel(nm)
    sel = strcmp(E.variant, nm{v});
    for k = 1:numel(mcols)
        S(v, k) = mean(E.(mcols{k})(sel), 'omitnan');
    end
end
dg.closedSummary = [table(nm, 'VariableNames', {'variant'}), array2table(S, 'VariableNames', mcols)];

% ---------- B 价值排序探针 ----------
probeEvery = 12;
sp = specs(1);
[seg, cap] = buildEvalSegment(ctx, W, sp);
env = IronRustEnv(ctx);
env.reset(sp.seed, sp.c, sp.initSOC, struct('seg', seg, 'capSched', cap, 'initMode', 'deterministic'));
cands = lib.candidates;
nC = size(cands, 2);
E0 = embeddingsFromIds(lib, cands);
iM0 = find(all(cands == w0.id(:), 1), 1);
if isempty(iM0)
    iM0 = NaN;
end
rs1 = RandStream('twister', 'Seed', 7001);
rs2 = RandStream('twister', 'Seed', 7002);
ropt = struct('K', K, 'mode', 'ghm');
rows = {};
for t = 1:sp.len
    obs = env.getObs();
    if t > sp.warmup && mod(t - sp.warmup, probeEvery) == 1
        r1 = riskValue(model, obs.s, obs.c, E0, ctx, rs1, ropt);
        r2 = riskValue(model, obs.s, obs.c, E0, ctx, rs2, ropt);
        q1 = r1.Q(:);
        q2 = r2.Q(:);
        rho = spearman(q1, q2);
        se = std(q1 - q2) / sqrt(2);                      % 单次估计的抽样标准误（候选间平均）
        spread = std((q1 + q2) / 2);                      % 候选间价值离散度
        qm = (q1 + q2) / 2;
        [~, ord] = sort(qm, 'descend');
        rk = NaN;
        if isfinite(iM0)
            rk = find(ord == iM0, 1);
        end
        Rm = (r1.R(:) + r2.R(:)) / 2;
        [mf, ~] = computeMargins(obs.s, ctx);
        rows(end + 1, :) = {t - sp.warmup, rho, spread / max(se, eps), rk, nC, min(Rm), max(Rm), ...
            candName(lib, cands(:, ord(1))), ord(1), min(mf)}; %#ok<AGROW>
    end
    a = policyAct(obs, w0, ctx);
    env.step(a);
end
dg.probe = cell2table(rows, 'VariableNames', {'day', 'spearmanQ', 'snrQ', 'rankM0', 'nCand', 'Rmin', 'Rmax', ...
    'topName', 'topIdx', 'minMuFe'});
P = dg.probe;
dg.probeSummary = struct('nStates', height(P), 'medianSpearman', median(P.spearmanQ, 'omitnan'), ...
    'medianSNR', median(P.snrQ, 'omitnan'), 'fracM0Top1', mean(P.rankM0 == 1), ...
    'medianRankM0', median(P.rankM0, 'omitnan'), 'medianRrange', median(P.Rmax - P.Rmin, 'omitnan'), ...
    'medianRmin', median(P.Rmin, 'omitnan'), 'iM0', iM0, 'nCand', nC);
end

function s = candName(lib, id)
if all(id == id(1)) && id(1) <= numel(lib.names)
    s = lib.names{id(1)};
else
    s = ['mix[' sprintf('%d', id) ']'];
end
end

function r = spearman(a, b)
ra = rankv(a);
rb = rankv(b);
r = corr1(ra, rb);
end

function r = rankv(x)
[~, o] = sort(x(:));
r = zeros(numel(x), 1);
r(o) = 1:numel(x);
end

function r = corr1(a, b)
a = a - mean(a);
b = b - mean(b);
r = sum(a .* b) / max(sqrt(sum(a .^ 2) * sum(b .^ 2)), eps);
end
