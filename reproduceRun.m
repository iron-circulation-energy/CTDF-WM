function results = reproduceRun(configFile, only)
%REPRODUCERUN 由保存的 config.mat 一键复现：读取完整参数 p 并重新运行指定实验。
%   results = reproduceRun('results/E3/20261009_120000/config.mat', {'E3'})
%   全部随机数由 p.seed 与各实验种子派生，CPU 上结果可逐位复现；GPU 上可能存在微小的非确定性差异（见 ver.txt）。

setupPaths();
L = load(configFile, 'p');
if nargin < 2 || isempty(only)
    results = runExperiments(L.p);
else
    results = runExperiments(L.p, struct('only', {only}));
end
end
