function s = estimateStats(W, years, p, Tl)
%ESTIMATESTATS 从训练年份估计临界循环质量与事件风险所需统计量，并给出自助法 95% 置信区间。
%   日必需燃铁量 B_d = must_d /(η̄·h_Fe)，日可吸收还原量 A_d = absorb_d / ē_red（均为 t/d，按 dailyDerived 口径）；
%   净耗 net_d = B_d − A_d。只使用每年前 365 天。
%     Φ̄      = mean(B_d)                                  （p.stats.flux = 'must'）
%     δ^D    = 低风光日 max(net_d, 0) 的 deltaQuantile 分位数；δ̄^D 为其均值（策略单位）
%     δ^U    = 富余日 max(−net_d, 0) 的 deltaQuantile 分位数；δ̄^U 为其均值
%     D_max  = 低风光持续天数的 dQuantile 分位数；U_max 同理
%     q̂      = 已观察到的低风光持续转移数 / 低风光出发转移数，末端删失不当作退出。
%   仅连续真实 calendarYear 合并跨年事件；各自独立生成的合成年不拼接。
%   自助法先固定完整事件的起始年份归属，再按年重抽样，避免拼接随机年份制造长事件。
%
%   输出 s：Phi、deltaD、deltaDbar、deltaU、deltaUbar、Dmax、Umax、qhat、meanD、Amean、Bmean、
%           Druns、Uruns、PhiP、deltaDbarP（nP×1）、deltaUbarR（nR×1）、ci（各量 1×2）、bootRaw。

etaBar = sum(p.plant.pmax .* p.plant.etaSt) / sum(p.plant.pmax);
eRedNom = p.iron.hFe * p.station.kappa ./ p.station.etaEl + p.station.epsAux;
eBar = sum(p.station.pRedMax .* eRedNom) / sum(p.station.pRedMax);
nd = p.weather.daysPerYear;
years = unique(years(:)');

per = struct('B', {}, 'A', {}, 'reg', {}, 'Druns', {}, 'Uruns', {});
for m = 1:numel(years)
    Wy = W(years(m));
    ix = 1:nd;
    [RE, D] = hourlyProfiles(Wy.EW(ix), Wy.ES(ix), Wy.EL(ix), Wy.doy(ix), p.weather);
    dv = dailyDerived(RE, D, p);
    per(m).B = dv.must / (etaBar * p.iron.hFe);
    per(m).A = dv.absorb / eBar;
    per(m).reg = Wy.reg(ix);
    per(m).Druns = [];
    per(m).Uruns = [];
    per(m).Dcensored = [];
    per(m).Ucensored = [];
    fromD = Wy.reg(ix(1:end - 1)) == 2;
    toD = Wy.reg(ix(2:end)) == 2;
    per(m).stayD = nnz(fromD & toD);
    per(m).exitD = nnz(fromD & ~toD);
end
% Events crossing a real calendar boundary retain their full observed duration.
% Counts/events are assigned once to original years before bootstrap resampling.
b0 = 1;
for m = 1:numel(years)
    adjacent = m < numel(years) && isfield(W, 'calendarYear') && ...
        ~isempty(W(years(m)).calendarYear) && ~isempty(W(years(min(m + 1, numel(years)))).calendarYear) && ...
        W(years(min(m + 1, numel(years)))).calendarYear == W(years(m)).calendarYear + 1;
    if adjacent
        if per(m).reg(end) == 2
            per(m).stayD = per(m).stayD + (per(m + 1).reg(1) == 2);
            per(m).exitD = per(m).exitD + (per(m + 1).reg(1) ~= 2);
        end
        continue;
    end
    blockReg = [per(b0:m).reg];
    owner = repelem(b0:m, arrayfun(@(x) numel(x.reg), per(b0:m)));
    for state = [2, 3]
        [len, starts] = runLengths(blockReg == state);
        censored = starts == 1 | starts + len - 1 == numel(blockReg);
        for j = 1:numel(len)
            y = owner(starts(j));
            if state == 2
                per(y).Druns(end + 1) = len(j);
                per(y).Dcensored(end + 1) = censored(j);
            else
                per(y).Uruns(end + 1) = len(j);
                per(y).Ucensored(end + 1) = censored(j);
            end
        end
    end
    b0 = m + 1;
end
s = computeFromParts(per, p);
s.etaBar = etaBar;
s.eBar = eBar;
shareP = p.plant.pmax(:) / sum(p.plant.pmax);
shareR = p.station.pRedMax(:) / sum(p.station.pRedMax);
s.PhiP = s.Phi * shareP;
s.deltaDbarP = s.deltaDbar * shareP;
s.deltaUbarR = s.deltaUbar * shareR;
s.Tloop = Tl.mean;

% 自助法置信区间
Bn = p.stats.bootB;
names = {'Phi', 'deltaD', 'deltaU', 'Dmax', 'Umax', 'qhat', 'deltaDbar', 'deltaUbar'};
boot = nan(Bn, numel(names));
bootIdentified = false(Bn, 1);
rs = RandStream('twister', 'Seed', p.seed + 17);
for b = 1:Bn
    if numel(per) >= 2
        pick = randi(rs, numel(per), 1, numel(per));
        sb = computeFromParts(per(pick), p);
    else
        sb = bootOneYear(per, rs, p);
    end
    for m = 1:numel(names)
        boot(b, m) = sb.(names{m});
    end
    bootIdentified(b) = sb.qhatIdentified;
end
s.ci = struct();
for m = 1:numel(names)
    s.ci.(names{m}) = quantileLin(boot(:, m), [0.025, 0.975]);
end
s.bootRaw = array2table(boot, 'VariableNames', names);
s.bootRaw.qhatIdentified = bootIdentified;
if ~all(bootIdentified), s.ci.qhat = [NaN, NaN]; end
end

function s = computeFromParts(per, p)
B = [per.B];
A = [per.A];
reg = [per.reg];
Dr = [per.Druns];
Ur = [per.Uruns];
net = B - A;
s.Phi = mean(B);
s.Bmean = mean(B);
s.Amean = mean(A);
dpos = max(net(reg == 2), 0);
upos = max(-net(reg == 3), 0);
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
s.deltaD = quantileLin(dpos, p.stats.deltaQuantile);
s.deltaDbar = mean(dpos);
s.deltaU = quantileLin(upos, p.stats.deltaQuantile);
s.deltaUbar = mean(upos);
% 事件持续天数为整数：分位数向上取整（保守），使与流体模型的离散时间口径一致
s.Dmax = ceil(quantileLin(Dr, p.stats.dQuantile) - 1e-9);
s.Umax = ceil(quantileLin(Ur, p.stats.dQuantile) - 1e-9);
s.meanD = mean(Dr);
s.qStayCount = sum([per.stayD]);
s.qExitCount = sum([per.exitD]);
s.qTransitionCount = s.qStayCount + s.qExitCount;
s.qhat = s.qStayCount / max(s.qTransitionCount, 1);
s.qhatIdentified = s.qTransitionCount > 0;
s.finiteGeometricMeanIdentified = s.qExitCount > 0;
s.nCensoredD = sum([per.Dcensored]);
s.nCensoredU = sum([per.Ucensored]);
s.eventEstimator = 'observed contiguous calendar-year events; censored endpoints retained as lower bounds';
s.tailEstimator = 'D-to-D / observed D-origin transitions; no artificial endpoint exits';
s.bootstrapEventUnit = 'whole observed event assigned to its original starting year';
s.Druns = Dr;
s.Uruns = Ur;
s.nDays = numel(B);
end

function sb = bootOneYear(per, rs, p)
% 单个训练年：低风光日、富余日、事件长度分别 iid 重抽样
B = per.B;
A = per.A;
reg = per.reg;
n = numel(B);
pick = randi(rs, n, 1, n);
part.B = B(pick);
part.A = A(pick);
part.reg = reg(pick);
Dr = per.Druns;
Ur = per.Uruns;
if isempty(Dr)
    Dr = 1;
end
if isempty(Ur)
    Ur = 1;
end
part.Druns = Dr(randi(rs, numel(Dr), 1, numel(Dr)));
part.Uruns = Ur(randi(rs, numel(Ur), 1, numel(Ur)));
transitions = [true(1, per.stayD), false(1, per.exitD)];
if isempty(transitions)
    part.stayD = 0;
    part.exitD = 0;
else
    sampled = transitions(randi(rs, numel(transitions), 1, numel(transitions)));
    part.stayD = nnz(sampled);
    part.exitD = nnz(~sampled);
end
part.Dcensored = per.Dcensored;
part.Ucensored = per.Ucensored;
sb = computeFromParts(part, p);
end
