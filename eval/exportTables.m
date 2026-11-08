function files = exportTables(res, p, outDir)
%EXPORTTABLES 导出补充表（.csv 与 .md）。
%   补充表 2：各方法在各工况下的测试年指标（均值与 95% 区间，区间按气象年聚类），另附年度汇总、配对差值与事件窗口；
%   补充表 3：CTDF-WM 各要素带来的提升，另附逐工况年度汇总与逐状态预测记录；
%   补充表 4：守恒与模型性质检查；
%   补充表 6：模型参数与来源；
%   补充表 8：符号表，附代码变量名。
%   res 字段（缺失则跳过）：e3、e5、vp。输出 files：已写出的文件列表。

if ~exist(outDir, 'dir')
    mkdir(outDir);
end
files = {};
if isfield(res, 'e3') && ~isempty(res.e3)
    Sm = res.e3.summary;
    T2 = table(Sm.method, Sm.scenario, ...
        metricCI(Sm,'pF'),metricCI(Sm,'eventF'),metricCI(Sm,'shedMWh'), ...
        metricCI(Sm,'pShed'),metricCI(Sm,'eventShed'),metricCI(Sm,'curRate',100), ...
        metricCI(Sm,'rustBlockMWh'),metricCI(Sm,'cost',1e-4),metricCI(Sm,'decTime'), ...
        Sm.n,columnOr(Sm,'nYears',NaN), ...
        'VariableNames', {'方法','工况','断供概率','事件断供概率','缺供电量/MWh', ...
        '失负荷日比例','事件失负荷比例','弃电率/%','锈阻塞弃电量/MWh', ...
        '总成本/万元','决策时间/s','回合数','气象年数'});
    files = [files, writeBoth(T2, fullfile(outDir, 'supp_table2_indicators'), ...
        '补充表 2 各方法在各工况下的测试年指标')];
    files = [files, writeBoth(res.e3.paired, fullfile(outDir, 'supp_table2_paired'), ...
        '补充表 2 附：共同年份与种子上 CTDF-WM 与各方法的配对差值')];
    files = [files, writeBoth(Sm,fullfile(outDir,'supp_table2_annual'), ...
        '补充表 2 附：各指标的年度汇总')];
    windowMetrics={'injectedShedMWh','injectedAnyShed','injectedSafeDays', ...
        'followupShedMWh','followupAnyShed','injectedWarningLeadDays'};
    names=Sm.Properties.VariableNames;
    windowColumns=names(startsWith(names,strcat(windowMetrics,'_')));
    if ~isempty(windowColumns)
        keep=intersect([{'method','scenario'},windowColumns,{'n','nYears'}],names,'stable');
        Tw=Sm(~strcmp(Sm.scenario,'normal'),keep);
        files=[files,writeBoth(Tw,fullfile(outDir,'supp_table2_events'), ...
            '补充表 2 附：极端事件窗口与后续窗口指标')];
    end
end
if isfield(res, 'e5') && ~isempty(res.e5)
    E = res.e5.table;
    method=columnOr(E,'DistanceMethod',{'exact'});
    T3 = table(E.Label, E.ConsErrT, E.RawConsRel, E.NegPct, E.W1, method, E.pF, ...
        'VariableNames', {'模型（所度量的要素）', '守恒误差/t', '投影前守恒相对误差', '负值样本比例/%', ...
        'W1 距离','距离计算','断供风险'});
    files = [files, writeBoth(T3, fullfile(outDir, 'supp_table3_elements'), '补充表 3 各模型取值')];
    iF = find(strcmp(E.Name, 'full'), 1);
    if ~isempty(iF) && height(E) > 1
        rows = setdiff(1:height(E), iF, 'stable');
        g = @(v, b) 100 * (v - b) ./ max(abs(v), eps);
        G = table(E.Label(rows), E.ConsErrT(rows) ./ max(E.ConsErrT(iF), eps), E.NegPct(rows) - E.NegPct(iF), ...
            g(E.W1(rows), E.W1(iF)), g(E.pF(rows), E.pF(iF)), ...
            'VariableNames', {'所考虑的要素', '守恒误差降低倍数', '负值样本降低/百分点', 'W1 距离降低/%', '断供风险降低/%'});
        files = [files, writeBoth(G, fullfile(outDir, 'supp_table3_gain'), ...
            '补充表 3 考虑各要素带来的提升（相对仅在该要素上不同的对照模型）')];
    end
    optional={'annualSummary','supp_table3_annual','补充表 3 附：逐工况年度汇总'; ...
        'predictionRaw','supp_table3_prediction','补充表 3 附：逐状态预测记录'; ...
        'predictionSummary','supp_table3_prediction_summary','补充表 3 附：预测精度汇总'};
    for k=1:size(optional,1)
        if isfield(res.e5,optional{k,1}) && istable(res.e5.(optional{k,1}))
            files=[files,writeBoth(res.e5.(optional{k,1}),fullfile(outDir,optional{k,2}),optional{k,3})]; %#ok<AGROW>
        end
    end
end
if isfield(res, 'vp') && ~isempty(res.vp)
    T4 = res.vp.table;
    T4.Properties.VariableNames = {'检查项', '对应关系', '结果', '判据', '是否满足'};
    files = [files, writeBoth(T4, fullfile(outDir, 'supp_table4_checks'), '补充表 4 守恒与模型性质检查')];
end
files = [files, writeBoth(paramSources(p), fullfile(outDir, 'supp_table6_parameters'), '补充表 6 模型参数')];
files = [files, writeBoth(symbolTable(), fullfile(outDir, 'supp_table8_notation'), '补充表 8 符号表')];
end

function values=columnOr(T,name,fallback)
if ismember(name,T.Properties.VariableNames), values=T.(name);
else, values=repmat(fallback,height(T),1); end
end

function values=metricCI(T,name,scale)
if nargin<3, scale=1; end
required=strcat(name,{'_mean','_lo','_hi'});
if ~all(ismember(required,T.Properties.VariableNames))
    values=repmat({'—'},height(T),1); return;
end
values=arrayfun(@(a,b,c) sprintf('%.4g [%.4g, %.4g]',scale*a,scale*b,scale*c), ...
    T.(required{1}),T.(required{2}),T.(required{3}),'UniformOutput',false);
end

function f = writeBoth(T, base, ttl)
writetable(T, [base, '.csv'], 'Encoding', 'UTF-8');
fid = fopen([base, '.md'], 'w', 'n', 'UTF-8');
fprintf(fid, '%s\n\n', ttl);
vn = T.Properties.VariableNames;
fprintf(fid, '| %s |\n', strjoin(vn, ' | '));
fprintf(fid, '|%s\n', repmat(' --- |', 1, numel(vn)));
for r = 1:height(T)
    cells = cell(1, numel(vn));
    for c = 1:numel(vn)
        v = T{r, c};
        if iscell(v)
            v = v{1};
        end
        if isnumeric(v) || islogical(v)
            if isscalar(v)
                cells{c} = sprintf('%.4g', v);
            else
                cells{c} = mat2str(v, 4);
            end
        else
            cells{c} = char(string(v));
        end
    end
    fprintf(fid, '| %s |\n', strjoin(cells, ' | '));
end
fclose(fid);
f = {[base, '.csv'], [base, '.md']};
end

function T = symbolTable()
rows = {
    '𝓡, 𝓟, 𝓗, 𝓔', '还原站、改造火电、枢纽、线路集合', '—', 'topo.R, topo.P, topo.H, topo.nE'
    '𝓔^Fe, 𝓔^Ox', '正向铁粉线路、反向铁锈线路集合', '—', 'topo.mat'
    'k, t', '日序、小时序', 'd、h', 'env.k'
    'τ_e, L_e', '线路运输时延、线路长度', 'd、km', 'topo.tau, topo.L'
    'I^Fe_{i,k}, I^Ox_{i,k}', '电厂 i 的铁、锈库存', 't（铁当量）', 'x(idx.IFe), x(idx.IOx)'
    'S^Fe_{j,k}, S^Ox_{j,k}', '还原站 j 的铁、锈库存', 't（铁当量）', 'x(idx.SFe), x(idx.SOx)'
    'H^Fe_{h,k}, H^Ox_{h,k}', '枢纽 h 的铁、锈库存', 't（铁当量）', 'x(idx.HFe), x(idx.HOx)'
    'q_{e,d,k}, a_{e,k}', '剩余 d 天到达的在途量、当日到达量', 't（铁当量）', 'x(idx.q{e})'
    'V_k', '固定质量运行中损失与补铁的核算存量', 't（铁当量）', 'x(idx.V)'
    'x_k, n', '物料状态向量及其维数', '—', 'env.x, idx.n'
    'c', '循环铁总质量', 't（铁当量）', 'env.c'
    'b_{i,k}, b̄_{i,k}', '实际燃铁量、燃铁量上限', 't/d', 'info.b, a.bcap'
    'ρ_{j,k}', '还原量', 't/d', 'info.rho, a.rho'
    'f_{e,k}', '发运量', 't/d', 'info.f, a.f'
    'u_{j,k}', '补铁量', 't/d', 'info.u'
    'ℓ_i', '颗粒捕集损耗率', '—', 'p.plant.loss'
    'β_{i,k}, o_{i,k}', '掺氨比例、日开机状态', '—', 'a.beta, a.o'
    'h_Fe', '铁热值，取 2.05', 'MWh/t', 'p.iron.hFe'
    'η^st_i, η^el_j', '汽轮机循环效率、电解效率', '—', 'p.plant.etaSt, p.station.etaEl'
    'κ_j, ε_j', '还原氢耗、单位还原辅助电耗', 'MWh_H2/MWh_Fe、MWh_el/t_Fe', 'p.station.kappa, p.station.epsAux'
    'E^dis_{i,k}, E^ch_{j,k}', '电厂日放能、还原站日耗电', 'MWh', 'innerDispatchLP'
    'p_{i,t}, p^red_{j,t}', '电厂出力、还原站功率', 'MW', 'lp.p, lp.red'
    'P^RE_t, P^cur_t, P^shed_t, D_t', '风光出力、弃电、失负荷、负荷', 'MW', 'RE, lp.cur, lp.shed, D'
    'C_k, J^in_k', '单日成本、内层运行成本', '元', 'info.cost, lp.Jop'
    'T_loop', '闭环周转时间', 'd', 'Tl.mean'
    'μ^Fe_{i,k}, μ^Ox_{j,k}', '铁裕度、锈裕度', 't（铁当量）', 'computeMargins'
    'I̲^Fe_i, S̲^Ox_j', '安全铁库存、安全锈库存', 't（铁当量）', 'p.plant.safetyFe, p.station.safetyOx'
    'SOC_k', '全网荷电状态', '—', 'env.soc()'
    'Φ̄', '平均日燃铁通量', 't/d', 'stats.Phi'
    'D_max, U_max', '最长连续低风光天数、最长连续富余天数', 'd', 'stats.Dmax, stats.Umax'
    'δ^D, δ^U', '低风光期日净耗铁、富余期日净耗锈', 't/d', 'stats.deltaD, stats.deltaU'
    'M_crit, M_crit(ε), M_0', '临界循环质量、风险校准临界质量、基准质量', 't（铁当量）', 'cm.M_crit, cm.M_eps, cm.M_0'
    'q, ε', '低风光天数的几何尾参数、可接受风险', '—', 'stats.qhat, p.stats.epsRisk'
    's_k, ξ_k, z_k', '状态、外生状态、上一日未赋价物理数量', '—', 'obs.s, obs.xi, obs.z'
    'π_w, 𝒲', '编号为 w 的策略、策略库', '—', 'jointPolicy, policyLibrary'
    'γ', '折扣因子，有效时域为 (1−γ)⁻¹', '—', 'p.ctdf.gammaStages'
    'm^π, Q^π', '后继测度、动作价值', '—、元', 'sampleGHM, riskValue'
    'v_θ, v^P_θ, θ̄', '速度场网络、投影速度场、目标网络参数', '—', 'velocityForward, nullSpaceProj, model.ema'
    'P, Π', '零空间投影矩阵、到 𝓜(c) 的欧氏投影', '—', 'nullSpaceProj, projectSimplex'
    '𝓜(c)', '守恒可行集 {x ≥ 0 : 1ᵀx = c}', '—', '—'
    'R_w, λ, ϑ, K', '折扣预测短缺暴露、风险权重、平滑参数、采样数', '—', 'riskValue, p.ctdf.lambda, p.ctdf.varthetaDays, p.ctdf.K'
    };
T = cell2table(rows, 'VariableNames', {'符号', '含义', '单位', '代码变量'});
end
