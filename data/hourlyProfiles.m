function [RE, D, shS] = hourlyProfiles(EW, ES, EL, doy, w)
%HOURLYPROFILES 由日电量与日序生成小时级风光出力与负荷（典型日形状 × 日电量）。
%   输入：EW、ES、EL 为 1×N 日电量（MWh），doy 为 1×N 日序（1..365），w = p.weather。
%   输出：RE、D 为 24×N（MW，Δt = 1 h，故小时电量数值等于功率）；shS 为光伏形状 24×N。
%   风电形状：1 + a·cos(2π(t − t0)/24)；光伏形状：日照时长随季节变化、以 solarNoon 为中心的正弦；
%   负荷形状：日间抬升、夜间回落与晚高峰叠加。各形状按列归一化，使日电量守恒。

EW = reshape(EW, 1, []);
ES = reshape(ES, 1, []);
EL = reshape(EL, 1, []);
doy = reshape(doy, 1, []);
t = (1:24)' - 0.5;

shW = 1 + w.shapeWAmp * cos(2 * pi * (t - w.shapeWPeak) / 24);
shW = shW / sum(shW);

dl = w.dayLen0 + w.dayLenAmp * cos(2 * pi * (doy - 172) / 365);   % 1×N 日照时长
noon = 12;
if isfield(w, 'solarNoon')
    noon = w.solarNoon;                                          % 出力重心时刻（北京时间；实测数据由 fitWeatherModel 估计）
end
sr = noon - dl / 2;                                              % 1×N 日出时刻
shS = max(0, sin(pi * (t - sr) ./ dl));                          % 24×N
shS = shS ./ max(sum(shS, 1), eps);

shL = 1 + w.loadDayAmp * sin(pi * (t - 7) / 14) .* (t >= 7 & t <= 21) ...
    - w.loadNightDip * (t <= 6) ...
    + w.loadEveAmp * exp(-((t - w.loadEvePeak) / w.loadEveWidth) .^ 2);
shL = shL / sum(shL);

RE = shW * EW + shS .* ES;
D = shL * EL;
end
