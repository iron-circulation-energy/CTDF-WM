function Cl = natClimate(N, n)
%NATCLIMATE 各省风光日容量因子与日负荷指数（ERA5 逐时再分析，经 Open-Meteo 下载；在使用者电脑上运行）。
%   Cl = natClimate(N, n)，N 为 natLoadInputs 的输出，n 为 params_national()。
%   下载：每个风光代表点（相同坐标只下载一次）每年一次请求，原始数据缓存在 n.era5.rawDir（文件名为坐标），
%   中断或达到接口限额后重新运行只下载缺失部分。下载顺序为“年份优先”：先下载校正年（2019）全部点，再逐年下载，
%   因此即使只完成部分年份，也能用已齐全的年份先行评估（至少 n.era5.minYears 年）。
%   转换（与浩吉算例相同的 era5ToHourly、windCF）：
%     风电  省内各风电代表点的逐时容量因子按点权重加权，偏差校正系数 α_i（全省统一）使校正年平均容量因子等于
%           2019 年该省风电利用小时数 /(1 − 弃风率)/8760（curtailAdjust = false 时不除以 1 − 弃风率）；
%     光伏  固定倾角模型，不做偏差校正（省级光伏利用小时数无完整官方统计）；
%     负荷  光伏代表点日平均气温的温度响应指数（n.load），按全部评估年份归一化为均值 1；mode = 'flat' 时为常数 1。
%   输出 Cl：years（升序）、cfW、cfS、load、Tday（nP×Y×365）、alpha、target、hoursRaw（未校正校正年风电小时数）、
%            windHours、pvHours（评估年份平均）、complete（是否全部配置年份齐全）、clipped（校正是否未达目标）。
%   若目标在 alpha∈[0.3,3] 内不可达（山地省份 ERA5 100 m 风速偏低），不采用边界系数，而改用未校正风速（alpha = 1）
%   的容量因子按比例 s = 目标/原始平均值放大并截断于 1，记 Cl.clipped(i) = true、Cl.cfScale(i) = s，并给出警告；
%   其余省份 Cl.cfScale = 1。

e = n.era5;
if ~exist(e.rawDir, 'dir')
    mkdir(e.rawDir);
end
pts = N.pts;
[keys, ia] = unique(pts.key, 'stable');
nK = numel(keys);
yrs = [e.windCalYear, setdiff(e.years(:)', e.windCalYear, 'stable')];
fo = struct('vars', {e.vars}, 'rawDir', e.rawDir, 'pause', e.pause, 'model', e.model, 'timezone', e.timezone, ...
    'url', e.url, 'waits', e.waits, 'maxRetry', e.maxRetry, 'apikey', e.apikey);
have = false(nK, numel(yrs));
for m = 1:numel(yrs)
    for k = 1:nK
        have(k, m) = isfile(fullfile(e.rawDir, sprintf('%s_%d.mat', keys(k), yrs(m))));
    end
end
nMiss = nnz(~have);
if nMiss > 0
    fprintf(['ERA5 下载：%d 个代表点 × %d 年，缺 %d 个点年。免费接口每日约可下载 250~380 个点年，', ...
        '预计需要 %.1f~%.1f 天（可多次运行续传；已下载部分缓存在 %s）。\n'], nK, numel(yrs), nMiss, nMiss / 380, ...
        nMiss / 250, e.rawDir);
end
stopped = false;
nFail = 0;
maxFail = 4;
if isfield(e, 'maxConsecutiveFail') && ~isempty(e.maxConsecutiveFail)
    maxFail = e.maxConsecutiveFail;
end
for m = 1:numel(yrs)
    for k = 1:nK
        if have(k, m)
            continue;
        end
        site = struct('name', keys(k), 'lat', pts.lat(ia(k)), 'lon', pts.lon(ia(k)));
        try
            fetchERA5OpenMeteo(site, yrs(m), fo);
            have(k, m) = true;
            nFail = 0;
        catch err
            nFail = nFail + 1;
            fprintf('  跳过 %s %d 年（%s）。\n', site.name, yrs(m), err.message);
            if nFail >= maxFail
                warning('natClimate:download', ['连续 %d 个点年下载失败，下载暂停。已下载的数据保留，稍后重新运行 main ', ...
                    '即可续传；本次先用已齐全的年份评估。'], nFail);
                stopped = true;
                break;
            end
        end
    end
    if stopped
        break;
    end
end
okY = all(have, 1);
if ~okY(1)
    error('natClimate:calYear', '校正年 %d 尚未下载齐全，无法进行偏差校正；请稍后重新运行续传。', yrs(1));
end
yOK = sort(yrs(okY));
if numel(yOK) < e.minYears
    error('natClimate:years', '只有 %d 个年份数据齐全（至少需要 %d 个），请稍后重新运行续传。', numel(yOK), e.minYears);
end
Y = numel(yOK);
cal = find(yOK == e.windCalYear, 1);

% 逐点转换（每个点只转换一次）
U = cell(nK, 1);
PV = cell(nK, 1);
TT = cell(nK, 1);
for k = 1:nK
    site = struct('name', keys(k), 'lat', pts.lat(ia(k)), 'lon', pts.lon(ia(k)));
    H = fetchERA5OpenMeteo(site, yOK, fo);           % 全部已缓存，只读取
    U{k} = zeros(24, 365, Y);
    PV{k} = zeros(24, 365, Y);
    TT{k} = zeros(Y, 365);
    for m = 1:Y
        o = era5ToHourly(H{m}, site, 'wind', e);
        U{k}(:, :, m) = o.U;
        o = era5ToHourly(H{m}, site, 'pv', e);
        PV{k}(:, :, m) = o.CF;
        o = era5ToHourly(H{m}, site, 'temp', e);
        TT{k}(m, :) = o.Tday;
    end
end
[~, kOf] = ismember(pts.key, keys);

nP = height(N.prov);
Cl.years = yOK;
Cl.cfW = zeros(nP, Y, 365);
Cl.cfS = zeros(nP, Y, 365);
Cl.Tday = zeros(nP, Y, 365);
Cl.load = ones(nP, Y, 365);
Cl.alpha = ones(nP, 1);
Cl.target = zeros(nP, 1);
Cl.hoursRaw = zeros(nP, 1);
Cl.clipped = false(nP, 1);
Cl.cfScale = ones(nP, 1);
for i = 1:nP
    kw = find(pts.provIdx == i & pts.kind == "wind");
    ks = find(pts.provIdx == i & pts.kind == "pv");
    ww = pts.weight(kw) / sum(pts.weight(kw));
    ws = pts.weight(ks) / sum(pts.weight(ks));
    % 风电偏差校正
    tgt = N.prov.windHours(i);
    if e.curtailAdjust
        tgt = tgt / (1 - N.prov.windCurt(i) / 100);
    end
    Cl.target(i) = tgt;
    f = @(a) windMix(U, kOf(kw), ww, a, cal, e);
    Cl.hoursRaw(i) = 8760 * mean(reshape(f(1), [], 1));
    uw = cell(numel(kw),1); wwHourly = uw;
    for j = 1:numel(kw)
        uk = U{kOf(kw(j))}(:,:,cal);
        uw{j} = uk(:); wwHourly{j} = repmat(ww(j)/numel(uk),numel(uk),1);
    end
    [Cl.alpha(i),matched] = calibrateWindAlpha(vertcat(uw{:}),tgt/8760,e,vertcat(wwHourly{:}));
    if ~matched && isfield(e, 'windDonor')
        % 借用相邻省份的风电代表点
        jd = find(strcmp(string(e.windDonor.prov), string(N.prov.name(i))), 1);
        if ~isempty(jd)
            iDon = find(strcmp(string(N.prov.name), string(e.windDonor.donor{jd})), 1);
            kd = find(pts.provIdx == iDon & pts.kind == "wind");
            if ~isempty(kd)
                kw = kd;
                ww = pts.weight(kw) / sum(pts.weight(kw));
                uw = cell(numel(kw),1); wwHourly = uw;
                for j = 1:numel(kw)
                    uk = U{kOf(kw(j))}(:,:,cal);
                    uw{j} = uk(:); wwHourly{j} = repmat(ww(j)/numel(uk),numel(uk),1);
                end
                [Cl.alpha(i),matched] = calibrateWindAlpha(vertcat(uw{:}),tgt/8760,e,vertcat(wwHourly{:}));
                fprintf('%s：本省风电代表点校正不可达，借用%s的风电代表点，校正系数 %.2f（%s）。\n', char(string(N.prov.name(i))), ...
                    e.windDonor.donor{jd}, Cl.alpha(i), string(matched));
            end
        end
    end
    Cl.clipped(i) = ~matched;
    if ~matched
        Cl.alpha(i) = 1;
        raw = Cl.hoursRaw(i) / 8760;
        Cl.cfScale(i) = tgt / 8760 / max(raw, eps);
        warning('natClimate:alpha', ['%s：目标风电利用小时数 %.0f h 在 alpha∈[0.3,3] 内不可达（未校正 %.0f h），', ...
            '改用未校正容量因子按 %.2f 倍比例放大并截断于 1。'], N.prov.name(i), tgt, Cl.hoursRaw(i), Cl.cfScale(i));
    end
    cw = zeros(24, 365, Y);
    for j = 1:numel(kw)
        cw = cw + ww(j) * windCF(Cl.alpha(i) * U{kOf(kw(j))}, e);
    end
    if Cl.cfScale(i) ~= 1
        cw = min(1, Cl.cfScale(i) * cw);
    end
    cs = zeros(24, 365, Y);
    td = zeros(Y, 365);
    for j = 1:numel(ks)
        cs = cs + ws(j) * PV{kOf(ks(j))};
        td = td + ws(j) * TT{kOf(ks(j))};
    end
    Cl.cfW(i, :, :) = reshape(squeeze(mean(cw, 1))', 1, Y, 365);
    Cl.cfS(i, :, :) = reshape(squeeze(mean(cs, 1))', 1, Y, 365);
    Cl.Tday(i, :, :) = reshape(td, 1, Y, 365);
    if strcmpi(n.load.mode, 'temp')
        l = 1 + n.load.coolCoef * max(td - n.load.coolBase, 0) + n.load.heatCoef * max(n.load.heatBase - td, 0);
        Cl.load(i, :, :) = reshape(l / mean(l(:)), 1, Y, 365);
    end
end
Cl.windHours = 8760 * mean(reshape(Cl.cfW, nP, []), 2);
Cl.pvHours = 8760 * mean(reshape(Cl.cfS, nP, []), 2);
Cl.complete = all(okY) && Y == numel(e.years);
if ~exist(n.outDir, 'dir')
    mkdir(n.outDir);
end
save(fullfile(n.outDir, 'climate.mat'), 'Cl');
fprintf('ERA5 省级容量因子：%d—%d 年（%d 年%s）；风电 α 中位数 %.2f，范围 %.2f~%.2f。\n', yOK(1), yOK(end), Y, ...
    ternary(Cl.complete, '，全部齐全', '，下载未完成，结果为初步结果'), median(Cl.alpha), min(Cl.alpha), max(Cl.alpha));
end

function c = windMix(U, kIdx, w, a, m, e)
% 省内风电代表点加权的逐时容量因子（第 m 年，24×365）
c = zeros(24, 365);
for j = 1:numel(kIdx)
    c = c + w(j) * windCF(a * U{kIdx(j)}(:, :, m), e);
end
end

function s = ternary(c, a, b)
if c
    s = a;
else
    s = b;
end
end
