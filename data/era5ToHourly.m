function out = era5ToHourly(T, site, kind, cfg)
%ERA5TOHOURLY 单站单年 ERA5 逐时数据转为 24×365 的出力或温度矩阵。
%   out = era5ToHourly(T, site, kind, cfg)
%   T     fetchERA5OpenMeteo 返回的一年逐时 table（北京时间）。
%   site  结构体：lat、lon（度）。
%   kind  'wind'：输出 out.U，为空气密度修正后的 100 m 等效风速（m/s），出力由 windCF(α·U, cfg) 计算，
%                 α 为偏差校正系数（见 prepareRealData）；
%         'pv'  ：输出 out.CF，为固定倾角朝南光伏的逐时容量因子（未做偏差校正）；
%         'temp'：输出 out.Tday，为 1×365 日平均 2 m 气温（°C），用于负荷的温度响应。
%   cfg   p.weather.era5（字段见 params_default 的 haoji 算例）。
%
%   日历：闰年删除 2 月 29 日，每年 365 天，与模型日序 doy = 1..365 一致。
%   时间对齐：Open-Meteo 的辐射量为“前一小时平均”，时间戳 s 对应区间 [s − 1, s]；先整体前移一小时，使矩阵第 h 行
%   对应北京时间区间 [h − 1, h]（与 hourlyProfiles 的 t = h − 0.5 一致）。风速、气温、气压为瞬时值，不移位
%   （与区间中点相差 0.5 h，对日电量无影响）。
%   风电：ρ = p_s/(R_d·T)，U = v_100·(ρ/1.225)^(1/3)（等功率密度折算到标准空气密度，功率曲线按标准空气密度给出）。
%   光伏：太阳位置按 Cooper 赤纬与 Spencer 型均时差近似；倾斜面辐照按各向同性天空模型
%         POA = B_h·R_b + D_h·(1 + cos β)/2 + G_h·ρ_g·(1 − cos β)/2，R_b = max(cos θ, 0)/cos Z（太阳高度 < 5° 时取 0）；
%         电池温度 T_c = T_a + POA/800·(NOCT − 20)；CF = PR·POA/1000·(1 + γ·(T_c − 25))，截断到 [0, 1]。

t = T.time;
switch lower(kind)
    case 'wind'
        v = T.wind_speed_100m;
        rho = T.surface_pressure * 100 ./ (287.05 * (T.temperature_2m + 273.15));
        x = v .* (rho / 1.225) .^ (1 / 3);
    case 'pv'
        x = [shiftRad(T.shortwave_radiation), shiftRad(T.direct_radiation), shiftRad(T.diffuse_radiation), ...
            T.temperature_2m];
    case 'temp'
        x = T.temperature_2m;
    otherwise
        error('era5ToHourly:kind', '未知类型 %s。', kind);
end
keep = ~(month(t) == 2 & day(t) == 29);
x = x(keep, :);
if size(x, 1) ~= 8760
    error('era5ToHourly:length', '逐时数据长度 %d（删除 2 月 29 日后应为 8760），请检查下载的年份是否完整。', size(x, 1));
end
switch lower(kind)
    case 'wind'
        out.U = reshape(x, 24, 365);
    case 'temp'
        out.Tday = mean(reshape(x, 24, 365), 1);
    case 'pv'
        G = reshape(x(:, 1), 24, 365);
        B = reshape(x(:, 2), 24, 365);
        D = reshape(x(:, 3), 24, 365);
        Ta = reshape(x(:, 4), 24, 365);
        beta = pvTiltDeg(site.lat, cfg);
        [cosZ, cosTh] = solarGeometry(site.lat, site.lon, beta);
        Rb = zeros(size(cosZ));
        up = cosZ > sind(5);
        Rb(up) = max(cosTh(up), 0) ./ cosZ(up);
        poa = B .* Rb + D * (1 + cosd(beta)) / 2 + G * cfg.pvAlbedo * (1 - cosd(beta)) / 2;
        Tc = Ta + poa / 800 * (cfg.pvNOCT - 20);
        out.CF = min(1, max(0, cfg.pvPR * poa / 1000 .* (1 + cfg.pvGamma * (Tc - 25))));
end
end

function beta = pvTiltDeg(lat, cfg)
% 固定倾角（°）：cfg.pvTilt 为数值时直接使用；为 NaN 时取 Jacobson & Jadhav (2018, Solar Energy 169:55–66) 北半球
% 最佳倾角拟合式 β = 1.3793 + φ·(1.2011 + φ·(−0.014404 + φ·0.000080509))（[待核实] 系数请对照原文）
if isfinite(cfg.pvTilt)
    beta = cfg.pvTilt;
else
    beta = 1.3793 + lat * (1.2011 + lat * (-0.014404 + lat * 0.000080509));
end
end

function v = shiftRad(v)
% 前一小时平均量前移一小时：v(k) 改为区间 [s_k, s_k + 1] 的平均（年末最后一小时为夜间，取原值）
v = [v(2:end); v(end)];
end

function [cosZ, cosTh] = solarGeometry(lat, lon, beta)
% 24×365 的太阳天顶角余弦与朝南倾斜面入射角余弦（北京时间区间中点 h − 0.5，东八区标准经线 120°E）
h = (1:24)' - 0.5;
n = 1:365;
dec = 23.45 * sind(360 * (284 + n) / 365);                   % 赤纬（Cooper）
Bd = 360 * (n - 81) / 364;
eot = 9.87 * sind(2 * Bd) - 7.53 * cosd(Bd) - 1.5 * sind(Bd);  % 均时差（min）
ts = h + (lon - 120) / 15 + eot / 60;                        % 真太阳时（h），24×365
w = 15 * (ts - 12);                                          % 时角（°）
cosZ = sind(lat) * sind(dec) + cosd(lat) * cosd(dec) .* cosd(w);
cosTh = sind(lat - beta) * sind(dec) + cosd(lat - beta) * cosd(dec) .* cosd(w);
end
