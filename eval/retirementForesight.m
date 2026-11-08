function res = retirementForesight(ctx, wx, retro, opts)
%RETIREMENTFORESIGHT 退役反事实的有限预见版本：替代方案按滚动 W 天预见调度，其余与 retirementCounterfactual 相同。
%   res = retirementForesight(ctx, wx, retro, opts)
%   retirementCounterfactual 的替代方案调度为逐小时完全预见（对替代方案有利）；改造情景的控制器只用条件期望预测，
%   本函数使二者的信息条件对称。做法：以与 retirementCounterfactual 完全相同的二分法序列（同一 Pmax、迭代次数与容差）
%   求替代功率，每个功率下的评估期调度改用 storageDispatchRolling；把得到的 P—(EUE, 运行成本, 弃电, 风光电量)
%   作为缓存传给 retirementCounterfactual，由其计算年化成本与保留资产价值（计算方法不变、不再调用完全预见调度）。
%   opts 字段：type（缺省 p.retire.type）、foresightDays（缺省 p.retire.foresightDays，须为有限值）、
%             waterValueMult（给定时不调参）、vGrid（候选，缺省 p.retire.waterValueGrid）、
%             Pref（调参的参考功率，缺省为改造电厂总容量；diagE1acct 传入完全预见下的替代功率）。
%   输出 res：retirementCounterfactual 的全部字段，另含 foresight（days、vMult、vGrid、tuneCost、Pref）。

p = ctx.p;
if nargin < 4
    opts = struct();
end
typ = getf(opts, 'type', p.retire.type);
sp = p.retire.(typ);
fd = getf(opts, 'foresightDays', getf(p.retire, 'foresightDays', 3));
if ~isfinite(fd)
    error('retirementForesight:days', '有限预见天数须为有限值（完全预见请用 retirementCounterfactual）。');
end
Ppl = sum(p.plant.pmax);
Pmax = 3 * Ppl;
[wu, wt] = uniqueProfiles(wx);
vGrid = getf(opts, 'vGrid', getf(p.retire, 'waterValueGrid', [0.5, 0.8, 1, 1.2, 1.5, 2, 3]));
vMult = getf(opts, 'waterValueMult', []);
Pref = getf(opts, 'Pref', Ppl);
cst = nan(size(vGrid));
if isempty(vMult)
    for g = 1:numel(vGrid)
        cst(g) = 0;
        for m = 1:numel(wu)
            rg = storageDispatchRolling(wu{m}, Pref, sp, p, fd, vGrid(g));
            cst(g) = cst(g) + wt(m) * rg.op;
        end
    end
    [~, gb] = min(cst);
    vMult = vGrid(gb);
end
cache = struct('P', [], 'eue', [], 'op', [], 'cur', [], 'RE', []);
eueTolerance = max(retro.eueMWh * p.retire.eueTol, p.exp.eueAbsTol);
eueT = retro.eueMWh + eueTolerance;
% 与 retirementCounterfactual 相同的二分法序列
[r0, cache] = evalP(0, cache);
if r0.eue > eueT
    [rM, cache] = evalP(Pmax, cache);
    if rM.eue <= eueT
        lo = 0;
        hi = Pmax;
        for it = 1:p.retire.bisectIter
            mid = 0.5 * (lo + hi);
            [rm, cache] = evalP(mid, cache);
            if rm.eue <= eueT
                hi = mid;
            else
                lo = mid;
            end
        end
    end
end
res = retirementCounterfactual(ctx, wx, retro, struct('type', typ, 'cache', cache));
res.foresight = struct('days', fd, 'vMult', vMult, 'vGrid', vGrid, 'tuneCost', cst, 'Pref', Pref);
res.informationBoundary = sprintf(['Replacement dispatched with rolling %g-day foresight (storage value %.2f x backup ', ...
    'fuel-and-carbon cost, tuned in-sample); retrofit under realised control.'], fd, vMult);

    function [out, cache] = evalP(P, cache)
        hit = find(abs(cache.P - P) <= 1e-9 * max(1, P), 1);
        if ~isempty(hit)
            out = struct('eue', cache.eue(hit), 'op', cache.op(hit), 'cur', cache.cur(hit), 'RE', cache.RE(hit));
            return;
        end
        out = struct('eue', 0, 'op', 0, 'cur', 0, 'RE', 0);
        for m = 1:numel(wu)
            if P > 0
                o1 = storageDispatchRolling(wu{m}, P, sp, p, fd, vMult);
            else
                o1 = storageDispatchLP(wu{m}, P, sp, p);     % 无储能时两种口径相同
            end
            out.eue = out.eue + wt(m) * o1.eue;
            out.op = out.op + wt(m) * o1.op;
            out.cur = out.cur + wt(m) * o1.cur;
            out.RE = out.RE + wt(m) * o1.RE;
        end
        cache.P(end + 1) = P;
        cache.eue(end + 1) = out.eue;
        cache.op(end + 1) = out.op;
        cache.cur(end + 1) = out.cur;
        cache.RE(end + 1) = out.RE;
    end
end

function [wu, wt] = uniqueProfiles(wx)
% 合并逐小时风光、负荷与碳价完全相同的评估期（不同种子共用同一气象年），wt 为重复次数
wu = {};
wt = [];
for m = 1:numel(wx)
    hit = 0;
    for q = 1:numel(wu)
        if isequal(wu{q}.RE, wx{m}.RE) && isequal(wu{q}.D, wx{m}.D) && isequal(wu{q}.carbon, wx{m}.carbon)
            hit = q;
            break;
        end
    end
    if hit
        wt(hit) = wt(hit) + 1;
    else
        wu{end + 1} = wx{m}; %#ok<AGROW>
        wt(end + 1) = 1; %#ok<AGROW>
    end
end
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = d;
end
end
