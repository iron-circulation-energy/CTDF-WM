function files = Fig6Panels()
%FIG6PANELS 单独生成正文图 6 的四个面板（a 路线地图、b LCOS 曲线、c 情景热图、d 储能组合），各存为一个文件。
%   只读取已有的全国评估结果，不重新计算。输出到 results\paper\<时间戳>\figures\Fig6a—Fig6d（.pdf/.png/.fig）。
%   用法：Fig6Panels
root = setupPaths();
f = fullfile(root, 'results', 'main_progress_paper.mat');
L = load(f, 'pr');
pr = L.pr;
n = params_national();
R = load(fullfile(n.outDir, 'national_results.mat'), 'R');
R = R.R;
N = natLoadInputs(n);
S = plotStyle(pr.p);
outDir = fullfile(pr.p.exp.resultsRoot, 'paper', pr.stamp, 'figures');
if ~exist(outDir, 'dir'), mkdir(outDir); end
jobs = {'Fig6a', @(o) N03_routeMap(R, N, S, o); 'Fig6b', @(o) N04_lcosCurves(R, S, o); ...
        'Fig6c', @(o) N06_scenarioWinners(R, S, o); 'Fig6d', @(o) N09_portfolioMix(R, S, o)};
files = {};
for k = 1:size(jobs, 1)
    o = fullfile(outDir, jobs{k, 1});
    try
        jobs{k, 2}(o);
        files{end + 1} = [o, '.pdf']; %#ok<AGROW>
        fprintf('已生成 %s\n', o);
    catch err
        warning('Fig6Panels:fail', '%s 生成失败：%s（%s 第 %d 行）', jobs{k, 1}, err.message, err.stack(1).name, err.stack(1).line);
    end
end
end
