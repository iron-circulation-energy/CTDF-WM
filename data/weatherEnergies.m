function [EW, ES, EL] = weatherEnergies(reg, eW, eS, eL, doy, p)
%WEATHERENERGIES 由隐状态计算日电量。
%   EW = capW·24·min(cfWmax, cfW(doy)·mW(reg)·max(0, 1 + eW))
%   ES = capS·24·min(cfSmax, cfS(doy)·mS(reg)·max(0, 1 + eS))
%   EL = L̄·24·lf(doy)·(1 + eL)
%   reg 取 1（常规）、2（低风光）、3（富余）；输入可为同尺寸数组。单位 MWh。

w = p.weather;
cfW = w.cfW0 + w.cfWamp * cos(2 * pi * (doy - w.cfWpeak) / 365);
cfS = w.cfS0 + w.cfSamp * cos(2 * pi * (doy - w.cfSpeak) / 365);
mW = reshape(w.mW(reg), size(reg));
mS = reshape(w.mS(reg), size(reg));
EW = p.re.capW * 24 * min(w.cfWmax, cfW .* mW .* max(0, 1 + eW));
ES = p.re.capS * 24 * min(w.cfSmax, cfS .* mS .* max(0, 1 + eS));
lf = 1 + w.lAmp1 * cos(2 * pi * (doy - w.lPeak1) / 365) + w.lAmp2 * cos(4 * pi * (doy - w.lPeak2) / 365);
EL = p.load.mean * 24 * lf .* (1 + eL);
end
