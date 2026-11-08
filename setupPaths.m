function root = setupPaths()
%SETUPPATHS 把工程各子目录加入 MATLAB 路径，并检查必需工具箱。
%   必需：Deep Learning Toolbox（dlarray、dlgradient、adamupdate）、Optimization Toolbox（linprog）。
%   可选：Gurobi（内层调度与随机 MPC 推荐）、YALMIP、Parallel Computing Toolbox、MATPOWER（仅 useDCPF 时）。

root = fileparts(mfilename('fullpath'));
sub = {'config', 'topo', 'env', 'data', 'policies', 'ctdf', 'capacity', 'baselines', 'eval', 'plots', 'utils', 'tests', ...
    'national'};
for k = 1:numel(sub)
    addpath(fullfile(root, sub{k}));
end
v = ver;
names = {v.Name};
req = {'Deep Learning Toolbox', 'Optimization Toolbox'};
for k = 1:numel(req)
    if ~any(strcmp(names, req{k}))
        warning('setupPaths:toolbox', '未检测到 %s，相关功能无法运行。', req{k});
    end
end
if exist('gurobi', 'file') < 2
    fprintf('提示：未检测到 Gurobi，线性规划将使用 linprog（dual-simplex），随机 MPC 求解较慢。\n');
end
end
