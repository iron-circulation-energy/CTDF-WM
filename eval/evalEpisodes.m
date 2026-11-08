function [R, T] = evalEpisodes(ctx, W, specs, ctrl, useParfor, epDir)
%EVALEPISODES 批量运行评估回合，可用 parfor 并行（各回合独立随机流，结果可复现）。
%   输出 R：1×N 结构体数组（runEpisode 输出）；T：指标汇总表，每行一个回合，含年份、种子、工况与各项指标，
%   供 statsUtils 计算均值、标准差、95% 置信区间与按（年份, 种子, 工况）配对的检验。
%   useParfor 缺省或为空时取 p.data.useParfor。
%   epDir（可选，断点续跑的逐回合缓存目录）：每个回合的 runEpisode 输出保存为一个 .mat，文件名由控制器名与回合说明
%   字段（year、seed、scenario、d0、len、warmup、c、initSOC、keepTrace，及 carbon、h2）确定；文件已存在且其中的
%   控制器名与回合说明一致时直接读取，否则运行并保存。同一目录内同名控制器须相同（E6 各变体共用控制器名，
%   λ 与 MPC 调参不使用此缓存）。

if nargin < 5 || isempty(useParfor)
    useParfor = ctx.p.data.useParfor;
end
if nargin < 6
    epDir = '';
end
if ~isempty(epDir) && ~exist(epDir, 'dir')
    mkdir(epDir);
end
N = numel(specs);
Rc = cell(1, N);
useP = useParfor && N > 1 && ~isempty(ver('parallel')) && license('test', 'Distrib_Computing_Toolbox');
if any(strcmpi(ctrl.type,{'gpi','stepwise','gpicrn'}))
    useP = false; % one client owns the single GPU; samples/candidates already batched
end
workers=inf;
if isfield(ctx.p,'runtime'), workers=ctx.p.runtime.cpuWorkers; end
if useP
    parfor (m = 1:N, workers)
        Rc{m} = cachedEpisode(ctx, W, specs(m), ctrl, epDir);
    end
else
    for m = 1:N
        Rc{m} = cachedEpisode(ctx, W, specs(m), ctrl, epDir);
    end
end
R = [Rc{:}];
T = metricsTable(R);
end

function out = cachedEpisode(ctx, W, spec, ctrl, epDir)
% 单个评估回合（带逐回合缓存）。读取、运行与保存放在局部函数中，满足 parfor 透明性要求
% （parfor 循环体内不能直接调用 save/load）；先写临时文件再改名，中断时不会留下损坏的回合文件。
if isempty(epDir)
    out = runEpisode(ctx, W, spec, ctrl);
    return;
end
tag = '';
if isfield(ctrl, 'cacheTag') && ~isempty(ctrl.cacheTag)
    tag = ['_', ctrl.cacheTag];
end
f = fullfile(epDir, [episodeFileName(ctrl.name, spec), tag, '.mat']);
if isfile(f)
    try
        L = load(f, 'out');
        if strcmp(L.out.ctrlName, ctrl.name) && isequaln(L.out.spec, spec) && isfield(L.out, 'daily')
            out = L.out;
            return;
        end
    catch
        % 文件损坏：重新运行并覆盖
    end
end
out = runEpisode(ctx, W, spec, ctrl);
tmp = [tempname(epDir), '.mat'];
save(tmp, 'out');
movefile(tmp, f, 'f');
end

function nm = episodeFileName(name, sp)
% 回合缓存文件名（不含扩展名）：控制器名与回合说明各字段依次拼接；数值按 '%.10g' 格式化后把小数点、负号替换为
% p、m 并去掉指数正号，名称中的非字母数字字符替换为下划线，文件名只含字母、数字与下划线
tr = isfield(sp, 'keepTrace') && ~isempty(sp.keepTrace) && logical(sp.keepTrace(1));
nm = sprintf('%s_y%s_s%s_%s_d%s_L%s_w%s_c%s_soc%s_tr%d', safeName(name), numTag(sp.year), numTag(sp.seed), ...
    safeName(sp.scenario), numTag(sp.d0), numTag(sp.len), numTag(sp.warmup), numTag(sp.c), numTag(sp.initSOC), tr);
if isfield(sp, 'carbon') && ~isempty(sp.carbon)
    nm = [nm, '_co2', numTag(sp.carbon)];
end
if isfield(sp, 'h2') && ~isempty(sp.h2)
    nm = [nm, '_h2', numTag(sp.h2)];
end
end

function s = numTag(v)
s = strjoin(arrayfun(@(a) sprintf('%.10g', a), double(v(:)'), 'UniformOutput', false), '_');
s = strrep(strrep(strrep(s, '.', 'p'), '-', 'm'), '+', '');
end

function s = safeName(s)
s = regexprep(char(s), '[^A-Za-z0-9]', '_');
end

function T = metricsTable(R)
N = numel(R);
year = zeros(N, 1);
seed = zeros(N, 1);
scen = cell(N, 1);
c = zeros(N, 1);
names = {'pF', 'pShed', 'shedMWh', 'curRate', 'curMWh', 'rustBlockMWh', 'cost', 'decTime', 'localFe', ...
    'forecastExposure','safetyExposure','ironShortfallMWh','localForecastFe','eventForecastExposure', ...
    'localOx', 'localRB', 'loadMWh', 'REMWh', 'maxConsRel', 'trunc', 'events', 'eventShed', 'eventF', 'mpcTime', ...
    'injectedShedMWh','injectedAnyShed','injectedSafeDays','followupShedMWh','followupAnyShed', ...
    'injectedWarningLeadDays','injectedComplete','followupComplete'};
V = zeros(N, numel(names));
for m = 1:N
    year(m) = R(m).spec.year;
    seed(m) = R(m).spec.seed;
    scen{m} = R(m).spec.scenario;
    c(m) = R(m).spec.c;
    for q = 1:numel(names)
        V(m, q) = R(m).metrics.(names{q});
    end
end
T = [table(year, seed, scen, c, 'VariableNames', {'year', 'seed', 'scenario', 'c'}), ...
    array2table(V, 'VariableNames', names)];
T.method = repmat({R(1).ctrlName}, N, 1);
end
