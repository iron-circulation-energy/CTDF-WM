function files = paperFigures(res, p, outDir, nat)
%PAPERFIGURES 正文图 2—6：把单图函数组合为 a—d 面板，宽 180 mm，面板字母为加粗小写（8 pt）。
%   图 2 a F25 设计图、b F05、c F21、d F22；图 3 a F09、b F13、c F23、d F08；图 4 a F10、b F11、c F19；
%   图 5 a F17、b F12、c F24、d F26；图 6 a N03、b N04、c N06、d N09。以下为原有面板的样式说明。
%   files = paperFigures(res, p, outDir, nat)
%   res   runExperiments 的输出（capacity、e1—e6 等字段）；p 为参数；outDir 为输出目录；
%   nat   可选，struct('R', 全国评估结果, 'N', 全国输入)，缺省时图 6 的面板标为待生成。
%   每个面板独立绘制：某一面板的数据缺失或绘制出错时，该面板显示提示文字，其余面板照常输出。
%   面板与单图函数（模板对应）：
%     图 2  a F05 双样本山脊图（逐月山脊：实心 vs 描边）；b F21 可靠性曲线 + 分区底色 + 倍数标注；
%           c F22 事件平面（缓冲 × 持续天数）+ 右侧对数副轴的断供概率
%     图 3  a F09 低风光事件行带（缓冲剩余底色 + 白衬库存曲线 + 红框 + 安全天数条形）；
%           b F13 六边形密度 + 中位数/分位线 + 边缘分布；c F23 横向云雨图（半小提琴 + 圆角箱 + 回合散点）
%     图 4  a F10 分组箱线 + 抖动散点 + 显著性字母；b F11 火山图（提升 × −log10 P）+ 各要素平均提升竖色带
%     图 5  a F17 三元热图 + 光晕气泡（面积 ∝ 保留价值）+ 渐变流向弧 + 分项环带；b F12 三角网格发散色热图 + 盈亏边界
%     图 6  a N03 路线地图 + 特高压流线（FeT 线路着色）+ 局部放大 + 比例尺与指北针；
%           b N04 各省 LCOS × 自治天数散点 + 路线族密度等值线 + 边缘密度；c N06 情景 × 省份热力图 + 顶部折线 + 右侧条形
if nargin < 4
    nat = [];
end
if ~exist(outDir, 'dir')
    mkdir(outDir);
end
S = plotStyle(p);
S.fs = 7;
S.note = '';
W = 180 / 25.4;
files = {};
g = @(name) getRes(res, name);

dp = designPoint();

fig = styledFigure(S, W, 6.0);
panel(fig, S, 'a', [0.00, 0.52, 0.47, 0.48], @(t) F25_designMap(dp.T, p, S, '', dp.bMin, dp.bSel, t));
panel(fig, S, 'b', [0.00, 0.00, 0.47, 0.50], @(t) F05_criticalRidges(g('e2'), S, '', t));
panel(fig, S, 'c', [0.52, 0.52, 0.48, 0.48], @(t) F21_reliabilityCurve(g('e2'), S, '', t));
panel(fig, S, 'd', [0.52, 0.00, 0.48, 0.50], @(t) F22_eventTail(g('capacity'), S, '', t));
files{end + 1} = saveOut(fig, fullfile(outDir, 'Fig2'));

fig = styledFigure(S, W, 5.8);
panel(fig, S, 'a', [0.00, 0.34, 0.54, 0.66], @(t) F09_droughtWaterfall(g('e3'), p, S, '', t));
panel(fig, S, 'b', [0.57, 0.52, 0.43, 0.48], @(t) F13_policyHexbin(g('e3'), S, '', t));
panel(fig, S, 'c', [0.57, 0.00, 0.43, 0.50], @(t) F23_stressBox(g('e3'), S, '', t));
panel(fig, S, 'd', [0.00, 0.00, 0.54, 0.32], @(t) F08_dailyCostBox(g('e3'), S, '', t));
files{end + 1} = saveOut(fig, fullfile(outDir, 'Fig3'));

fig = styledFigure(S, W, 3.4);
panel(fig, S, 'a', [0.00, 0.00, 0.36, 1.00], @(t) F10_horizonBubbles(g('e4'), S, '', t));
panel(fig, S, 'b', [0.37, 0.00, 0.38, 1.00], @(t) F11_elementGain(g('e5'), S, '', t));
panel(fig, S, 'c', [0.77, 0.00, 0.23, 1.00], @(t) F19_scaling(g('e7'), S, '', t));
files{end + 1} = saveOut(fig, fullfile(outDir, 'Fig4'));

fig = styledFigure(S, W, 6.2);
% 图 5：a 年化成本差由基础核算到全面核算的分解；b 运价 × 往返效率下的保留价值（全面核算）；c 保留价值随循环质量的变化
panel(fig, S, 'a', [0.00, 0.00, 0.52, 1.00], @(t) F26_accountWaterfall(g('e1'), S, '', t));
panel(fig, S, 'b', [0.55, 0.50, 0.45, 0.50], @(t) F12_sensSurface(g('e6'), S, '', t, acctOf(res)));
panel(fig, S, 'c', [0.55, 0.00, 0.45, 0.47], @(t) F24_reliabilityValue(g('e1'), S, '', t));
files{end + 1} = saveOut(fig, fullfile(outDir, 'Fig5'));

fig = styledFigure(S, W, 9.4);
if isempty(nat)
    nat = struct('R', [], 'N', []);
end
panel(fig, S, 'a', [0.00, 0.56, 0.62, 0.44], @(t) N03_routeMap(nat.R, nat.N, S, '', t));
panel(fig, S, 'b', [0.64, 0.58, 0.36, 0.42], @(t) N04_lcosCurves(nat.R, S, '', t));
panel(fig, S, 'c', [0.00, 0.00, 0.58, 0.54], @(t) N06_scenarioWinners(nat.R, S, '', t));
panel(fig, S, 'd', [0.60, 0.00, 0.40, 0.54], @(t) N09_portfolioMix(nat.R, S, '', t));
files{end + 1} = saveOut(fig, fullfile(outDir, 'Fig6'));
end

function dp = designPoint()
% 设计扫描结果（config/design_point.mat，designSelect 写入）：表格、纯成本最低点与选定设计点的行号
dp = struct('T', [], 'bMin', [], 'bSel', []);
f = fullfile(fileparts(which('params_paper')), 'design_point.mat');
if ~isfile(f)
    return;
end
L = load(f);
if ~isfield(L, 'T')
    return;
end
T = L.T;
dp.T = T;
d = L.design;
dp.bSel = find(T.mult == d.pMult & abs(T.cKt * 1e3 - d.cNominal) < 1, 1);
if isfield(d, 'minCostMult')
    dp.bMin = find(T.mult == d.minCostMult & abs(T.cKt * 1e3 - d.minCostC) < 1, 1);
else
    [~, dp.bMin] = min(T.totalAnnual);
end
end

function A = acctOf(res)
A = [];
if isfield(res, 'e1') && isfield(res.e1, 'acct')
    A = res.e1.acct;
end
end

function v = getRes(res, name)
if ~isfield(res, name) || isempty(res.(name))
    error('paperFigures:missing', 'Result %s is not available yet.', name);
end
v = res.(name);
end

function panel(fig, S, letter, pos, fn)
% 在区域 pos 内绘制一个面板并标注字母；出错时显示提示文字
try
    fn(struct('fig', fig, 'pos', pos));
catch err
    where = '';
    if ~isempty(err.stack)
        where = sprintf(' (%s 第 %d 行)', err.stack(1).name, err.stack(1).line);
    end
    warning('paperFigures:panel', 'Panel %s: %s%s', letter, err.message, where);
    ax = axes(fig, 'Position', pos, 'Visible', 'off');
    text(ax, 0.5, 0.5, lab(S, '面板待生成', 'Panel pending'), 'HorizontalAlignment', 'center', ...
        'Color', S.tick, 'FontName', S.font, 'FontSize', S.fs);
end
% 面板字母：画在覆盖整幅图窗的不可见坐标轴上（跨版本一致）
ov = axes(fig, 'Position', [0, 0, 1, 1], 'Visible', 'off', 'HitTest', 'off');
xlim(ov, [0, 1]);
ylim(ov, [0, 1]);
text(ov, pos(1) + 0.004, pos(2) + pos(4) - 0.004, letter, 'FontWeight', 'bold', 'FontSize', 8, 'FontName', S.font, ...
    'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', 'Color', S.ink);
end

function f = saveOut(fig, base)
saveFigure(fig, base);
f = [base, '.pdf'];
end
