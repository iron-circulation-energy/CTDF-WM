function e3 = runE3Comparison(C, methods, years, seeds, epDir)
%RUNE3COMPARISON E3 常规与极端工况对比。
%   工况：normal、drought（连续 p.exp.droughtDays 天低风光）、outage（铁路中断 p.exp.outageDays 天）、
%   stationOut（还原站故障 p.exp.stationOutDays 天）；循环铁总质量取名义值 cNominal；全部方法使用相同测试年份、
%   种子窗口与预测信息。指标见 runEpisode。方法间差异用配对 t 检验（按同一年份、种子与工况配对，M1 对其余方法）。
%   第一个测试年份、第一个种子的 drought 与 outage 回合保存逐日轨迹（图 3）。
%   methods：结构体数组，字段 name、factory（@(seed) 控制器），可选 seeds（该方法使用的种子子集，配对检验只用共同种子）。
%   epDir（可选）：断点续跑的逐回合缓存目录（见 evalEpisodes），已完成的回合（含轨迹）直接读取。
%   输出 e3：episodes、summary（方法 × 工况）、paired（配对检验表）、traces（方法 × 工况的轨迹）。

if nargin < 5
    epDir = '';
end
p = C.p;
scen = {'normal', 'drought', 'outage', 'stationOut'};
Tall = {};
traces = struct('method', {}, 'scenario', {}, 'trace', {}, 'ext', {});
daily = struct('method', {}, 'scenario', {}, 'year', {}, 'seed', {}, 'd', {}, 'flow', {});
for m = 1:numel(methods)
    sm = seeds;
    if isfield(methods(m), 'seeds') && ~isempty(methods(m).seeds)
        sm = methods(m).seeds;
    end
    scenM = scen;
    if isfield(p.exp,'e3MethodScenarios') && isfield(p.exp.e3MethodScenarios,methods(m).name)
        scenM = intersect(scen,p.exp.e3MethodScenarios.(methods(m).name),'stable');
    end
    for s = sm(:)'
        ctrl = methods(m).factory(s);
        specs = makeEvalSpecs(p, years, s, scenM, C.cNominal);
        for q = 1:numel(specs)
            specs(q).keepTrace = (specs(q).year == years(1)) && (s == seeds(1)) && ...
                any(strcmpi(specs(q).scenario, {'drought', 'outage'}));
        end
        ctxM = C.ctx;
        if isfield(methods(m), 'ctx') && ~isempty(methods(m).ctx)
            ctxM = methods(m).ctx;                  % 个别方法使用不同的信息条件（M2o 完全预见上界）
        end
        [R, T] = evalEpisodes(ctxM, C.W, specs, ctrl, [], epDir);
        T.method = repmat({methods(m).name}, height(T), 1);
        Tall{end + 1} = T; %#ok<AGROW>
        for q = 1:numel(R)
            daily(end + 1) = struct('method', methods(m).name, 'scenario', R(q).spec.scenario, ...
                'year', R(q).spec.year, 'seed', s, 'd', R(q).daily, 'flow', R(q).lineFlow); %#ok<AGROW>
            if ~isempty(R(q).trace)
                traces(end + 1) = struct('method', methods(m).name, 'scenario', R(q).spec.scenario, ...
                    'trace', R(q).trace, 'ext', R(q).ext); %#ok<AGROW>
            end
        end
    end
end
E = vertcat(Tall{:});
metrics = {'pF', 'pShed', 'shedMWh', 'curRate', 'rustBlockMWh', 'cost', 'decTime', 'eventF','eventShed', ...
    'injectedShedMWh','injectedAnyShed','injectedSafeDays','followupShedMWh','followupAnyShed','injectedWarningLeadDays'};
e3.episodes = E;
e3.summary = statsUtils('summaryTable', E, {'method', 'scenario'}, metrics);
% 配对检验：M1 对其余方法
rows = cell(0, 12);
names = unique(E.method, 'stable');
ref = 'M1';
if any(strcmp(names, ref))
    for m = 1:numel(names)
        if strcmp(names{m}, ref)
            continue;
        end
        for sc = scen
            A = E(strcmp(E.method, ref) & strcmp(E.scenario, sc{1}), :);
            B = E(strcmp(E.method, names{m}) & strcmp(E.scenario, sc{1}), :);
            [tf, loc] = ismember([A.year, A.seed], [B.year, B.seed], 'rows');
            A = A(tf, :);
            B = B(loc(tf), :);
            if isempty(A), continue; end
            for k = 1:numel(metrics)
                [pv, dm, ny, lo, hi] = statsUtils('clusterPaired', A.(metrics{k}), B.(metrics{k}), A.year);
                va=A.(metrics{k}); vb=B.(metrics{k}); ok=isfinite(va)&isfinite(vb);
                ma=NaN; mb=NaN;
                if any(ok)
                    [~,~,gy]=unique(A.year(ok));
                    ma=mean(accumarray(gy,va(ok),[],@mean)); mb=mean(accumarray(gy,vb(ok),[],@mean));
                end
                rows(end + 1, :) = {ref, names{m}, sc{1}, metrics{k}, dm, pv, nnz(ok), ny, lo, hi, ma, mb}; %#ok<AGROW>
            end
        end
    end
end
e3.paired = cell2table(rows, 'VariableNames', {'MethodA', 'MethodB', 'Scenario', 'Metric', 'MeanDiff', 'pValue', 'nPairs','nYears','DiffLo','DiffHi','MatchedMeanA','MatchedMeanB'});
e3.inference = 'Year-clustered paired t intervals; nPairs are episodes, nYears are independent weather clusters. M3 only compared on its observed matched subset.';
e3.metricScope = 'pShed/eventShed/shedMWh and injected/followup: unserved load; pF/eventF: plant iron starvation.';
e3.traces = traces;
e3.daily = daily;          % 逐回合逐日序列与线路日均发运量（图 F01、F08、F13、F16）
end
