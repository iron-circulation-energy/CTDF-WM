function reg = classifyRegime(EW, ES, doy, p)
%CLASSIFYREGIME 实测日电量的天气状态划分（1 常规、2 低风光、3 富余）。
%   比值 r = (EW + ES)/(capW·24·cfW(doy) + capS·24·cfS(doy))，cfW、cfS 为季节基准（p.weather 的一阶谐波），
%   r < p.weather.regLow 为低风光，r > p.weather.regHigh 为富余，其余为常规。
%   readWeatherCSV（读取）与 fitWeatherModel（估计转移矩阵与状态乘子）共用本函数，保证口径一致。

w = p.weather;
cfW = w.cfW0 + w.cfWamp * cos(2 * pi * (doy - w.cfWpeak) / 365);
cfS = w.cfS0 + w.cfSamp * cos(2 * pi * (doy - w.cfSpeak) / 365);
ratio = (EW + ES) ./ (p.re.capW * 24 * cfW + p.re.capS * 24 * cfS);
reg = ones(size(ratio));
reg(ratio < w.regLow) = 2;
reg(ratio > w.regHigh) = 3;
end
