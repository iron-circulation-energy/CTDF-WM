function o = storageDispatchRolling(w, P, sp, p, W, vMult)
%STORAGEDISPATCHROLLING 替代方案的滚动有限预见调度：与改造情景的信息条件对称。
%   o = storageDispatchRolling(w, P, sp, p, W, vMult)
%   每日求解一次覆盖未来 W 天（含当日）的逐小时线性规划（storageWindowLP），只执行当日 24 h，储能量逐日传递；
%   W 天之外的未来以窗口末储能量的单位价值 v_S = vMult·c^bk·η_d 表示（储能放出 1 MWh 电量替代备用机组的燃料与碳成本），
%   vMult 由 retirementForesight 在参考功率下按评估期总成本最小选取（在评估期内选取，对替代方案有利）。
%   年末储能量与初值 e_0 = 0.5·E_cap 之差按 v_S 计入运行成本（多存的电量记为收益），对应完全预见口径的末端约束 e_N ≥ e_0。
%   输出字段与 storageDispatchLP 相同：eue、op、cur、RE，另含 eEnd、vS。

RE = reshape(w.RE, 24, []);
D = reshape(w.D, 24, []);
nd = size(RE, 2);
Ecap = P * sp.hours / sp.etaDischarge;
cBk = p.backup.fuelCost + w.carbon * p.backup.ef;
vS = vMult * cBk * sp.etaDischarge;
e = 0.5 * Ecap;
e0 = e;
u = 0;          % 上一执行段末的燃机在线容量（运行约束开启时传递，避免每日重复计启动）
o = struct('eue', 0, 'op', 0, 'cur', 0, 'RE', 0);
for d = 1:nd
    win = d:min(nd, d + W - 1);
    wd = struct('RE', RE(:, win), 'D', D(:, win), 'carbon', w.carbon);
    r = storageWindowLP(wd, P, sp, p, struct('e0', e, 'termValue', vS, 'commitH', 24, 'u0', u));
    o.eue = o.eue + r.eue;
    o.op = o.op + r.op;
    o.cur = o.cur + r.cur;
    o.RE = o.RE + r.RE;
    e = r.eCommit;
    if isfield(r, 'uCommit'), u = r.uCommit; end
end
o.op = o.op - vS * (e - e0);
o.eEnd = e;
o.vS = vS;
end
