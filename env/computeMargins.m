function [muFe, muOx] = computeMargins(S, ctx, spec)
%COMPUTEMARGINS 由原始状态（D×M，列为样本）计算铁裕度与锈裕度（—(16)，H = T_loop）：
%   μ^Fe_i = I^Fe_i + Σ_{d=1}^{H} â^Fe_{i,k+d} − Σ_{d=0}^{H−1} b̂_{i,k+d} − I̲^Fe_i
%   μ^Ox_j = S^Ox_j + Σ_{d=1}^{H} â^Ox_{j,k+d} − Σ_{d=0}^{H−1} ρ̂_{j,k+d} − S̲^Ox_j
%   其中 â_{·,k+d} 取进入该节点线路的第 d 个管道格（第 k+d−1 日到达，即管道中已知的到达量）；
%   b̂ 由前 H 日必需电量和 EH 按电厂容量份额与名义效率折算，ρ̂ 由可吸收电量和 AH 按还原功率份额
%   与名义单位能耗折算。两者都是状态的仿射函数 μ = G·s + g0（短缺暴露误差的 Lipschitz 常数由 G 给出）。
%   输出：muFe（nP×M）、muOx（nR×M），单位 t。

% 缺省采用已发运在途量与名义分配计算裕度，不含候选策略尚未发出的发运；
% 固定物料计划的裕度由 frozenPlanMargins 给出。
if nargin<3 || isempty(spec), spec=ctx.margin; end
muFe = spec.GFe * S + spec.gFe0;
muOx = spec.GOx * S + spec.gOx0;
muFe = full(muFe);
muOx = full(muOx);
end
