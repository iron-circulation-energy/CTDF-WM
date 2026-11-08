function Tl = computeTloop(topo, p)
%COMPUTETLOOP 已执行的闭环运输时延与裕度预测时域 H。
%   当前日尺度环境支持到货后当日转换和发运，没有额外工序队列。
%   因此运行口径为 T_loop,i = τ^Fe_i + τ^Ox_i；它不包含排队或等待策略造成的停留。
%   p.loop 中的非零工序时滞只保存在 Tl.reference 作为假设参照，环境按线路时延执行。
%   全网 T_loop 取以电厂容量份额为权重的通量加权平均（hMode='mean'）或最大值（hMode='max'），
%   H = ceil(T_loop)。
%
%   输出字段：perPlant (nP×1, d)、tauFe、tauOx (nP×1, d)、mean、max、H、share (nP×1)。

nP = topo.nP;
INF = 1e9;
% 枢纽到达时延：任一还原站经铁线路到达枢纽 h 的最短时延
dHubFe = INF * ones(topo.nNodes, 1);
for e = 1:topo.nE
    if topo.mat(e) == 1 && strcmp(topo.nodeType{topo.from(e)}, 'R') && strcmp(topo.nodeType{topo.to(e)}, 'H')
        dHubFe(topo.to(e)) = min(dHubFe(topo.to(e)), topo.tau(e));
    end
end
% 枢纽到还原站的回运时延
dHubOx = INF * ones(topo.nNodes, 1);
for e = 1:topo.nE
    if topo.mat(e) == 2 && strcmp(topo.nodeType{topo.from(e)}, 'H') && strcmp(topo.nodeType{topo.to(e)}, 'R')
        dHubOx(topo.from(e)) = min(dHubOx(topo.from(e)), topo.tau(e));
    end
end

tauFe = INF * ones(nP, 1);
tauOx = INF * ones(nP, 1);
for i = 1:nP
    g = topo.P(i);
    for e = 1:topo.nE
        if topo.mat(e) == 1 && topo.to(e) == g
            src = topo.from(e);
            if strcmp(topo.nodeType{src}, 'R')
                tauFe(i) = min(tauFe(i), topo.tau(e));
            else
                tauFe(i) = min(tauFe(i), dHubFe(src) + topo.tau(e));
            end
        end
        if topo.mat(e) == 2 && topo.from(e) == g
            dst = topo.to(e);
            if strcmp(topo.nodeType{dst}, 'R')
                tauOx(i) = min(tauOx(i), topo.tau(e));
            else
                tauOx(i) = min(tauOx(i), topo.tau(e) + dHubOx(dst));
            end
        end
    end
end
if any(tauFe >= INF) || any(tauOx >= INF)
    error('computeTloop:path', '存在电厂无法与还原站构成闭环。');
end

share = p.plant.pmax(:) / sum(p.plant.pmax);
process = [p.loop.dwellPlant, p.loop.dwellStation, p.loop.tRed];
validateattributes(process, {'numeric'}, {'numel',3,'finite','nonnegative','integer'});
Tl.tauFe = tauFe;
Tl.tauOx = tauOx;
Tl.perPlant = tauFe + tauOx;
Tl.mean = sum(share .* Tl.perPlant);
Tl.max = max(Tl.perPlant);
Tl.share = share;
Tl.processApplied = false;
Tl.processDays = [0, 0, 0];
Tl.reference.processDays = process;
Tl.reference.perPlant = Tl.perPlant + sum(process);
Tl.reference.mean = sum(share .* Tl.reference.perPlant);
Tl.reference.max = max(Tl.reference.perPlant);
Tl.scope = 'Minimum transport cycle; within-day conversion; no additional process queues or policy waiting.';
if any(process > 0)
    warning('computeTloop:referenceOnly', ...
        'Nonzero process delays are reference-only: the daily environment does not execute additional process queues.');
end
switch lower(p.loop.hMode)
    case 'mean'
        Tl.H = ceil(Tl.mean - 1e-9);
    case 'max'
        Tl.H = ceil(Tl.max - 1e-9);
    otherwise
        error('computeTloop:hMode', 'hMode 只能为 mean 或 max。');
end
Tl.H = max(Tl.H, 1);
end
