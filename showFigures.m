function figs = showFigures(what, stamp)
%SHOWFIGURES 打开已保存的结果图（.fig）并保持显示，图窗按标签页停靠在同一窗口中。
%   showFigures()            正文图（results/paper/<时间戳>/figures）；尚无正文图时打开各实验目录的图
%   showFigures('all')       全部实验目录（E1—E7、common）、正文图与全国评估图
%   showFigures('E2')        某一实验目录（E1—E7、common）
%   showFigures('national')  全国评估图（N01—N09）
%   showFigures(folder)      任意文件夹（递归查找 .fig）
%   stamp 缺省取 main_progress_paper.mat 中最近一次运行的时间戳。
%   关闭全部：close all。
setupPaths();
if nargin < 1 || isempty(what)
    what = 'paper';
end
p = params_paper();
root = p.exp.resultsRoot;
if nargin < 2 || isempty(stamp)
    stamp = '';
    f = fullfile(root, 'main_progress_paper.mat');
    if isfile(f)
        L = load(f, 'pr');
        stamp = L.pr.stamp;
    end
end
n = params_national();
dirs = {};
if isfolder(what)
    dirs = {what};
else
    switch lower(what)
        case 'paper'
            dirs = {fullfile(root, 'paper', stamp, 'figures')};
            if ~isfolder(dirs{1})
                dirs = expDirs(root, stamp);
            end
        case 'all'
            dirs = [expDirs(root, stamp), {fullfile(root, 'paper', stamp, 'figures'), n.figDir}];
        case 'national'
            dirs = {n.figDir};
        otherwise
            dirs = {fullfile(root, upper(what), stamp)};
            if strcmpi(what, 'common')
                dirs = {fullfile(root, 'common', stamp)};
            end
    end
end
files = {};
for k = 1:numel(dirs)
    if isfolder(dirs{k})
        L = dir(fullfile(dirs{k}, '**', '*.fig'));
        files = [files, fullfile({L.folder}, {L.name})]; %#ok<AGROW>
    end
end
files = unique(files, 'stable');
if isempty(files)
    fprintf('未找到 .fig 文件：%s\n', strjoin(dirs, '；'));
    figs = gobjects(0);
    return;
end
old = get(groot, 'DefaultFigureWindowStyle');
set(groot, 'DefaultFigureWindowStyle', 'docked');
figs = gobjects(numel(files), 1);
for k = 1:numel(files)
    try
        figs(k) = openfig(files{k}, 'new', 'visible');
        [~, nm] = fileparts(files{k});
        set(figs(k), 'Name', nm, 'NumberTitle', 'off', 'WindowStyle', 'docked');   % .fig 保存的窗口样式会覆盖默认值
    catch err
        warning('showFigures:open', '%s 无法打开：%s', files{k}, err.message);
    end
end
set(groot, 'DefaultFigureWindowStyle', old);
drawnow;
fprintf('已打开 %d 张图（停靠在同一窗口的标签页中；关闭全部用 close all）。\n', nnz(isgraphics(figs)));
end

function d = expDirs(root, stamp)
d = {};
for e = {'common', 'E1', 'E2', 'E3', 'E4', 'E5', 'E6', 'E7'}
    q = fullfile(root, e{1}, stamp);
    if isfolder(q)
        d{end + 1} = q; %#ok<AGROW>
    end
end
end
