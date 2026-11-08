function rep = downloadWeather(p, n, opts)
%DOWNLOADWEATHER 下载区域算例与全国评估所需的 ERA5 逐时数据（经 Open-Meteo 历史天气接口）。
%   rep = downloadWeather(p, n)，p = params_paper()，n = params_national()；n 为空时只下载区域数据。
%   每个站点每年一次请求，原始数据缓存为 <rawDir>/<站点>_<年>.mat，已下载且元数据一致的站点年直接跳过，
%   因此中断或达到免费接口每日限额后重新运行即可续传。
%   区域数据（还原侧风光站点与负荷站点，含尾部年）必须全部下载完成，否则报错；
%   全国数据按“校正年优先、再逐年”的顺序下载，达到接口限额时停止并在 rep 中记录缺失数量，
%   全国评估在已齐全的年份上进行，后续运行继续补齐。
%   opts.national 为 false 时跳过全国数据。
%   输出 rep：regionalFiles、nationalFiles、nationalMissing、nationalComplete。

if nargin < 2
    n = [];
end
if nargin < 3
    opts = struct();
end
rep = struct('regionalFiles', 0, 'nationalFiles', 0, 'nationalMissing', 0, 'nationalComplete', true);

% ---------- 区域算例 ----------
e = p.weather.era5;
allY = [e.years(:)', e.tailYear];
fo = struct('vars', {e.vars}, 'rawDir', fullfile(e.dataDir, 'raw'), 'pause', e.pause, 'model', e.model, ...
    'timezone', e.timezone, 'url', e.url);
fprintf('区域 ERA5：还原侧站点 %d 个、负荷站点 %d 个，%d—%d 年。\n', numel(e.reSites), numel(e.loadSites), ...
    allY(1), allY(end));
for k = 1:numel(e.reSites)
    fetchERA5OpenMeteo(e.reSites(k), allY, fo);
    rep.regionalFiles = rep.regionalFiles + numel(allY);
end
if isempty(e.loadFile)
    foT = fo;
    foT.vars = {'temperature_2m'};
    for k = 1:numel(e.loadSites)
        fetchERA5OpenMeteo(e.loadSites(k), allY, foT);
        rep.regionalFiles = rep.regionalFiles + numel(allY);
    end
end
fprintf('区域 ERA5 已齐全（%d 个站点年）。\n', rep.regionalFiles);

% ---------- 全国评估 ----------
if isempty(n) || ~getf(opts, 'national', true)
    return;
end
N = natLoadInputs(n);
en = n.era5;
[keys, ia] = unique(N.pts.key, 'stable');
yrs = [en.windCalYear, setdiff(en.years(:)', en.windCalYear, 'stable')];
fon = struct('vars', {en.vars}, 'rawDir', en.rawDir, 'pause', en.pause, 'model', en.model, 'timezone', en.timezone, ...
    'url', en.url, 'waits', en.waits, 'maxRetry', en.maxRetry, 'apikey', en.apikey);
if ~exist(en.rawDir, 'dir')
    mkdir(en.rawDir);
end
have = false(numel(keys), numel(yrs));
for m = 1:numel(yrs)
    for k = 1:numel(keys)
        have(k, m) = isfile(fullfile(en.rawDir, sprintf('%s_%d.mat', keys(k), yrs(m))));
    end
end
fprintf('全国 ERA5：%d 个代表点 × %d 年，已有 %d 个点年，待下载 %d 个。\n', numel(keys), numel(yrs), nnz(have), ...
    nnz(~have));
nFail = 0;
for m = 1:numel(yrs)
    for k = 1:numel(keys)
        if have(k, m)
            continue;
        end
        site = struct('name', keys(k), 'lat', N.pts.lat(ia(k)), 'lon', N.pts.lon(ia(k)));
        try
            fetchERA5OpenMeteo(site, yrs(m), fon);
            have(k, m) = true;
            nFail = 0;
        catch err
            nFail = nFail + 1;
            fprintf('  跳过 %s %d 年（%s），继续下载其余代表点。\n', site.name, yrs(m), err.message);
            if nFail >= getf(en, 'maxConsecutiveFail', 4)
                fprintf(['全国 ERA5 连续 %d 个点年下载失败，网络或接口暂时不可用，下载暂停；', ...
                    '已下载 %d 个点年，缺 %d 个。稍后重新运行 main 即可续传。\n'], nFail, nnz(have), nnz(~have));
                rep.nationalFiles = nnz(have);
                rep.nationalMissing = nnz(~have);
                rep.nationalComplete = false;
                return;
            end
        end
    end
end
rep.nationalFiles = nnz(have);
rep.nationalMissing = nnz(~have);
rep.nationalComplete = all(have(:));
if rep.nationalComplete
    fprintf('全国 ERA5 已齐全（%d 个点年）。\n', rep.nationalFiles);
else
    fprintf('全国 ERA5 本轮结束：已有 %d 个点年，仍缺 %d 个（个别点年失败已跳过），重新运行 main 即可补齐。\n', ...
        rep.nationalFiles, rep.nationalMissing);
end
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = d;
end
end
