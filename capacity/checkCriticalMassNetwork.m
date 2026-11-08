function out = checkCriticalMassNetwork(ctx, W, years, cm, lib, opts)
%CHECKCRITICALMASSNETWORK 临界循环质量在完整网络环境中的检查。
%   流体、有界扰动、无容量约束与事件间可恢复条件下的检查见 checkCriticalMass。
%   本函数在完整环境（整数日、内层线性规划、机组组合、料仓与运力约束、载体老化）中运行 policyBaseStock，
%   在气象片段中注入对抗事件族（DU：D_max 天低风光 → 间隔 → U_max 天富余；UD：顺序相反），
%   比较 c = M_crit 与 c = (1 − η)·M_crit 时的裕度违约天数、失负荷与锈阻塞弃电，
%   反映整数日、容量约束与时滞对缓冲设计的影响。
%   opts 字段：eta（默认 p.exp.bufferEta(end)）、gap（默认 p.exp.networkEventGap）、warm（默认 p.exp.warmup）、seed。
%   输出 out.table：工况、事件族、铁裕度为负天数、锈裕度为负天数、失负荷（MWh）、锈阻塞弃电（MWh）、首次铁裕度违约日。

p = ctx.p;
if nargin < 6
    opts = struct();
end
eta = getf(opts, 'eta', p.exp.bufferEta(end));
gap = getf(opts, 'gap', p.exp.networkEventGap);
warm = getf(opts, 'warm', p.exp.warmup);
seed = getf(opts, 'seed', p.seed + 31);
st = ctx.stats;
Dm = max(1, round(st.Dmax));
Um = max(1, round(st.Umax));
w = policyBaseStock(ctx, lib);
fams = {'DU', 'UD'};
cases = {'c = M_crit', 1.0; sprintf('c = (1 − %.2f)·M_crit', eta), 1 - eta};
y = years(1);
L = warm + 2 * (gap + Dm + gap + Um) + gap;
L = min(L, p.weather.daysPerYear);
rows = {};
for m = 1:size(cases, 1)
    for f = 1:numel(fams)
        seg = buildSegment(W(y), 1, L, p);
        ev = {};
        k = warm + gap;
        for r = 1:2
            for typ = fams{f}
                if typ == 'D'
                    ev{end + 1} = struct('type', 'drought', 'start', k + 1, 'days', Dm); %#ok<AGROW>
                    k = k + Dm + gap;
                else
                    ev{end + 1} = struct('type', 'surplus', 'start', k + 1, 'days', Um); %#ok<AGROW>
                    k = k + Um + gap;
                end
            end
        end
        ev = ev(cellfun(@(e) e.start + e.days - 1 <= L, ev));
        [seg, cap] = injectExtremes(seg, ev, p, ctx.topo);
        env = IronRustEnv(ctx);
        env.reset(seed, cases{m, 2} * cm.M_crit, p.exp.initSOC, struct('seg', seg, 'capSched', cap));
        nFe = 0;
        nOx = 0;
        shed = 0;
        rb = 0;
        first = NaN;
        for t = 1:L
            [muFe, muOx] = env.margins();
            if t > warm
                if any(muFe < 0)
                    nFe = nFe + 1;
                    if isnan(first)
                        first = t;
                    end
                end
                nOx = nOx + any(muOx < 0);
            end
            a = policyAct(env.getObs(), w, ctx);
            info = env.step(a);
            if t > warm
                shed = shed + info.shed;
                rb = rb + info.rustBlockMWh;
            end
        end
        rows(end + 1, :) = {cases{m, 1}, cases{m, 2}, fams{f}, nFe, nOx, shed, rb, first}; %#ok<AGROW>
    end
end
out.table = cell2table(rows, 'VariableNames', {'Case', 'cOverMcrit', 'Family', 'DaysFeNeg', 'DaysOxNeg', ...
    'ShedMWh', 'RustBlockMWh', 'FirstFeDay'});
out.note = '完整网络环境：整数日、容量约束与运输时滞下的缓冲表现。';
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = d;
end
end
