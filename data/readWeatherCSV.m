function W = readWeatherCSV(file, p)
%READWEATHERCSV 读取实测日尺度风光与负荷数据，替代合成气象年。
%   CSV 列：year, day, EW, ES, EL（MWh/日），可选 regime（1 常规、2 低风光、3 富余）。
%   缺少 regime 时由 classifyRegime 按风光日电量相对季节基准的比值划分（< regLow 为低风光，> regHigh 为富余）。
%   p.weather.csvLastIsTail 为真时，CSV 最后一年只作为前一年的尾部（不作为模型年份；prepareRealData 使用）。
%   隐 AR 残差由观测方程反解：e = E /(cap·24·cf(doy)·m(reg)) − 1，使条件预测可用。
%   年份须连续；每年须恰有 day=1:365，且没有缺日或重复日。闰年须先删除 2 月 29 日，再将日序重排为 1:365，
%   与 era5ToHourly 的日历一致；不能直接截去闰年的第 366 天。以下一年开头 tailDays 天作为尾部；
%   最后一个模型年在 csvLastIsTail 为假时以第一年开头循环补齐
%   尾部（尾部只用于前瞻预测、场景窗口与片段截取，统计量只取前 365 天），使各年长度一致（365 + tailDays）。列名不区分大小写。
%   注意：气象过程参数（季节项、转移矩阵 P、状态乘子、AR(1)）取自 p.weather；使用实测数据时应先用训练年份重新估计
%   （prepareRealData → fitWeatherModel 自动完成）。

if isempty(file) || ~isfile(file)
    error('readWeatherCSV:file', '找不到气象 CSV 文件：%s。', file);
end
T = readtable(file);
need = {'year', 'day', 'EW', 'ES', 'EL', 'regime'};
vn = T.Properties.VariableNames;
for m = 1:numel(need)
    k = find(strcmpi(vn, need{m}), 1);
    if isempty(k)
        if m <= 5
            error('readWeatherCSV:col', 'CSV 缺少列 %s。', need{m});
        end
    else
        vn{k} = need{m};
    end
end
T.Properties.VariableNames = vn;
T = sortrows(T, {'year', 'day'});
yrs = unique(T.year)';
if isempty(yrs) || ~isnumeric(T.year) || any(~isfinite(T.year)) || any(T.year ~= fix(T.year))
    error('readWeatherCSV:calendar','CSV year 必须为有限整数，且每年至少包含完整的 365 天。');
end
if any(diff(yrs) ~= 1)
    error('readWeatherCSV:calendar','CSV 年份必须连续；不能将缺失年份两侧的记录拼成相邻天气日。');
end
for y = yrs
    days = T.day(T.year == y);
    if ~isnumeric(days) || ~isequal(days(:), (1:365)')
        error('readWeatherCSV:calendar', ['CSV 的 %d 年必须恰有唯一的 day=1:365（不能缺日或重复）。' ...
            '闰年请先删除 2 月 29 日并重排日序；不接受未经转换的 366 天日历。'], y);
    end
end
w = p.weather;
nY = numel(yrs);
if isfield(w, 'csvLastIsTail') && w.csvLastIsTail
    nY = nY - 1;                                      % 最后一年只作为尾部
    if nY < 1
        error('readWeatherCSV:tail', 'csvLastIsTail 为真时 CSV 至少需要 2 个年份。');
    end
end
W = repmat(struct('reg', [], 'eW', [], 'eS', [], 'eL', [], 'doy', [], 'EW', [], 'ES', [], 'EL', [], ...
    'carbon', [], 'h2', [], 'year', [], 'N', [], 'calendarYear', [], 'sourceYearIndex', []), 1, nY);
rs = RandStream('twister', 'Seed', p.seed + 5);
for m = 1:nY
    rows = T.year == yrs(m);
    if m < numel(yrs)
        nxt = find(T.year == yrs(m + 1));
    else
        nxt = find(T.year == yrs(1));                 % 最后一年：以第一年开头循环补齐尾部
    end
    rows = find(rows);
    rows = [rows; nxt(1:min(numel(nxt), w.tailDays))]; %#ok<AGROW>
    EW = T.EW(rows)';
    ES = T.ES(rows)';
    EL = T.EL(rows)';
    N = numel(rows);
    doy = mod((1:N) - 1, 365) + 1;
    cfW = w.cfW0 + w.cfWamp * cos(2 * pi * (doy - w.cfWpeak) / 365);
    cfS = w.cfS0 + w.cfSamp * cos(2 * pi * (doy - w.cfSpeak) / 365);
    lf = 1 + w.lAmp1 * cos(2 * pi * (doy - w.lPeak1) / 365) + w.lAmp2 * cos(4 * pi * (doy - w.lPeak2) / 365);
    if any(strcmp(T.Properties.VariableNames, 'regime'))
        reg = T.regime(rows)';
    else
        reg = classifyRegime(EW, ES, doy, p);
    end
    W(m).reg = reg;
    W(m).eW = EW ./ (p.re.capW * 24 * cfW .* w.mW(reg)) - 1;
    W(m).eS = ES ./ (p.re.capS * 24 * cfS .* w.mS(reg)) - 1;
    W(m).eL = EL ./ (p.load.mean * 24 * lf) - 1;
    W(m).doy = doy;
    W(m).EW = EW;
    W(m).ES = ES;
    W(m).EL = EL;
    W(m).carbon = w.carbonRange(1) + diff(w.carbonRange) * rand(rs);
    W(m).h2 = w.h2Range(1) + diff(w.h2Range) * rand(rs);
    W(m).year = m;
    W(m).N = N;
    W(m).calendarYear = yrs(m);
    [~, W(m).sourceYearIndex] = ismember(T.year(rows)', yrs);
end
end
