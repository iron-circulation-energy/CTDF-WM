function W = genWeatherYears(p, seed)
%GENWEATHERYEARS 生成 Y 个合成气象年。
%   日尺度过程为“季节均值 + AR(1) + 三状态马尔可夫切换（1 常规、2 低风光、3 富余）”：
%       reg_d ~ P(reg_{d−1}, :)，eW_d = φW·eW_{d−1} + σW·ε，eS、eL 同理；
%       日电量由 weatherEnergies 给出，小时曲线由 hourlyProfiles 给出（典型日形状 × 日电量）。
%   低风光持续天数服从几何分布：P(D = d) = (1 − q)·q^(d−1)，P(D > d) = q^d，d ≥ 1，q = p.weather.qLow。
%   每年长度为 365 + tailDays，尾部天数只用于前瞻预测、场景窗口与片段截取，统计量只取前 365 天。
%   各年使用独立随机流（种子 seed·1000 + y），初始状态取平稳分布。
%   若 p.weather.source = 'csv'，改为调用 readWeatherCSV。
%
%   输出：W 为 1×Y 结构体数组，字段 reg、eW、eS、eL、doy、EW、ES、EL（1×N）、carbon、h2、year、N。

w = p.weather;
if strcmpi(w.source, 'csv')
    W = readWeatherCSV(w.csvFile, p);
    return;
end
if nargin < 2 || isempty(seed)
    seed = p.seed;
end
N = w.daysPerYear + w.tailDays;
% 马尔可夫链平稳分布
[V, Dg] = eig(w.P');
[~, k] = min(abs(diag(Dg) - 1));
piStat = real(V(:, k));
piStat = piStat / sum(piStat);
cp = cumsum(w.P, 2);
cp(:, end) = 1;

W = repmat(struct('reg', [], 'eW', [], 'eS', [], 'eL', [], 'doy', [], 'EW', [], 'ES', [], 'EL', [], ...
    'carbon', [], 'h2', [], 'year', [], 'N', []), 1, w.Y);
for y = 1:w.Y
    rs = RandStream('twister', 'Seed', seed * 1000 + y);
    reg = zeros(1, N);
    eW = zeros(1, N);
    eS = zeros(1, N);
    eL = zeros(1, N);
    r0 = find(rand(rs) <= cumsum(piStat), 1, 'first');
    w0 = w.sigW / sqrt(1 - w.phiW ^ 2) * randn(rs);
    s0 = w.sigS / sqrt(1 - w.phiS ^ 2) * randn(rs);
    l0 = w.sigL / sqrt(1 - w.phiL ^ 2) * randn(rs);
    for d = 1:N
        r0 = 1 + sum(rand(rs) > cp(r0, :));
        w0 = w.phiW * w0 + w.sigW * randn(rs);
        s0 = w.phiS * s0 + w.sigS * randn(rs);
        l0 = w.phiL * l0 + w.sigL * randn(rs);
        reg(d) = r0;
        eW(d) = w0;
        eS(d) = s0;
        eL(d) = l0;
    end
    doy = mod((1:N) - 1, 365) + 1;
    [EW, ES, EL] = weatherEnergies(reg, eW, eS, eL, doy, p);
    W(y).reg = reg;
    W(y).eW = eW;
    W(y).eS = eS;
    W(y).eL = eL;
    W(y).doy = doy;
    W(y).EW = EW;
    W(y).ES = ES;
    W(y).EL = EL;
    W(y).carbon = w.carbonRange(1) + diff(w.carbonRange) * rand(rs);
    W(y).h2 = w.h2Range(1) + diff(w.h2Range) * rand(rs);
    W(y).year = y;
    W(y).N = N;
end
end
