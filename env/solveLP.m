function [x, fval, exitflag, info] = solveLP(prob, solverPref)
%SOLVELP 线性规划求解封装：Gurobi（直接接口）、YALMIP（调用 Gurobi）或 linprog（dual-simplex）。
%   prob 字段：f、Aineq、bineq、Aeq、beq、lb、ub（列向量，ub 可含 Inf）。
%   solverPref：'auto'（有 Gurobi 用 Gurobi，否则 linprog）、'gurobi'、'yalmip'、'linprog'。
%   exitflag = 1 表示求得最优解；info 字段：solver、time、status、mipGap（LP 为 0）。

if nargin < 2 || isempty(solverPref)
    solverPref = 'auto';
end
solver = lower(solverPref);
if strcmp(solver, 'auto')
    if exist('gurobi', 'file') >= 2
        solver = 'gurobi';
    else
        solver = 'linprog';
    end
end
info.solver = solver;
info.mipGap = 0;
tic0 = tic;
switch solver
    case 'gurobi'
        model.obj = full(prob.f(:));
        model.A = [prob.Aineq; prob.Aeq];
        model.rhs = full([prob.bineq(:); prob.beq(:)]);
        model.sense = [repmat('<', size(prob.Aineq, 1), 1); repmat('=', size(prob.Aeq, 1), 1)];
        model.lb = full(prob.lb(:));
        model.ub = full(prob.ub(:));
        model.modelsense = 'min';
        params.OutputFlag = 0;
        params.Method = 1;
        params.Threads = 1; % independent episodes already parallelize at the outer level
        res = gurobi(model, params);
        info.status = res.status;
        if strcmp(res.status, 'OPTIMAL')
            x = res.x;
            fval = res.objval;
            exitflag = 1;
        else
            x = [];
            fval = NaN;
            exitflag = -1;
        end
    case 'yalmip'
        nv = numel(prob.f);
        xv = sdpvar(nv, 1);
        lbv = prob.lb(:);
        ubv = prob.ub(:);
        fin = isfinite(ubv);
        cons = [prob.Aineq * xv <= prob.bineq(:), prob.Aeq * xv == prob.beq(:), xv >= lbv, xv(fin) <= ubv(fin)];
        ops = sdpsettings('solver', 'gurobi', 'verbose', 0, 'gurobi.Threads', 1);
        sol = optimize(cons, prob.f(:)' * xv, ops);
        info.status = sol.info;
        if sol.problem == 0
            x = value(xv);
            fval = prob.f(:)' * x;
            exitflag = 1;
        else
            x = [];
            fval = NaN;
            exitflag = -1;
        end
    case 'linprog'
        opts = optimoptions('linprog', 'Display', 'none', 'Algorithm', 'dual-simplex');
        [x, fval, ef, out] = linprog(prob.f(:), prob.Aineq, prob.bineq(:), prob.Aeq, prob.beq(:), ...
            prob.lb(:), prob.ub(:), opts);
        info.status = out.message;
        exitflag = double(ef == 1);
        if ef ~= 1
            exitflag = -1;
        end
    otherwise
        error('solveLP:solver', '未知求解器 %s。', solverPref);
end
info.time = toc(tic0);
end
