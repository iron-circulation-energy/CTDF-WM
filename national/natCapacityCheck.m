function t = natCapacityCheck(svc, r, n, loopDays)
%NATCAPACITYCHECK 省级稳定供电单元的事件缓冲质量与序列峰值库存（每 1 MW 平均负荷，t/MW）。
%   t = natCapacityCheck(svc, r, n, loopDays)
%   svc       natStorage 的输出（按铁路线往返效率计算），使用其日缺电量 de 与日充电量 ch（平均负荷 = 1）
%   r         Y×365 风光组合日容量因子（划分低风光日、富余日）
%             各行必须是相邻年；svc.years非空时校验真实历年。无年份的合成调用遵守相同行序约定。
%   loopDays  闭环周转时间 T_loop（d）
%   日必需燃铁 B_d = 24·de_d/(η_st·h_Fe)，日还原 A_d = 24·ch_d/e_red（t/d 每 MW 平均负荷），净耗 net = B − A；
%   天气状态与区域层 classifyRegime 口径一致：r 与其一阶季节谐波基准之比 < regLow 为低风光日，> regHigh 为富余日；
%   δ^D、δ^U、D_max、U_max 的分位数与 estimateStats 相同（params_default 的 p.stats）。
%     M_event = Φ̄·T_loop + δ^D·D_max + δ^U·U_max                 （临界循环质量，不含安全库存）
%     M_sp  = 24·S/(η_st·h_Fe) + Φ̄·T_loop                      （序列峰值储能能量折算的铁库存 + 在途量）
%   二者之比反映单次最长事件缓冲与季节性累计亏欠的关系。

f = n.fe;
eOut = f.etaSt * f.hFe;
eRed = f.hFe * f.kappa / f.etaEl + f.eps;
B = 24 * svc.de / eOut;
A = 24 * svc.ch / eRed;
net = B - A;
[Y, nd] = size(r);
if isfield(svc,'years') && ~isempty(svc.years)
    years = svc.years;
    if ~isnumeric(years) || ~isreal(years) || ~isvector(years) || numel(years)~=Y || ...
            any(~isfinite(years)) || any(years~=fix(years)) || any(diff(years(:))~=1)
        error('natCapacityCheck:nonConsecutiveYears','Event statistics require consecutive integer calendar years matching the rows.');
    end
end
doy = repmat(1:nd, Y, 1);
th = 2 * pi * (1:nd)' / nd;
b = [ones(nd, 1), cos(th), sin(th)] \ mean(r, 1)';
base = b(1) + b(2) * cos(2 * pi * doy / nd) + b(3) * sin(2 * pi * doy / nd);
ratio = r ./ max(base, eps);
low = ratio < n.regime.low;
high = ratio > n.regime.high;
% Join actual consecutive year boundaries, without wrapping the record's last
% observation back to its first. The sizing cycle is not an observed event.
Dr = runLengths(reshape(low',1,[]));
Ur = runLengths(reshape(high',1,[]));
dpos = max(net(low), 0);
upos = max(-net(high), 0);
if isempty(dpos)
    dpos = 0;
end
if isempty(upos)
    upos = 0;
end
if isempty(Dr)
    Dr = 1;
end
if isempty(Ur)
    Ur = 1;
end
t.Phi = mean(B(:));
t.deltaD = quantileLin(dpos, n.stats.deltaQuantile);
t.deltaU = quantileLin(upos, n.stats.deltaQuantile);
t.Dmax = ceil(quantileLin(Dr, n.stats.dQuantile) - 1e-9);
t.Umax = ceil(quantileLin(Ur, n.stats.dQuantile) - 1e-9);
t.lowFreq = mean(low(:));
t.Mevent = t.Phi * loopDays + t.deltaD * t.Dmax + t.deltaU * t.Umax;
t.Msp = 24 * svc.S / eOut + t.Phi * loopDays;
end
