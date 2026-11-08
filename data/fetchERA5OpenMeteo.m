function H = fetchERA5OpenMeteo(site, years, opt)
%FETCHERA5OPENMETEO 从 Open-Meteo 历史天气接口下载 ERA5 逐时再分析数据（在使用者电脑上运行，需联网）。
%   H = fetchERA5OpenMeteo(site, years, opt)
%   site  结构体：name（英文短名，用作文件名）、lat、lon（度）。
%   years 年份向量（日历年）。
%   opt   结构体（缺省见下）：
%     url       接口地址，缺省 'https://archive-api.open-meteo.com/v1/archive'
%     vars      逐时变量名元胞，缺省 {'wind_speed_100m','temperature_2m','surface_pressure',
%               'shortwave_radiation','direct_radiation','diffuse_radiation'}
%     model     再分析模型，缺省 'era5'（固定为 ERA5，避免 best_match 在近年混用其他模型导致序列不一致）
%     timezone  缺省 'Asia/Shanghai'（返回北京时间，逐日汇总按当地日界）
%     rawDir    原始数据缓存目录（每站每年一个 .mat）
%     pause     两次请求之间的间隔（s），缺省 2
%     maxRetry  每次请求的最大重试次数，缺省 6（遇到限流 HTTP 429 时至少等待 60 s）
%     waits     可选，第 a 次失败后的等待时间（s）向量（超出长度取最后一个）；为空时按 pause·2^a 指数退避
%     apikey    可选，Open-Meteo 商业接口密钥；非空时改用 customer-archive-api 并附加 apikey 参数（不受免费限额约束）
%   输出 H：1×numel(years) 元胞，每个元素为 table，列 time（datetime，北京时间）与各变量（double，缺测已线性插值）。
%
%   每个站点每年一次请求，结果先写临时文件再改名为 rawDir/<name>_<year>.mat；缓存核对坐标、年份、模型、
%   时区、接口和单位。旧缓存缺少这些元数据时重新下载，以保证数据与当前请求一致。
%   单位：wind_speed_100m 为 m/s（请求中指定 wind_speed_unit=ms，接口缺省为 km/h）、temperature_2m 为 °C、
%   surface_pressure 为 hPa、辐射为 W/m²（前一小时平均，见 era5ToDaily 的时间对齐说明）。
%   数据来源与许可：ERA5（Hersbach et al., 2020, Q. J. R. Meteorol. Soc. 146:1999–2049，0.25°，1940 年至今），
%   经 Open-Meteo 历史天气接口提供（https://open-meteo.com/en/docs/historical-weather-api，CC BY 4.0，
%   非商业用途免费、无需密钥）；论文数据部分须同时注明二者。

if nargin < 3
    opt = struct();
end
opt = setDefault(opt, 'url', 'https://archive-api.open-meteo.com/v1/archive');
opt = setDefault(opt, 'vars', {'wind_speed_100m', 'temperature_2m', 'surface_pressure', 'shortwave_radiation', ...
    'direct_radiation', 'diffuse_radiation'});
opt = setDefault(opt, 'model', 'era5');
opt = setDefault(opt, 'timezone', 'Asia/Shanghai');
opt = setDefault(opt, 'rawDir', fullfile(pwd, 'era5_raw'));
opt = setDefault(opt, 'pause', 2);
opt = setDefault(opt, 'maxRetry', 6);
opt = setDefault(opt, 'waits', []);
opt = setDefault(opt, 'apikey', '');
if ~exist(opt.rawDir, 'dir')
    mkdir(opt.rawDir);
end
H = cell(1, numel(years));
wopt = weboptions('ContentType', 'text', 'Timeout', 180);
for k = 1:numel(years)
    y = years(k);
    f = fullfile(opt.rawDir, sprintf('%s_%d.mat', site.name, y));
    cacheMeta = struct('schema',1,'lat',site.lat,'lon',site.lon,'year',y, ...
        'model',char(opt.model),'timezone',char(opt.timezone),'url',char(opt.url),'windSpeedUnit','ms');
    if isfile(f)
        try
            L = load(f);
            if isfield(L,'cacheMeta') && isequaln(L.cacheMeta,cacheMeta) && ...
                    all(ismember(opt.vars, L.T.Properties.VariableNames))
                H{k} = L.T;
                continue;
            end
        catch
            % 文件损坏、元数据不匹配或变量不全：重新下载
        end
    end
    url = sprintf(['%s?latitude=%.4f&longitude=%.4f&start_date=%d-01-01&end_date=%d-12-31&hourly=%s', ...
        '&models=%s&timezone=%s&wind_speed_unit=ms'], opt.url, site.lat, site.lon, y, y, ...
        strjoin(opt.vars, ','), opt.model, strrep(opt.timezone, '/', '%2F'));
    if ~isempty(opt.apikey)
        url = [strrep(url, '://archive-api.', '://customer-archive-api.'), '&apikey=', char(opt.apikey)];
    end
    txt = '';
    for a = 1:opt.maxRetry
        try
            txt = webread(url, wopt);
            break;
        catch err
            if a == opt.maxRetry
                error('fetchERA5OpenMeteo:http', '下载失败（站点 %s，%d 年，已重试 %d 次）：%s', site.name, y, a, ...
                    err.message);
            end
            wt = opt.pause * 2 ^ a;
            if contains(err.message, '429')
                wt = max(wt, 60);
            end
            if ~isempty(opt.waits)
                wt = opt.waits(min(a, numel(opt.waits)));
            end
            fprintf('  下载 %s %d 年失败（%s），%.0f s 后重试（%d/%d）。\n', site.name, y, err.message, wt, a, ...
                opt.maxRetry);
            pause(wt);
        end
    end
    J = jsondecode(txt);
    if ~isfield(J, 'hourly')
        error('fetchERA5OpenMeteo:format', '接口返回内容缺少 hourly 字段（站点 %s，%d 年）。', site.name, y);
    end
    T = parseHourly(J.hourly, opt.vars, site.name, y);
    tmp = fullfile(opt.rawDir, sprintf('%s_%d.tmp.mat', site.name, y));
    save(tmp, 'T', 'cacheMeta');
    movefile(tmp, f, 'f');
    H{k} = T;
    fprintf('  已下载 %s %d 年（%d 小时）。\n', site.name, y, height(T));
    pause(opt.pause);
end
end

function T = parseHourly(h, vars, name, y)
% 逐时字段转为 table；JSON 中的 null 转为 NaN，缺测比例超过 1% 时报错，否则线性插值补齐
t = datetime(h.time, 'InputFormat', 'yyyy-MM-dd''T''HH:mm');
T = table(t(:), 'VariableNames', {'time'});
for m = 1:numel(vars)
    fn = vars{m};
    if ~isfield(h, fn) && isfield(h, [fn, '_era5'])
        fn = [fn, '_era5'];                          % 指定模型时个别接口版本会给变量名加模型后缀
    end
    if ~isfield(h, fn)
        error('fetchERA5OpenMeteo:var', '接口返回内容缺少变量 %s（站点 %s，%d 年）。', vars{m}, name, y);
    end
    v = h.(fn);
    if iscell(v)
        e = cellfun(@isempty, v);
        v(e) = {NaN};
        v = cell2mat(v);
    end
    v = double(v(:));
    miss = isnan(v);
    if mean(miss) > 0.01
        error('fetchERA5OpenMeteo:missing', '变量 %s 缺测比例 %.1f%% 超过 1%%（站点 %s，%d 年）。', vars{m}, ...
            100 * mean(miss), name, y);
    end
    if any(miss)
        v = fillmissing(v, 'linear', 'EndValues', 'nearest');
    end
    T.(vars{m}) = v;
end
end

function s = setDefault(s, f, v)
if ~isfield(s, f) || isempty(s.(f))
    s.(f) = v;
end
end
