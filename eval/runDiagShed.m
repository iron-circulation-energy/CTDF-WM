function dg = runDiagShed(C, ref, years, seed, epDir)
%RUNDIAGSHED 失负荷来源核实：容量不足导致的失负荷下界与实际失负荷对照（不训练、不改模型参数）。
%   对每个年份（常规工况、名义循环质量、评估窗口）：
%     loadMWh      负荷电量
%     deficitMWh   负荷超出风光的缺口 Σ max(0, D − RE)
%     capShedMWh   容量下界 Σ max(0, D − RE − P_backup − ΣP_plant)：即使铁粉无限、调度完美也无法避免的失负荷
%     shedM0MWh    M0 实际失负荷
%   并给出 capShed / shedM0（容量下界所占份额）与失负荷占负荷的比例，以及峰值缺口与可调容量。

p = C.p;
ctx = C.ctx;
W = C.W;
c = C.cNominal;
specs = makeEvalSpecs(p, years, seed, {'normal'}, c);
[Rk, T] = evalEpisodes(ctx, W, specs, makeController('fixed', 'M0', ref.w), [], epDir);
Pp = sum(p.plant.pmax);
Pb = p.backup.pmax;
n = numel(specs);
rows = zeros(n, 8);
sp2 = zeros(n, 7);
for k = 1:n
    sp = specs(k);
    seg = buildEvalSegment(ctx, W, sp);
    ev = (sp.warmup + 1):sp.len;
    [RE, D] = hourlyProfiles(seg.EW(ev), seg.ES(ev), seg.EL(ev), seg.doy(ev), p.weather);
    r = D - RE;
    dv = dailyDerived(RE, D, p);
    sel = T.year == sp.year;
    rows(k, :) = [sp.year, sum(D(:)), sum(max(0, r(:))), sum(dv.capShed), mean(T.shedMWh(sel)), ...
        max(r(:)), sum(dv.must), sum(max(0, -r(:)))];
    % 逐日拆分：失负荷发生在电厂缺铁日的份额、可归因于缺铁的电量、失负荷日的必需电量与风光
    dd = Rk(k).daily;
    sh = double(dd.shed(:));
    ifm = double(dd.ironShortfallMWh(:));
    mustD = dv.must(:);
    nD = min([numel(sh), numel(ifm), numel(mustD)]);
    sh = sh(1:nD); ifm = ifm(1:nD); mustD = mustD(1:nD);
    sp2(k, :) = [sum(sh), sum(sh(ifm > 1e-6)), sum(min(sh, ifm)), nnz(sh > 1e-3), nnz(sh > 1e-3 & ifm <= 1e-6), ...
        sum(mustD(sh > 1e-3)), sum(sh(mustD <= 1e-3))];
end
dg.byYear = array2table(rows, 'VariableNames', {'year', 'loadMWh', 'deficitMWh', 'capShedMWh', 'shedM0MWh', ...
    'peakDeficitMW', 'mustMWh', 'surplusMWh'});
B = dg.byYear;
S2 = sum(sp2, 1);
dg.split = struct('shedOnIronShortDaysPct', 100 * S2(2) / max(S2(1), eps), ...
    'ironAttributablePct', 100 * S2(3) / max(S2(1), eps), 'shedDaysPerYear', S2(4) / n, ...
    'shedDaysWithoutIronShortPerYear', S2(5) / n, 'shedToMustOnShedDaysPct', 100 * S2(1) / max(S2(6), eps), ...
    'shedOnZeroMustDaysPct', 100 * S2(7) / max(S2(1), eps));
dg.summary = struct('years', n, 'plantPmaxMW', Pp, 'backupPmaxMW', Pb, ...
    'meanLoadTWh', mean(B.loadMWh) / 1e6, 'meanShedM0TWh', mean(B.shedM0MWh) / 1e6, ...
    'shedShareOfLoadPct', 100 * mean(B.shedM0MWh) / mean(B.loadMWh), ...
    'capShedShareOfShedPct', 100 * mean(B.capShedMWh) / max(mean(B.shedM0MWh), eps), ...
    'meanPeakDeficitMW', mean(B.peakDeficitMW), 'maxPeakDeficitMW', max(B.peakDeficitMW), ...
    'mustTWh', mean(B.mustMWh) / 1e6, 'surplusTWh', mean(B.surplusMWh) / 1e6);
end
