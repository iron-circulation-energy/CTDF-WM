function out = main(opts)
%MAIN 一键运行全部流程：数据下载、数据导入、单元测试、模型训练、本文方法、对比方法、全国评估与论文图表。
%
%   main                                  运行论文算例全部阶段；中断后再次运行即从未完成处继续
%   main(struct('case', 'smoke'))         合成小算例，快速检查环境与全部流程
%   main(struct('stages', {{'download', 'import'}}))   只运行列出的阶段
%   main(struct('restart', true))         放弃已有进度，开始新的运行（已下载数据与已训练模型仍复用）
%
%   阶段（括号内为依赖）：
%     download     ERA5 逐时数据下载：浩吉通道站点与全国代表点，可续传
%     import       数据导入：风光容量因子与负荷指数、偏差校正、日尺度 CSV、气象过程拟合与来源记录；
%                  全国评估输入表（download）
%     tests        单元测试
%     train        数据集、参照后继分布、CTDF-WM 与对比模型、单要素对照模型、λ 与随机 MPC 调参（import、tests）
%     proposed     本文方法：临界循环质量与事件风险、E2 循环质量扫描、E1 改造与退役、E6 敏感性、气象与示意图（train）
%     comparison   对比方法：E3 常规与极端工况、E4 长时域预测、E5 各要素贡献、E7 规模扩展、守恒与模型性质检查（train）
%     national     全国 31 个省级行政区评估与全国图（import）
%     figures      导出补充表，绘制正文多面板图 2—6，并按编号汇总补充图到 results/paper/<时间戳>/（proposed、comparison）
%
%   opts 字段：case（'paper' 缺省 | 'smoke'）、stages（阶段子集）、restart（缺省 false）、
%              verbose（训练输出，缺省 true）、cache（'use' 缺省 | 'refresh' | 'off'，见 runExperiments）、
%              redoExp（需重算的实验块，如 {'E2','E3','E5'}；旧结果备份为 results_prev.mat，逐回合缓存保留）。
%
%   断点续跑：每个阶段完成后立即写入 results/main_progress_<算例>.mat。某一阶段出错时，已完成的阶段保留，
%   不依赖该阶段的阶段继续运行；问题排除（如网络恢复）后再次运行 main 即从未完成处继续。阶段内部同样可续：
%   下载按站点年缓存，数据采集按分块、参照分布按状态、训练按检查点、评估按回合保存，中断后不必从头计算。
%   参数改变时自动开始新的运行，已下载数据与指纹相同的模型直接复用。
%
%   输出 out：progress（进度记录）、summary（各阶段状态表）、paperDir（论文图表目录）。

if nargin < 1
    opts = struct();
end
root = setupPaths();
caseName = lower(char(getf(opts, 'case', 'paper')));
switch caseName
    case 'paper'
        pBase = params_paper();
        n = params_national();
        order = {'download', 'import', 'tests', 'train', 'proposed', 'comparison', 'national', 'figures'};
    case 'smoke'
        pBase = params_default('smoke');
        pBase.exp.resultsRoot = fullfile(root, 'results', 'smoke');
        n = [];
        order = {'tests', 'train', 'proposed', 'comparison', 'figures'};
    otherwise
        error('main:case', '未知算例 %s，可选 paper 或 smoke。', caseName);
end
deps = struct('download', {{}}, 'import', {{'download'}}, 'tests', {{}}, 'train', {{'import', 'tests'}}, ...
    'proposed', {{'train'}}, 'comparison', {{'train'}}, 'national', {{'import'}}, ...
    'figures', {{'proposed', 'comparison'}});
stages = getf(opts, 'stages', order);
if ischar(stages) || isstring(stages)
    stages = cellstr(stages);
end
bad = setdiff(stages, order);
if ~isempty(bad)
    error('main:stages', '未知或不适用于该算例的阶段：%s。可选：%s。', strjoin(bad, ', '), strjoin(order, ', '));
end
stages = order(ismember(order, stages));

resRoot = pBase.exp.resultsRoot;
if ~exist(resRoot, 'dir')
    mkdir(resRoot);
end
progFile = fullfile(resRoot, sprintf('main_progress_%s.mat', caseName));
pr = loadProgress(progFile);
if ~isempty(pr) && ~getf(opts, 'restart', false) && ~isequaln(pr.pBase, pBase) && ...
        isequaln(mainModelKey(pr.pBase), mainModelKey(pBase))
    % 只有评估、核算或作图参数改变（如退役对照方案、作图设置），模型相关参数未变：沿用进度、缓存模型与已完成的调参
    fprintf('只有评估、核算或作图参数改变，沿用上次运行的进度、模型与调参结果。\n');
    pr.pBase = pBase;
    if isfield(pr, 'p') && isstruct(pr.p) && ~isempty(pr.p)
        for f = {'retire', 'plot', 'mpc', 'exp'}               % prepareRealData 不改动这些字段
            if isfield(pBase, f{1})
                pr.p.(f{1}) = pBase.(f{1});
            end
        end
    end
    saveProgress(progFile, pr);
end
if getf(opts, 'restart', false) || isempty(pr) || ~isequaln(pr.pBase, pBase)
    if ~isempty(pr) && ~getf(opts, 'restart', false)
        fprintf('参数与上次运行不同，开始新的运行；已下载数据与指纹相同的模型将直接复用。\n');
    end
    pr = newProgress(pBase, order);
    if strcmp(caseName, 'smoke')
        pr.p = pBase;
        pr.done.download = true;
        pr.done.import = true;
    end
    saveProgress(progFile, pr);
end

% 指定实验块重算（opts.redoExp，如 {'E2','E3','E5'}）：把这些块已有的 results.mat 改名为 results_prev.mat 备份，
% 并把所属阶段标记为未完成；逐回合缓存保留，未受影响的方法（如 M0、M2）直接读取
redoExp = cellstr(getf(opts, 'redoExp', {}));
if ~isempty(redoExp) && ~isempty(pr) && ~isempty(pr.stamp)
    stageOf = struct('capacity', 'proposed', 'E1', 'proposed', 'E2', 'proposed', 'E6', 'proposed', ...
        'E3', 'comparison', 'E4', 'comparison', 'E5', 'comparison', 'E7', 'comparison', 'checks', 'comparison');
    for k = 1:numel(redoExp)
        ex = redoExp{k};
        fr = fullfile(pr.p.exp.resultsRoot, ex, pr.stamp, 'results.mat');
        if isfile(fr)
            movefile(fr, fullfile(pr.p.exp.resultsRoot, ex, pr.stamp, 'results_prev.mat'), 'f');
            fprintf('重算 %s：已有结果改名为 results_prev.mat。\n', ex);
        end
        if isfield(stageOf, ex)
            pr.done.(stageOf.(ex)) = false;
        end
    end
    saveProgress(progFile, pr);
end

logFile = fullfile(resRoot, sprintf('main_%s.log', caseName));
diary(logFile);
diaryGuard = onCleanup(@() diary('off'));
fprintf('\n==== main（%s）%s ====\n', caseName, char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
fprintf('进度文件：%s\n', progFile);
if exist('gurobi', 'file') >= 2
    fprintf('线性规划求解器：Gurobi（%s）\n', which('gurobi'));
else
    fprintf(['线性规划求解器：MATLAB linprog。未在路径中找到 Gurobi，若已安装，请先运行 ', ...
        'Gurobi 安装目录下 matlab\\gurobi_setup.m 并 savepath，再重新运行 main。\n']);
end
try
    g = gpuDevice;
    fprintf('GPU：%s（训练自动使用）\n', g.Name);
catch
    fprintf('GPU：未检测到可用 GPU，训练使用 CPU。\n');
end

ro = struct('skipTests', true, 'verbose', getf(opts, 'verbose', true), 'cache', getf(opts, 'cache', 'use'));
status = repmat({''}, numel(stages), 1);
elapsed = nan(numel(stages), 1);
message = repmat({''}, numel(stages), 1);
paperDir = '';
for s = 1:numel(stages)
    st = stages{s};
    if pr.done.(st) && ~strcmp(st, 'figures')
        status{s} = '已完成';
        continue;
    end
    waiting = deps.(st)(ismember(deps.(st), order));
    waiting = waiting(~cellfun(@(d) pr.done.(d), waiting));
    if ~isempty(waiting)
        status{s} = '等待';
        message{s} = ['需先完成 ', strjoin(waiting, '、')];
        fprintf('\n---- %s：等待 %s ----\n', st, strjoin(waiting, '、'));
        continue;
    end
    fprintf('\n---- 阶段 %s ----\n', st);
    t0 = tic;
    try
        switch st
            case 'download'
                pr.download = downloadWeather(pr.pBase, n);
            case 'import'
                [pr.p, pr.dataReport] = prepareRealData(pr.pBase);
                paperProtocolPreflight(pr.p, [], struct('mode', 'prepared', 'throwOnError', true));
                natLoadInputs(n);
            case 'tests'
                tdir = fullfile(root, 'tests');
                listed = strtrim(splitlines(fileread(fullfile(tdir, 'TEST_MANIFEST.txt'))));
                listed = listed(~cellfun(@isempty, listed));
                present = dir(fullfile(tdir, 'Test*.m'));
                stray = setdiff(erase({present.name}, '.m'), listed);
                if ~isempty(stray)
                    warning('main:strayTests', ['tests 文件夹中有不属于当前版本的旧测试，已跳过：%s。' ...
                        '建议删除这些文件，或将新版代码解压到空文件夹。'], strjoin(stray, ', '));
                end
                tr = runtests(fullfile(tdir, strcat(listed, '.m')));
                disp(table(tr));
                failed = {tr([tr.Failed] | [tr.Incomplete]).Name};
                if ~isempty(failed)
                    error('main:tests', '单元测试未通过：%s', strjoin(failed, '; '));
                end
            case 'train'
                pr = runBlocks(pr, {'train'}, ro, progFile);
            case 'proposed'
                pr = runBlocks(pr, {'capacity', 'E2', 'E1', 'E6', 'figW', 'fig02', 'fig03'}, ro, progFile);
            case 'comparison'
                pr = runBlocks(pr, {'E3', 'E4', 'E5', 'E7', 'checks'}, ro, progFile);
            case 'national'
                N = natLoadInputs(n);
                Cl = natClimate(N, n);
                R = natAssess(n, N, Cl);
                R.sustain = natSustain(R, n);
                R.mc = natMonteCarlo(n, N, Cl, R);
                save(fullfile(n.outDir, 'national_results.mat'), 'R');
                natFigures(R, N, n);
                if ~Cl.complete
                    error('main:nationalPartial', ['全国 ERA5 尚未下载齐全，已用 %d 个年份给出阶段结果；', ...
                        '再次运行 main 将继续下载并更新全国评估。'], numel(Cl.years));
                end
            case 'figures'
                [pr, paperDir] = collectOutputs(pr, n, ro, progFile, order);
        end
        pr.done.(st) = true;
        status{s} = '本次完成';
    catch err
        status{s} = '未完成';
        message{s} = err.message;
        fprintf(2, '阶段 %s 未完成：%s\n', st, err.message);
        if getf(opts, 'debug', false)
            rethrow(err);
        end
    end
    elapsed(s) = toc(t0);
    pr.history(end + 1, :) = {st, status{s}, elapsed(s), message{s}, char(datetime('now'))};
    saveProgress(progFile, pr);
end

summary = table(stages(:), status, round(elapsed / 60, 2), message, ...
    'VariableNames', {'阶段', '状态', '用时_min', '说明'});
fprintf('\n==== 运行汇总 ====\n');
disp(summary);
if all(ismember(status, {'已完成', '本次完成'}))
    fprintf('全部阶段已完成。论文图表：%s\n', paperDir);
    if getf(opts, 'showFigures', true) && usejava('desktop') && ~isempty(paperDir) && isfolder(fullfile(paperDir, 'figures'))
        showFigures(fullfile(paperDir, 'figures'));   % 结果图保持显示（opts.showFigures = false 时不打开）
    end
else
    fprintf('仍有阶段未完成；排除上述问题后再次运行 main 即从断点继续。\n');
end
out = struct('progress', pr, 'summary', summary, 'paperDir', paperDir);
end

% ======================================================================
function [pr, res] = runBlocks(pr, keys, ro, progFile)
% 以同一时间戳调用 runExperiments；首次调用新建运行，之后按时间戳续跑
root = pr.p.exp.resultsRoot;
if isempty(pr.stamp)
    pr.stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    saveProgress(progFile, pr);
end
o = ro;
o.only = keys;
if isfile(fullfile(root, 'common', pr.stamp, 'config.mat')) && isfile(fullfile(root, 'common', pr.stamp, ...
        'source_fingerprint.mat'))
    o.resume = pr.stamp;
else
    if isfolder(fullfile(root, 'common', pr.stamp))
        pr.stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
        saveProgress(progFile, pr);
    end
    o.stamp = pr.stamp;
end
res = [];
try
    res = runExperiments(pr.p, o);
catch err
    if ~any(strcmp(err.identifier, {'runExperiments:sourceChanged', 'runExperiments:resume'}))
        rethrow(err);
    end
    % 计算代码或参数已改变：在新的时间戳下重新运行评估，模型缓存按指纹复用
    fprintf('代码或参数已改变，在新的运行目录中继续（模型缓存按指纹复用）。\n');
    pr.stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    for f = {'train', 'proposed', 'comparison', 'figures'}
        pr.done.(f{1}) = false;
    end
    saveProgress(progFile, pr);
    o = rmfield(o, intersect(fieldnames(o), {'resume'}));
    o.stamp = pr.stamp;
    res = runExperiments(pr.p, o);
end
end

function [pr, paperDir] = collectOutputs(pr, n, ro, progFile, order)
% 导出全部补充表，绘制正文多面板图 2—6，并把补充图按编号复制到 results/paper/<时间戳>/
keys = {'capacity', 'E1', 'E2', 'E3', 'E4', 'E5', 'E6', 'E7', 'checks', 'figW', 'fig02', 'fig03'};
[pr, res] = runBlocks(pr, keys, ro, progFile);
root = pr.p.exp.resultsRoot;
paperDir = fullfile(root, 'paper', pr.stamp);
figDir = fullfile(paperDir, 'figures');
tabDir = fullfile(paperDir, 'tables');
if ~exist(figDir, 'dir'), mkdir(figDir); end
if ~exist(tabDir, 'dir'), mkdir(tabDir); end
r = @(exp, name) fullfile(root, exp, pr.stamp, name);
natFig = '';
nat = [];
if ~isempty(n)
    natFig = n.figDir;
    fr = fullfile(n.outDir, 'national_results.mat');
    if isfile(fr)
        try
            L = load(fr, 'R');
            nat = struct('R', L.R, 'N', natLoadInputs(n));
        catch err
            warning('main:national', '全国评估结果无法读取：%s', err.message);
        end
    end
end
if isempty(res)
    L = load(fullfile(root, 'common', pr.stamp, 'results_all.mat'), 'results');
    res = L.results;
end
paperFigures(res, pr.p, figDir, nat);
nf = @(name) fullfile(natFig, name);
mainFigs = {'Fig2', 'Fig3', 'Fig4', 'Fig5', 'Fig6'};
map = {
    'SFig1',  r('E3', 'F01_corridorMap')
    'SFig2',  r('figW', 'F02_windSurface')
    'SFig3',  r('figW', 'F03_yearRidges')
    'SFig4',  r('figW', 'F04_reLoadJoint')
    'SFig5',  r('figs', 'F06_socHeatmap')
    'SFig6',  r('E3', 'F16_corrMatrix')
    'SFig7',  r('E7', 'F15_learningDiag')
    'SFig8',  r('E6', 'F18_tornado')
    'SFig9',  r('E6', 'F14_breakeven')
    'SFig10', nf('N01_storage_coal_map')
    'SFig11', nf('N02_iron_mass_map')
    'SFig12', nf('N05_capacity_check')
    'SFig13', r('figs', 'F20_stateVector')
    'SFig14', r('E3', 'F07_parallelMetrics')
    'SFig16', nf('N07_sustainability')
    'SFig17', nf('N08_mc_robustness')
    };
% 补充图 15 为 CTDF-WM 训练与每日协调示意图（单独绘制）；原补充图 6、9、20—22 已并入正文图 3d、4c、2a、5c、6d
ext = {'.pdf', '.png', '.fig'};
rows = cell(size(map, 1), 3);
for k = 1:size(map, 1)
    [~, base] = fileparts(map{k, 2});
    try
        refreshFigure(map{k, 2}, 9);               % 统一为 Times New Roman 加粗 18 磅、全英文
    catch err
        warning('main:refresh', '%s 重新导出失败：%s', base, err.message);
    end
    got = false;
    for e = 1:numel(ext)
        src = [map{k, 2}, ext{e}];
        if isfile(src)
            copyfile(src, fullfile(figDir, [map{k, 1}, '_', base, ext{e}]));
            got = true;
        end
    end
    rows(k, :) = {map{k, 1}, base, ternary(got, '已生成', '待生成')};
end
for k = 1:numel(mainFigs)
    got = isfile(fullfile(figDir, [mainFigs{k}, '.pdf']));
    rows(end + 1, :) = {mainFigs{k}, 'paperFigures', ternary(got, '已生成', '待生成')}; %#ok<AGROW>
end
T = cell2table(rows, 'VariableNames', {'编号', '源文件', '状态'});
writetable(T, fullfile(paperDir, 'figure_index.csv'), 'Encoding', 'UTF-8');
tabSrc = fullfile(root, 'tables', pr.stamp);
if isfolder(tabSrc)
    copyfile(fullfile(tabSrc, 'supp_table*'), tabDir);
end
if ~isempty(n)
    for f = {'national_results.csv', 'national_scenarios.csv', 'national_sustainability.csv', ...
            'national_mc_provinces.csv', 'national_mc_draws.csv'}
        if isfile(fullfile(n.outDir, f{1}))
            copyfile(fullfile(n.outDir, f{1}), tabDir);
        end
    end
end
nMiss = nnz(strcmp(T.('状态'), '待生成'));
fprintf('论文图表已汇总到 %s（图 %d 幅，待生成 %d 幅）。\n', paperDir, height(T) - nMiss, nMiss);
if any(strcmp(order, 'national')) && ~pr.done.national
    fprintf('全国评估完成后再次运行 main，图 6 与补充图 12—14 将自动更新。\n');
end
end

function pr = newProgress(pBase, order)
pr.pBase = pBase;
pr.p = [];
pr.stamp = '';
for k = 1:numel(order)
    pr.done.(order{k}) = false;
end
pr.history = cell(0, 5);
end

function pr = loadProgress(f)
pr = [];
if isfile(f)
    try
        L = load(f, 'pr');
        pr = L.pr;
    catch
        warning('main:progress', '进度文件无法读取，开始新的运行：%s', f);
    end
end
end

function saveProgress(f, pr)
% 原子保存：先写临时文件再改名，断电或中断时不会留下损坏的进度文件
tmp = [f, '.tmp.mat'];
save(tmp, 'pr');
movefile(tmp, f, 'f');
end

function v = ternary(c, a, b)
if c
    v = a;
else
    v = b;
end
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = d;
end
end

function k = mainModelKey(p)
% 与 runExperiments 的 modelParamKey 相同的参数部分：去掉评估、作图、MPC、退役对照与核算字段
k = rmfield(p, intersect(fieldnames(p), {'exp', 'plot', 'mpc', 'retire', 'caseName'}));
if isfield(k, 'ctdf')
    k.ctdf = rmfield(k.ctdf, intersect(fieldnames(k.ctdf), {'lambda', 'lambdaGrid', 'K', 'gpiMode', 'varthetaDays', ...
        'useGPU', 'ckptEvery'}));
end
if isfield(k, 'data')
    k.data = rmfield(k.data, intersect(fieldnames(k.data), {'useParfor', 'chunkCols', 'blockEpisodes'}));
end
if isfield(k, 'plant')
    k.plant = rmfield(k.plant, intersect(fieldnames(k.plant), {'remainLife', 'newCapex', 'retrofitFrac', 'bookValueFrac'}));
end
if isfield(k, 'station')
    k.station = rmfield(k.station, intersect(fieldnames(k.station), {'capexRedPerKwFe', 'capexElPerKw', 'life'}));
end
if isfield(k, 'transport')
    k.transport = rmfield(k.transport, intersect(fieldnames(k.transport), {'uhvCostPerKwh', 'uhvCostPer1000km'}));
end
if isfield(p, 'exp')
    k.expSeeds = p.exp.seeds;
    k.expGT = [p.exp.gtStates, p.exp.gtValStates, p.exp.gtR, p.exp.gtSamples, p.exp.gtTcap, p.exp.exactW1Max, ...
        p.exp.warmup, p.exp.evalDays, p.exp.initSOC];
end
end
