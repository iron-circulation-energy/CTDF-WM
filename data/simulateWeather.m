function seg = simulateWeather(hs, N, R, p, rs)
%SIMULATEWEATHER 从隐状态出发生成 R 条独立的气象延续（用于后继测度真值的分支回放）。
%   hs 为 1 天的隐状态：reg、eW、eS、eL、doy、carbon、h2（该日本身视为已实现）。
%   生成其后 N 天（第 1 列为次日），各路径独立；rs 为 RandStream。
%   输出 seg：reg、eW、eS、eL、doy、EW、ES、EL 为 R×N，carbon、h2 为标量。

w = p.weather;
cp = cumsum(w.P, 2);
cp(:, end) = 1;
reg = zeros(R, N);
eW = zeros(R, N);
eS = zeros(R, N);
eL = zeros(R, N);
r0 = hs.reg * ones(R, 1);
w0 = hs.eW * ones(R, 1);
s0 = hs.eS * ones(R, 1);
l0 = hs.eL * ones(R, 1);
for d = 1:N
    u = rand(rs, R, 1);
    r0 = 1 + sum(u > cp(r0, :), 2);
    w0 = w.phiW * w0 + w.sigW * randn(rs, R, 1);
    s0 = w.phiS * s0 + w.sigS * randn(rs, R, 1);
    l0 = w.phiL * l0 + w.sigL * randn(rs, R, 1);
    reg(:, d) = r0;
    eW(:, d) = w0;
    eS(:, d) = s0;
    eL(:, d) = l0;
end
doy = repmat(mod(hs.doy - 1 + (1:N), 365) + 1, R, 1);
[EW, ES, EL] = weatherEnergies(reg, eW, eS, eL, doy, p);
seg.reg = reg;
seg.eW = eW;
seg.eS = eS;
seg.eL = eL;
seg.doy = doy;
seg.EW = EW;
seg.ES = ES;
seg.EL = EL;
seg.carbon = hs.carbon;
seg.h2 = hs.h2;
end
