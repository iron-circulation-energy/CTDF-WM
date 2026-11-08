function S = plotStyle(p)
%PLOTSTYLE 论文仿真图统一样式（依据模板图：青—米—赭配色、本文方法暖色突出、对比方法冷色/灰色）。
%   补充材料中的图为单图；正文图由 paperFigures 把若干单图组合为 a、b、c 面板。
%   视觉规则
%     · 坐标轴只保留左、下边框，刻度向外，浅灰网格；英文图用无衬线字体（Arial），中文图用衬线字体（思源宋体）；
%     · 本文方法 CTDF-WM 统一为赭色（S.hero），对比方法为深蓝、金、青、浅蓝，固定策略为中灰；
%     · 亮点元素：红框（S.hl，标出关键单元格或区域）、徽标（badge，关键数字）、区间带与边缘分布。
%   输出 S 的字段
%     lang、font、fs、w；颜色 ink、axis、tick、grid、land、cream、accent、hero、hl、slate、teal、sand、dark、mute；
%     色图（256×3）div（深青—米白—深赭，发散）、seq（米白—深青蓝，顺序）、warm（米白—深赭）、year、flow（地图流线）；
%     methodColor(name)、methodLabel(name)、methodOrder；note（冒烟算例提示）。

S.lang = 'en';                         % 投稿图一律英文
S.exportFs = 18;                      % 导出字号（磅），见 scaleForExport
S.exportFont = 'Times New Roman';     % 导出字体，加粗
if isfield(p, 'plot') && isfield(p.plot, 'exportFontSize') && ~isempty(p.plot.exportFontSize)
    S.exportFs = p.plot.exportFontSize;
end
if strcmp(S.lang, 'en')
    S.font = pickFont('Times New Roman', {'Times', 'Liberation Serif', 'DejaVu Serif'});
else
    S.font = pickFont(p.plot.font, {'Source Han Serif SC', 'Source Han Serif CN', '思源宋体', '思源宋体 CN', ...
        'Noto Serif CJK SC', 'Noto Serif SC', 'Songti SC', 'STSong', 'SimSun', '宋体', 'Times New Roman'});
end
S.fs = p.plot.fontSize;
S.w = p.plot.widthIn;

% 中性色
S.ink = hex2rgb('#262626');
S.axis = hex2rgb('#8C8C8C');
S.tick = hex2rgb('#6B6B6B');
S.grid = hex2rgb('#ECECEC');
S.land = hex2rgb('#EEF1F3');
S.cream = hex2rgb('#F6F2EA');
S.mute = hex2rgb('#9A9A9A');
% 主题色（模板 8、9：赭、深蓝、青、金）
S.hero = hex2rgb('#C8643C');          % 本文方法
S.accent = S.hero;
S.hl = hex2rgb('#C0392B');            % 红框与强调
S.slate = hex2rgb('#2C4E6E');
S.teal = hex2rgb('#3E9089');
S.sand = hex2rgb('#E0B062');
S.dark = hex2rgb('#1E3850');
S.sky = hex2rgb('#86AACB');

% 色图
S.div = makeMap({'#244B63', '#3E8089', '#8EC0B7', '#F4F0E8', '#EDBE9C', '#CF7A52', '#963B25'});
S.seq = makeMap({'#F5F3EC', '#D3E6DE', '#97C7BC', '#5AA29C', '#2F7684', '#1E4C66', '#16304A'});
S.warm = makeMap({'#F7F1E8', '#F0D3B8', '#E3A47E', '#CF7A52', '#A9502F', '#6E2E1C'});
S.year = makeMap({'#2C4A63', '#5F8F96', '#C9DDD3', '#EFE5C9', '#E2B87F', '#C66A45'});
S.flow = makeMap({'#3F5F8A', '#8FB1CA', '#F2E4C2', '#EE9C5E', '#CC4A31', '#8C1E1B'});
S.alpha = 0.2;

% 方法配色：本文方法赭色，对比方法冷色，固定策略灰色（两两可分，含色觉缺陷）
keys = {'M1', 'M0', 'M2', 'M3', 'M4', 'M2o'};
cols = {'#C8643C', '#8C8C8C', '#2C4E6E', '#3E9089', '#86AACB', '#5B5B7A'};
labs = {'本文 CTDF-WM', '固定联合策略', '随机 MPC', '逐步世界模型', '无守恒流模型', '完全信息 MPC'};
if strcmp(S.lang, 'en')
    labs = {'CTDF-WM', 'Fixed policy', 'Stochastic MPC', 'Stepwise model', 'Unconstrained flow', 'MPC (perfect info.)'};
end
mc = containers.Map(keys, cellfun(@hex2rgb, cols, 'UniformOutput', false));
ml = containers.Map(keys, labs);
S.methodColor = @(name) lookupMap(mc, name, hex2rgb('#7A7A7A'));
S.methodLabel = @(name) lookupMap(ml, name, name);
S.methodOrder = {'M1', 'M2', 'M3', 'M4', 'M0'};
S.note = '';
if isfield(p, 'caseName') && strcmpi(p.caseName, 'smoke')
    S.note = lab(S, '冒烟算例', 'Smoke case');
end
end

function v = lookupMap(m, key, def)
if isKey(m, key)
    v = m(key);
else
    v = def;
end
end

function f = pickFont(pref, fallback)
% 依次尝试首选字体与备选字体，返回系统中第一个可用的字体名（listfonts 不可用时返回首选字体）
cand = [{pref}, fallback];
f = pref;
try
    av = lower(listfonts);
    for k = 1:numel(cand)
        if any(strcmp(av, lower(cand{k})))
            f = cand{k};
            return;
        end
    end
catch
    % 无图形环境：保留首选字体
end
end

function c = hex2rgb(h)
h = char(h);
c = [hex2dec(h(2:3)), hex2dec(h(4:5)), hex2dec(h(6:7))] / 255;
end

function M = makeMap(hexes)
% 锚点颜色等距分布，线性插值为 256 级色图
A = cell2mat(cellfun(@hex2rgb, hexes(:), 'UniformOutput', false));
t = linspace(0, 1, size(A, 1));
M = interp1(t, A, linspace(0, 1, 256));
end
