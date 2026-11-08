function [p, rep] = prepareRealData(p)
%PREPAREREALDATA 实测气象数据准备（浩吉算例）：ERA5 逐时再分析 → 风光容量因子与负荷指数 → 偏差校正
%   → 日尺度 CSV（readWeatherCSV 格式）→ 用训练年份估计气象过程参数并写回 p.weather。
%   [p, rep] = prepareRealData(p)，配置见 p.weather.era5（params_default 的 haoji 算例）。
%
%   流程：
%   1 下载：fetchERA5OpenMeteo 按站点、年份下载（首次运行需联网，约 (还原侧站点 + 负荷站点) × 年数 次请求；
%     原始数据缓存在 era5.dataDir/raw/，再次运行或中断后重跑只下载缺失年份）。年份为 era5.years 与尾部年
%     era5.tailYear（尾部年只作为最后一个模型年的前瞻尾部，不进入训练、验证或测试）。
%   2 风电：等效风速 U（密度修正，era5ToHourly）→ 通用功率曲线 windCF；偏差校正系数 α_k 使站点 k 在校正年
%     era5.windCalYear 的年平均容量因子等于其所在省区官方风电利用小时数/8760（era5.windTarget），
%     α 对全部年份统一使用（只用一个年度统计量，不使用测试年份数据）；windBiasCorrect = false 时 α = 1。
%   3 光伏：era5ToHourly 的固定倾角模型；era5.pvTarget 为有限值时同样按校正年做比例校正，否则不校正。
%   4 多站点按 windWeight、pvWeight 加权得到系统容量因子；日电量 E = cap·24·日平均容量因子。
%   5 负荷：负荷站点日平均气温按 loadWeight 加权，指数 l = 1 + aC·max(T − TC, 0) + aH·max(TH − T, 0)，
%     再除以训练年份均值（年均负荷 = p.load.mean）；era5.loadFile 非空时改用该文件（列 year, day, load）。
%   6 规模：rescaleCap 为真时按“训练年平均风光电量与合成算例相同”换算风光装机（保持原规模校准的能量平衡），
%     换算系数写入 rep。
%   7 写出 CSV 与报告（dataDir/haoji_daily.csv、era5_report.csv、fit_report.mat，后者含训练年月份 × 时刻平均容量因子
%     monthHourW、monthHourS，供图 F02 使用），并调用 fitWeatherModel。
%   全部计算由缓存的原始数据确定性地得到，同一参数重复调用结果一致（断点续跑的参数核对据此通过）。

e = p.weather.era5;
w0 = p.weather;
rawDir = fullfile(e.dataDir, 'raw');
if ~exist(e.dataDir, 'dir')
    mkdir(e.dataDir);
end
yrs = e.years(:)';
allY = [yrs, e.tailYear];
nA = numel(allY);
Y = numel(yrs);
tr = w0.train;
cal = find(allY == e.windCalYear, 1);
fo = struct('vars', {e.vars}, 'rawDir', rawDir, 'pause', e.pause, 'model', e.model, 'timezone', e.timezone, ...
    'url', e.url);
fprintf('准备 ERA5 数据：还原侧站点 %d 个、负荷站点 %d 个、%d—%d 年（首次运行需下载）。\n', numel(e.reSites), ...
    numel(e.loadSites), allY(1), allY(end));

% 风光
nS = numel(e.reSites);
cfWh = zeros(24, 365, nA);
cfSh = zeros(24, 365, nA);
alpha = ones(1, nS);
pvScale = ones(1, nS);
siteHours = zeros(nS, 2);
for k = 1:nS
    s = e.reSites(k);
    H = fetchERA5OpenMeteo(s, allY, fo);
    U = zeros(24, 365, nA);
    S = zeros(24, 365, nA);
    for m = 1:nA
        o1 = era5ToHourly(H{m}, s, 'wind', e);
        o2 = era5ToHourly(H{m}, s, 'pv', e);
        U(:, :, m) = o1.U;
        S(:, :, m) = o2.CF;
    end
    if e.windBiasCorrect
        if isempty(cal)
            error('prepareRealData:cal', '校正年 %d 不在下载年份内。', e.windCalYear);
        end
        alpha(k) = calibrateAlpha(U(:, :, cal), s.windTarget / 8760, e);
    end
    tgtS = s.pvTarget;
    if isfinite(tgtS)
        pvScale(k) = tgtS / 8760 / max(mean(reshape(S(:, :, cal), [], 1)), eps);
    end
    Wk = windCF(alpha(k) * U, e);
    Sk = min(1, pvScale(k) * S);
    siteHours(k, :) = [mean(Wk(:)), mean(Sk(:))] * 8760;
    cfWh = cfWh + s.windWeight * Wk;
    cfSh = cfSh + s.pvWeight * Sk;
end
sw = sum([e.reSites.windWeight]);
ss = sum([e.reSites.pvWeight]);
cfWh = cfWh / sw;
cfSh = cfSh / ss;
cfWd = squeeze(mean(cfWh, 1))';          % nA×365
cfSd = squeeze(mean(cfSh, 1))';

% 负荷
if ~isempty(e.loadFile)
    L = readtable(e.loadFile);
    lraw = zeros(nA, 365);
    for m = 1:nA
        v = L.load(L.year == allY(m));
        if numel(v) < 365
            error('prepareRealData:load', '负荷文件中 %d 年不足 365 天。', allY(m));
        end
        lraw(m, :) = v(1:365);
    end
else
    Tm = zeros(nA, 365);
    wl = [e.loadSites.weight];
    foT = fo;
    foT.vars = {'temperature_2m'};               % 负荷站点只需气温
    for k = 1:numel(e.loadSites)
        s = e.loadSites(k);
        H = fetchERA5OpenMeteo(s, allY, foT);
        for m = 1:nA
            o = era5ToHourly(H{m}, s, 'temp', e);
            Tm(m, :) = Tm(m, :) + wl(k) / sum(wl) * o.Tday;
        end
    end
    lraw = 1 + e.loadCoolCoef * max(Tm - e.loadCoolBase, 0) + e.loadHeatCoef * max(e.loadHeatBase - Tm, 0);
end
lidx = lraw / mean(reshape(lraw(tr, :), [], 1));

% 规模换算（保持训练年平均风光电量与合成算例相同）
kW = 1;
kS = 1;
if e.rescaleCap
    mW0 = synthMeanCF(w0, 'W');
    mS0 = synthMeanCF(w0, 'S');
    kW = mW0 / mean(reshape(cfWd(tr, :), [], 1));
    kS = mS0 / mean(reshape(cfSd(tr, :), [], 1));
    p.re.capW = round(p.re.capW * kW / 10) * 10;
    p.re.capS = round(p.re.capS * kS / 10) * 10;
end

% 日电量与 CSV
EWa = p.re.capW * 24 * cfWd;
ESa = p.re.capS * 24 * cfSd;
ELa = p.load.mean * 24 * lidx;
csvFile = fullfile(e.dataDir, 'haoji_daily.csv');
yy = repmat(allY(:), 1, 365)';
dd = repmat((1:365)', 1, nA);
T = table(yy(:), dd(:), reshape(EWa', [], 1), reshape(ESa', [], 1), reshape(ELa', [], 1), ...
    'VariableNames', {'year', 'day', 'EW', 'ES', 'EL'});
writetable(T, csvFile, 'Encoding', 'UTF-8');

% 逐时统计（日内形状）
hs.windProfile = mean(reshape(cfWh(:, :, tr), 24, []), 2);
[hs.dayLen, hs.noon] = pvSpread(cfSh(:, :, 1:Y));

% 写回参数并估计气象过程
p.weather.source = 'csv';
p.weather.csvFile = csvFile;
p.weather.csvLastIsTail = true;
p.weather.Y = Y;
[p, fit] = fitWeatherModel(p, EWa(1:Y, :), ESa(1:Y, :), ELa(1:Y, :), tr, hs);

% 报告
rep = struct('alpha', alpha, 'pvScale', pvScale, 'siteHours', siteHours, 'capScale', [kW, kS], ...
    'capW', p.re.capW, 'capS', p.re.capS, 'fit', fit, 'years', allY, 'csvFile', csvFile);
% 训练年月份 × 时刻平均容量因子（图 F02）
mo = month(datetime(2001, 1, 1) + caldays(0:364));
rep.monthHourW = zeros(12, 24);
rep.monthHourS = zeros(12, 24);
for q = 1:12
    rep.monthHourW(q, :) = mean(reshape(cfWh(:, mo == q, tr), 24, []), 2)';
    rep.monthHourS(q, :) = mean(reshape(cfSh(:, mo == q, tr), 24, []), 2)';
end
R = table(allY(:), 8760 * mean(cfWd, 2), 8760 * mean(cfSd, 2), mean(lidx, 2), ...
    'VariableNames', {'year', 'windHours', 'pvHours', 'loadIndex'});
writetable(R, fullfile(e.dataDir, 'era5_report.csv'), 'Encoding', 'UTF-8');
save(fullfile(e.dataDir, 'fit_report.mat'), 'rep');
[~, p.weather.provenanceFile] = writeWeatherProvenance(p, rep);
fprintf(['ERA5 数据准备完成：风电偏差校正系数 α = %s；训练年平均利用小时数 风电 %.0f h、光伏 %.0f h；', ...
    '风光装机换算为 %d / %d MW；低风光状态频率 %.3f，平均持续 %.1f d，训练年最长连续 %d d。\n'], ...
    mat2str(alpha, 3), 8760 * fit.meanCfW, 8760 * fit.meanCfS, p.re.capW, p.re.capS, fit.freq(2), ...
    fit.meanLowDays, fit.maxLowRunTrain);
end

function a = calibrateAlpha(U, target, e)
% 切出风速造成非单调性；按切出断点分段找可达根。
[a,matched] = calibrateWindAlpha(U,target,e);
if ~matched
    error('prepareRealData:alpha', '偏差校正无解：目标容量因子 %.3f 超出 α ∈ [0.3, 3] 的可达范围，请检查站点或目标值。', ...
        target);
end
end

function m = synthMeanCF(w, kind)
% 合成气象过程的平均容量因子（平稳分布加权的状态乘子 × 季节均值，忽略截断与 AR 项的二阶效应）
[V, Dg] = eig(w.P');
[~, k] = min(abs(diag(Dg) - 1));
pis = real(V(:, k));
pis = pis / sum(pis);
if kind == 'W'
    m = w.cfW0 * (w.mW(:)' * pis);
else
    m = w.cfS0 * (w.mS(:)' * pis);
end
end

function [dl, noon] = pvSpread(C)
% 逐日光伏有效日照时长与出力重心：以逐时容量因子为权重的时刻均值 μ 与方差 v，
% 对 sin 形状（hourlyProfiles）有 v = dl²·(1/4 − 2/π²)，故 dl = sqrt(v/(1/4 − 2/π²))；日电量过小（< 0.01·24）时记 NaN
t = (1:24)' - 0.5;
Y = size(C, 3);
dl = NaN(Y, 365);
noon = NaN(Y, 365);
for m = 1:Y
    X = C(:, :, m);
    s = sum(X, 1);
    ok = s > 0.24;
    mu = (t' * X(:, ok)) ./ s(ok);
    v = sum(((t - mu) .^ 2) .* X(:, ok), 1) ./ s(ok);
    dl(m, ok) = sqrt(v / (1 / 4 - 2 / pi ^ 2));
    noon(m, ok) = mu;
end
end
