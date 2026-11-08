function logE1Comprehensive(fid, A, outDir)
%LOGE1COMPREHENSIVE 记录并导出全面核算（e1Comprehensive）的逐项与各口径合计（亿元）。
it = A.items;
for k = 1:height(it)
    logMsg(fid, 'E1 全面核算 [%s] %s：年度修正 %+.2f 亿元/年，保留资产价值修正 %+.1f 亿元（%s）。', it.category{k}, ...
        it.item{k}, it.dAnnual(k) / 1e8, it.dRV(k) / 1e8, it.basis{k});
end
S = A.summary;
nm = {'base', '原核算'; 'core', '核心（当前成本）'; 'coreToday_design', '核心 + 储氢缓冲设计（当前成本）'; ...
    'allToday', '核心 + 设计 + 副产品（当前成本）'; 'core2030', '核心（2030 年成本）'; ...
    'design2030', '核心 + 储氢缓冲设计（2030 年成本）'; 'all2030', '核心 + 设计 + 副产品（2030 年成本）'; ...
    'kappaToday', '核心 + 还原氢耗情景（当前成本）'; 'kappa2030', '核心 + 设计 + 还原氢耗情景（2030 年成本）'; ...
    'all2030kappa', '核心 + 设计 + 还原氢耗情景 + 副产品（2030 年成本）'; ...
    'coreRail', '核心 + 铁路边际成本（当前成本）'; 'all2030Rail', '核心 + 设计 + 副产品 + 铁路边际成本（2030 年成本）'; ...
    'all2030RailPolicy', '核心 + 设计 + 副产品 + 铁路边际成本 + 消纳责任权重（2030 年成本）'};
for k = 1:size(nm, 1)
    logMsg(fid, 'E1 全面核算 %s：年度成本差 %+.2f 亿元/年；保留资产价值 共同会计期 %d 年 %+.1f 亿元，延寿会计期 %d 年 %+.1f 亿元。', ...
        nm{k, 2}, S.(nm{k, 1}) / 1e8, S.Nrem, S.(['RV_' nm{k, 1}]) / 1e8, S.Nlong, S.(['RVlong_' nm{k, 1}]) / 1e8);
end
if isfield(S, 'railFracBreakEven') && isfinite(S.railFracBreakEven)
    logMsg(fid, 'E1 盈亏平衡（最有利口径）：铁路边际运营成本占运价比例低于 %.1f%% 时改造优于替代方案。', 100 * S.railFracBreakEven);
end
if isfield(A, 'breakEven')
    B = A.breakEven;
    logMsg(fid, ['E1 盈亏平衡（两条路线电解槽单位投资同时下降）：核心口径 %.2f 倍（%.0f 元/kW），', ...
        '核心 + 设计（2030 年还原厂）%.2f 倍（%.0f 元/kW），还原氢耗情景下 %.2f 倍（%.0f 元/kW）；≤ 0 表示仅靠电解槽降价不可达。'], ...
        B.fEl_core, B.perKw_core, B.fEl_design2030, B.perKw_design2030, B.fEl_kappa2030, B.perKw_kappa2030);
end
O = A.owner;
fom = 0;
if isfield(O, 'fixedOMPV'), fom = O.fixedOMPV; end
logMsg(fid, 'E1 投资方视角（电厂业主）：容量电价现值 %.1f 亿元，机组改造与延寿投资 %.1f 亿元，固定运维现值 %.1f 亿元，拆除费用 退役即付 %.1f、改造推迟后现值 %.1f 亿元；改造相对退役的业主净值 %+.1f 亿元；另避免账面核销 %.1f 亿元。', ...
    O.capacityRevenuePV / 1e8, O.retrofitPlantCapex / 1e8, fom / 1e8, O.decomRetire / 1e8, O.decomRetrofitPV / 1e8, ...
    O.netOwnerRetrofitMinusRetire / 1e8, O.avoidedWriteOff / 1e8);
L = A.lifecycle;
logMsg(fid, 'E1 全生命周期：原始投资 %.1f 亿元，剩余账面价值 %.1f 亿元（若退役则 %.0f%% 搁浅），改造延长服役 %.1f 年。', ...
    L.originalInvestment / 1e8, L.remainingBook / 1e8, 100 * L.shareStrandedIfRetired, L.yearsAddedService);
if nargin >= 3 && ~isempty(outDir)
    T = A.items;
    T.dAnnual_yi = T.dAnnual / 1e8;
    T.dRV_yi = T.dRV / 1e8;
    writetable(T, fullfile(outDir, 'E1_comprehensive.csv'), 'Encoding', 'UTF-8');
end
end
