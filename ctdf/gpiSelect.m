function [id, out] = gpiSelect(model, obs, ctx, lib, opts)
%GPISELECT 风险感知广义策略改进：w* = argmax_w [Q̃_w(s) − λ·R_w(s)]。
%   集中式（opts.mode = 'central'）：在 lib.candidates 上评估并取最大者。
%   分布式（'distributed'）：从当日集中式最优出发，按 电厂 → 还原站 → 物流 的顺序，
%   各智能体固定其余智能体的选择，只在本地子库中选择，使用系统价值（共享奖励信号）与本节点风险：
%     电厂 i：Q̃ − λ·R^Fe_i；还原站 j：Q̃ − λ·R^Ox_j；物流主体：Q̃ − λ·max_i R^Fe_i（共享节点风险）；
%   迭代一轮最优响应。世界模型为集中训练的共享模型（CTDE）。
%   物理数量支持固定转移核下的奖励重估；若价格改变内层调度，则改变转移核，必须重新验证。
%   opts 字段：mode、lambda、K、rs、riskMode（'ghm' 或 'stepwise'）、gammaEval、Tcap、prevId。

if nargin < 5
    opts = struct();
end
mode = getf(opts, 'mode', model.cfg.gpiMode);
lambda = getf(opts, 'lambda', model.cfg.lambda);
rs = getf(opts, 'rs', RandStream('twister', 'Seed', 1));
ropt = struct('K', getf(opts, 'K', model.cfg.K), 'mode', getf(opts, 'riskMode', 'ghm'), ...
    'gammaEval', getf(opts, 'gammaEval', 0.99), 'Tcap', getf(opts, 'Tcap', 200));
s = obs.s;
c = obs.c;
cands = lib.candidates;
E = embeddingsFromIds(lib, cands);
rv = riskValue(model, s, c, E, ctx, rs, ropt);
score = rv.Q - lambda * rv.R;
[~, b] = max(score);
id = cands(:, b);
out.central = struct('Q', rv.Q, 'R', rv.R, 'score', score, 'best', b);
out.nEval = size(cands, 2);
out.selected = struct('id',id,'Q',rv.Q(b),'R',rv.R(b));
out.lastResponse = struct('Q',rv.Q,'R',rv.R,'chosen',b);
if strcmpi(mode, 'distributed')
    cur = id;
    out.initialResponseId = cur;
    nP = lib.nP;
    nR = lib.nR;
    for a = 1:lib.nAgents
        ids = repmat(cur, 1, lib.nOpt);
        ids(a, :) = 1:lib.nOpt;
        rva = riskValue(model, s, c, embeddingsFromIds(lib, ids), ctx, rs, ropt);
        if a <= nP
            localRisk = rva.nodeFe(a, :);
        elseif a <= nP + nR
            localRisk = rva.nodeOx(a - nP, :);
        else
            localRisk = max(rva.nodeFe, [], 1);
        end
        [~, ob] = max(rva.Q - lambda * localRisk);
        cur(a) = ob;
        out.selected = struct('id',cur,'Q',rva.Q(ob),'R',rva.R(ob));
        out.lastResponse = struct('Q',rva.Q,'R',rva.R,'chosen',ob);
        out.nEval = out.nEval + lib.nOpt;
    end
    id = cur;
end
out.id = id;
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = d;
end
end
