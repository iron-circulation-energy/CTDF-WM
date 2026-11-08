function natFigures(R, N, n)
%NATFIGURES 绘制全国评估图 N01—N09（N07 需要 R.sustain，N08 需要 R.mc，N09 需要 R.Tport）（保存到 n.figDir，格式同 saveFigure：.fig、.pdf、600 dpi .png）。
p = params_default('haoji');
p.caseName = 'national';
S = plotStyle(p);
d = n.figDir;
N01_storageCoalMap(R, N, S, fullfile(d, 'N01_storage_coal_map'));
N02_ironMassMap(R, S, fullfile(d, 'N02_iron_mass_map'));
N03_routeMap(R, N, S, fullfile(d, 'N03_route_map'));
N04_lcosCurves(R, S, fullfile(d, 'N04_lcos_curves'));
N05_capacityCheck(R, S, fullfile(d, 'N05_capacity_check'));
N06_scenarioWinners(R, S, fullfile(d, 'N06_scenario_winners'));
if isfield(R, 'sustain') && ~isempty(R.sustain)
    N07_sustainability(R.sustain, S, fullfile(d, 'N07_sustainability'), R.T);
end
if isfield(R, 'mc') && ~isempty(R.mc)
    N08_mcRobustness(R.mc, S, fullfile(d, 'N08_mc_robustness'));
end
if isfield(R, 'Tport')
    N09_portfolioMix(R, S, fullfile(d, 'N09_portfolio_mix'));
end
fprintf('全国评估图已保存到 %s。\n', d);
end
