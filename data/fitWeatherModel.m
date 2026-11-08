function [p, rep] = fitWeatherModel(p, EW, ES, EL, train, hs)
%FITWEATHERMODEL 由实测日电量估计气象过程参数并写回 p.weather。
%   [p, rep] = fitWeatherModel(p, EW, ES, EL, train, hs)
%   EW、ES、EL  Y×365 日电量（MWh），与写入 CSV 的数值相同；train 为训练年份下标。
%   hs          可选，逐时统计（prepareRealData 给出）：windProfile（24×1 训练年平均逐时风电容量因子）、
%               dayLen（Y×365 光伏有效日照时长，h，无出力日为 NaN）、noon（Y×365 光伏出力重心时刻，h）。
%   估计内容（模型与 genWeatherYears/weatherEnergies/forecaster 完全一致）：
%     季节项   cf(doy) = a0 + A·cos(2π(doy − peak)/365)（风、光各一阶谐波，最小二乘）；
%              负荷 lf(doy) = 1 + A1·cos(2π(doy − p1)/365) + A2·cos(4π(doy − p2)/365)；
%     天气状态 classifyRegime（阈值 regLow、regHigh）；转移矩阵 P 由训练年内相邻日计数的频率估计；
%     状态乘子 mW(r) = Σ_{reg=r} cfW / Σ_{reg=r} cfW(doy)（比值的和式估计），mS 同理；
%     AR(1)    e = cf/(cf(doy)·m(reg)) − 1，φ = Σ e_t·e_{t−1}/Σ e_{t−1}²（年内），σ = 残差标准差；负荷 eL = lx/lf − 1 同理；
%     上限     cfWmax = cfSmax = 1（物理上限；读入实测数据时不截断，保证 readWeatherCSV 与 weatherEnergies 互逆）；
%     日内形状 风电 1 + a·cos(2π(t − t0)/24) 由平均逐时曲线的一阶谐波估计；光伏有效日照时长
%              dl(doy) = d0 + dA·cos(2π(doy − 172)/365) 与出力重心 solarNoon 由逐日曲线的二阶矩估计。
%   输出 rep：估计结果与诊断量（状态频率、平均低风光持续天数、训练年最长低风光连续天数等）。

w = p.weather;
tr = train(:)';
doy = 1:365;
cfW = EW(tr, :) / (p.re.capW * 24);
cfS = ES(tr, :) / (p.re.capS * 24);
lx = EL(tr, :) / (p.load.mean * 24);
% 1 季节谐波
[w.cfW0, w.cfWamp, w.cfWpeak] = harmonic1(cfW, doy);
[w.cfS0, w.cfSamp, w.cfSpeak] = harmonic1(cfS, doy);
[l0, w.lAmp1, w.lPeak1, w.lAmp2, w.lPeak2] = harmonic2(lx, doy);
w.cfWmax = 1;
w.cfSmax = 1;
p.weather = w;
% 2 天气状态与转移矩阵
reg = classifyRegime(EW(tr, :), ES(tr, :), repmat(doy, numel(tr), 1), p);
cnt = zeros(3);
for k = 1:numel(tr)
    r = reg(k, :);
    cnt = cnt + accumarray([r(1:end - 1)', r(2:end)'], 1, [3, 3]);
end
P = cnt ./ max(sum(cnt, 2), 1);
for r = 1:3
    if sum(cnt(r, :)) == 0
        P(r, :) = [1, 0, 0];
        warning('fitWeatherModel:emptyRegime', '训练年份中没有状态 %d 的日子，该行转移概率取“回到常规”。', r);
    end
end
w.P = P;
w.pLow = P(1, 2);
w.pSur = P(1, 3);
w.qLow = P(2, 2);
w.qSur = P(3, 3);
% 3 状态乘子
cfWs = w.cfW0 + w.cfWamp * cos(2 * pi * (doy - w.cfWpeak) / 365);
cfSs = w.cfS0 + w.cfSamp * cos(2 * pi * (doy - w.cfSpeak) / 365);
CWs = repmat(cfWs, numel(tr), 1);
CSs = repmat(cfSs, numel(tr), 1);
mW = ones(1, 3);
mS = ones(1, 3);
for r = 1:3
    s = reg == r;
    if any(s(:))
        mW(r) = sum(cfW(s)) / sum(CWs(s));
        mS(r) = sum(cfS(s)) / sum(CSs(s));
    end
end
w.mW = mW;
w.mS = mS;
% 4 AR(1) 残差
eW = cfW ./ (CWs .* mW(reg)) - 1;
eS = cfS ./ (CSs .* mS(reg)) - 1;
lf = 1 + w.lAmp1 * cos(2 * pi * (doy - w.lPeak1) / 365) + w.lAmp2 * cos(4 * pi * (doy - w.lPeak2) / 365);
eL = lx ./ repmat(lf, numel(tr), 1) - 1;
[w.phiW, w.sigW] = ar1(eW);
[w.phiS, w.sigS] = ar1(eS);
[w.phiL, w.sigL] = ar1(eL);
% 5 日内形状
if nargin >= 6 && ~isempty(hs)
    if isfield(hs, 'windProfile') && ~isempty(hs.windProfile)
        t = (1:24)' - 0.5;
        y = hs.windProfile(:) / mean(hs.windProfile) - 1;
        X = [cos(2 * pi * t / 24), sin(2 * pi * t / 24)];
        b = X \ y;
        w.shapeWAmp = hypot(b(1), b(2));
        w.shapeWPeak = mod(atan2(b(2), b(1)) * 24 / (2 * pi), 24);
    end
    if isfield(hs, 'dayLen') && ~isempty(hs.dayLen)
        dl = hs.dayLen(tr, :);
        nn = hs.noon(tr, :);
        D = repmat(doy, numel(tr), 1);
        ok = isfinite(dl) & isfinite(nn);
        fitDays = D(ok); fitLength = dl(ok);
        X = [ones(nnz(ok), 1), cos(2 * pi * (fitDays(:) - 172) / 365)];
        b = X \ fitLength(:);
        w.dayLen0 = b(1);
        w.dayLenAmp = b(2);
        w.solarNoon = mean(nn(ok));
    end
end
p.weather = w;
% 诊断
lowRun = 0;
for k = 1:numel(tr)
    lowRun = max(lowRun, maxRun(reg(k, :) == 2));
end
freq = arrayfun(@(r) mean(reg(:) == r), 1:3);
rep = struct('P', P, 'counts', cnt, 'freq', freq, 'mW', mW, 'mS', mS, ...
    'phi', [w.phiW, w.phiS, w.phiL], 'sig', [w.sigW, w.sigS, w.sigL], ...
    'cfW', [w.cfW0, w.cfWamp, w.cfWpeak], 'cfS', [w.cfS0, w.cfSamp, w.cfSpeak], ...
    'load', [l0, w.lAmp1, w.lPeak1, w.lAmp2, w.lPeak2], 'meanLowDays', 1 / max(1 - P(2, 2), eps), ...
    'maxLowRunTrain', lowRun, 'meanCfW', mean(cfW(:)), 'meanCfS', mean(cfS(:)), 'train', tr);
end

function [a0, A, pk] = harmonic1(Y, doy)
% 训练年逐日平均后做一阶谐波最小二乘（各年 365 天等权，与逐日堆叠的最小二乘等价）
y = mean(Y, 1)';
th = 2 * pi * doy(:) / 365;
b = [ones(365, 1), cos(th), sin(th)] \ y;
a0 = b(1);
A = hypot(b(2), b(3));
pk = mod(atan2(b(3), b(2)) * 365 / (2 * pi), 365);
end

function [a0, A1, p1, A2, p2] = harmonic2(Y, doy)
y = mean(Y, 1)';
th = 2 * pi * doy(:) / 365;
b = [ones(365, 1), cos(th), sin(th), cos(2 * th), sin(2 * th)] \ y;
a0 = b(1);
A1 = hypot(b(2), b(3)) / a0;
p1 = mod(atan2(b(3), b(2)) * 365 / (2 * pi), 365);
A2 = hypot(b(4), b(5)) / a0;
p2 = mod(atan2(b(5), b(4)), 2 * pi) * 365 / (4 * pi);
end

function [phi, sig] = ar1(E)
% 年内 AR(1)：φ = Σ e_t·e_{t−1}/Σ e_{t−1}²，截断到 [0, 0.99]；σ 为残差标准差
x0 = E(:, 1:end - 1);
x1 = E(:, 2:end);
phi = min(0.99, max(0, sum(x0(:) .* x1(:)) / max(sum(x0(:) .^ 2), eps)));
res = x1 - phi * x0;
sig = std(res(:), 1);
end

function m = maxRun(b)
m = 0;
c = 0;
for k = 1:numel(b)
    if b(k)
        c = c + 1;
        m = max(m, c);
    else
        c = 0;
    end
end
end
