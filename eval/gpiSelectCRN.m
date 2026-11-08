function [id, out] = gpiSelectCRN(model, obs, ctx, lib, opts)
%GPISELECTCRN 风险感知 GPI 的单日选择，候选价值用公共随机数估计（riskValueCRN）。
%   opts 字段：
%     mode       'central'：w* = argmax_w [Q̃_w(s) + b_w − λ·R_w(s)]，候选集为 lib.candidates；
%                'distributed'：从当日集中式最优出发，按 电厂 → 还原站 → 物流 的顺序，各智能体固定其余智能体的选择，
%                只在本地子库中选择，使用系统价值与本节点风险（电厂 R^Fe_i，还原站 R^Ox_j，物流 max_i R^Fe_i），
%                迭代一轮最优响应（与 gpiSelect 相同）；同一日内的全部评估共用同一组源样本。
%     lambda、K、rs
%     offset     1×nCand 价值校准偏移 b_w（只用于 'central'，缺省 0；见 CalibStore）
%     riskMode   'ghm'（缺省）或 'stepwise'；gammaEval、Tcap 为 'stepwise' 的参数
%     safeZ、baseId  安全改进（只用于 'central'）：baseId 为基准固定策略（M0）的候选编号列，最优候选相对基准的
%                预测增益不超过 safeZ 个配对标准误时保持基准；safeZ = 0（缺省）不启用
%   输出 out：selected（id、Q、R）、central（Q、R、score、best）、nEval。

mode = lower(getf(opts, 'mode', 'central'));
lambda = getf(opts, 'lambda', 0);
K = getf(opts, 'K', model.cfg.K);
rs = getf(opts, 'rs', RandStream('twister', 'Seed', 1));
rmode = getf(opts, 'riskMode', 'ghm');
ropt = struct('mode', rmode, 'gammaEval', getf(opts, 'gammaEval', 0.99), 'Tcap', getf(opts, 'Tcap', 200));
if strcmpi(rmode, 'ghm')
    ropt.X0 = sampleSource(model.meta, model.norm.n, model.norm.matScale, K, model.cfg, rs);
end
cands = lib.candidates;
E = embeddingsFromIds(lib, cands);
rv = riskValueCRN(model, obs.s, obs.c, E, ctx, rs, K, ropt);
offset = getf(opts, 'offset', []);
if isempty(offset) || ~strcmp(mode, 'central')
    offset = zeros(1, size(cands, 2));
end
score = rv.Q + reshape(offset, 1, []) - lambda * rv.R;
[~, b] = max(score);
% 以验证选定的固定策略为基准的安全改进：只有当最优候选相对基准的预测增益超过 safeZ 个配对标准误时才偏离基准
% （公共随机数下逐样本配对，标准误 = std(Q̃_b,k − Q̃_0,k)/√K）；safeZ = 0 时即为原规则。
safeZ = getf(opts, 'safeZ', 0);
baseId = getf(opts, 'baseId', []);
out.safe = struct('gated', false, 'gain', NaN, 'se', NaN);
if safeZ > 0 && ~isempty(baseId) && strcmp(mode, 'central')
    i0 = find(all(cands == baseId(:), 1), 1);
    if ~isempty(i0) && b ~= i0
        g = score(b) - score(i0);
        se = std(rv.Qk(:, b) - rv.Qk(:, i0)) / sqrt(size(rv.Qk, 1));
        out.safe = struct('gated', g < safeZ * se, 'gain', g, 'se', se);
        if g < safeZ * se
            b = i0;
        end
    end
end
id = cands(:, b);
out.central = struct('Q', rv.Q, 'R', rv.R, 'score', score, 'best', b);
out.selected = struct('id', id, 'Q', rv.Q(b), 'R', rv.R(b));
out.nEval = size(cands, 2);
if strcmp(mode, 'distributed')
    cur = id;
    nP = lib.nP;
    nR = lib.nR;
    for a = 1:lib.nAgents
        ids = repmat(cur, 1, lib.nOpt);
        ids(a, :) = 1:lib.nOpt;
        rva = riskValueCRN(model, obs.s, obs.c, embeddingsFromIds(lib, ids), ctx, rs, K, ropt);
        if a <= nP
            localRisk = rva.nodeFe(a, :);
        elseif a <= nP + nR
            localRisk = rva.nodeOx(a - nP, :);
        else
            localRisk = max(rva.nodeFe, [], 1);
        end
        [~, ob] = max(rva.Q - lambda * localRisk);
        cur(a) = ob;
        out.selected = struct('id', cur, 'Q', rva.Q(ob), 'R', rva.R(ob));
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
