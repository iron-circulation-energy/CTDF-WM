function V = nullSpaceProj(V, nMat)
%NULLSPACEPROJ 零空间投影：物料分量 v_mat ← v_mat − mean(v_mat)，即 P = I − (1/n)·11ᵀ。
%   外生、辅助与成本分量不投影。投影后 1ᵀ·v_mat = 0，生成 ODE 严格守恒；
%   P 为正交投影，对任意满足 1ᵀu = 0 的目标有 ‖P·v − u‖ ≤ ‖v − u‖。

Vm = V(1:nMat, :);
V(1:nMat, :) = Vm - mean(Vm, 1);
end
