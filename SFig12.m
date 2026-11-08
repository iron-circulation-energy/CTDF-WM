function SFig12()
%SFIG12 单独重画补充图 12（各省事件缓冲质量与多年库存对照，N05），只读取已有全国评估结果，不重新计算。
%   同时覆盖 figures\national\N05_capacity_check 与 results\paper\<时间戳>\figures\SFig12_N05_capacity_check。
root = setupPaths();
L = load(fullfile(root, 'results', 'main_progress_paper.mat'), 'pr');
pr = L.pr;
n = params_national();
R = load(fullfile(n.outDir, 'national_results.mat'), 'R');
S = plotStyle(pr.p);
N05_capacityCheck(R.R, S, fullfile(n.figDir, 'N05_capacity_check'));
paper = fullfile(pr.p.exp.resultsRoot, 'paper', pr.stamp, 'figures');
ext = {'.pdf', '.png', '.fig'};
for e = 1:numel(ext)
    src = fullfile(n.figDir, ['N05_capacity_check', ext{e}]);
    if isfile(src) && isfolder(paper)
        copyfile(src, fullfile(paper, ['SFig12_N05_capacity_check', ext{e}]));
    end
end
fprintf('已生成补充图 12：%s\n', fullfile(paper, 'SFig12_N05_capacity_check.png'));
end
