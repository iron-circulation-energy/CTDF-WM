function fl = fluidParams(ctx, stats)
%FLUIDPARAMS 由拓扑、统计量与参数组装流体模型参数（临界循环质量、事件风险数值验证共用）。
%   恢复速率 dR 取常规日平均富余吸收能力与平均通量之差（至少 0.25·Φ̄），代表事件间恢复荷电状态的能力。

p = ctx.p;
fl.Phi = stats.Phi;
fl.deltaD = stats.deltaD;
fl.deltaU = stats.deltaU;
fl.Dmax = round(stats.Dmax);
fl.Umax = round(stats.Umax);
fl.dR = max(stats.Amean - stats.Phi, 0.25 * stats.Phi);
fl.share = ctx.shareP;
fl.tauFe = ctx.Tl.tauFe;
fl.tauOx = ctx.Tl.tauOx;
% Match the operational environment. Standalone fluidLoopSim callers may
% explicitly supply nonzero process queues for a separate theoretical model.
fl.tP = 0;
fl.tR = 0;
fl.tRed = 0;
fl.safeFe = p.plant.safetyFe(:);
fl.safeOx = sum(p.station.safetyOx);
fl.gap = ceil(max(fl.deltaD * fl.Dmax, fl.deltaU * fl.Umax) / fl.dR) + ...
    ceil(max(fl.tauFe + fl.tP + fl.tauOx + fl.tR + fl.tRed)) + 5;
end
