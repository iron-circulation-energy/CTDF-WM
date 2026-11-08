function N = natLoadInputs(n)
%NATLOADINPUTS 读取全国评估输入数据（data/national/*.csv，来源与许可见 README“全国评估数据”）并整理为省级结构。
%   N = natLoadInputs(n)，n 为 params_national()。参与评估的是 31 个省级行政区（港澳台缺少 2019 年省级统计，
%   在地图上照常绘制、标注为未评估）。输出 N：
%     prov     31 行 table：name、short、gb、lon、lat（标注点）、windMW、windHours、windCurt（%）、pvMW、consGWh、
%              reShare、nhShare（%）、phiW（风电容量占比）、hydroShare（水电消纳占比）、saltTier（无盐穴记录为 Inf）、saltSites、
%              gwAll、gwYoung（GW）、nYoung、yearYoung（容量加权平均投运年）、coalLon、coalLat（搁浅风险机组容量加权
%              中心；无此类机组时取全部煤电，仍无则取标注点）、reLon、reLat（风光代表点按 2019 年装机加权的中心）、
%              dLocal（km，省内风光代表点到搁浅风险机组的铁路里程 = 容量加权大圆距离 × 绕行系数，下限 50 km）
%     coal     燃煤电厂 table（GPPD），增加 provIdx（0 为港澳台）与 young（投运年 ≥ n.coal.yearMin）
%     pts      风光代表点 table：provIdx、kind（'wind'/'pv'）、lon、lat、weight（省内同类点权重）、key（缓存文件名）
%     uhv      特高压直流 table：增加 fromIdx、toIdx
%     dHub     31×31 铁路里程（km）：dHub(h, i) 为省 h 风光中心到省 i 煤电中心的大圆距离 × 绕行系数
%     names    31×1 省名（string）

d = n.dataDir;
rd = @(f) readtable(fullfile(d, f), 'Encoding', 'UTF-8', 'TextType', 'string', 'Delimiter', ',');
P = rd('provinces_cn.csv');
P = P(P.assessed == 1, :);
st = rd('prov_stats_2019.csv');
[ok, loc] = ismember(P.prov, st.prov);
if ~all(ok)
    error('natLoadInputs:prov', '省级统计缺少：%s。', strjoin(P.prov(~ok), '、'));
end
st = st(loc, :);
nP = height(P);
T = table(P.prov, P.short, P.gb, P.labelLon, P.labelLat, 'VariableNames', {'name', 'short', 'gb', 'lon', 'lat'});
T.windMW = st.windMW;
T.windHours = st.windHours;
T.windCurt = st.windCurtPct;
T.pvMW = st.pvMW;
T.consGWh = st.consGWh;
T.reShare = st.reSharePct;
T.nhShare = st.nhSharePct;
T.phiW = st.windMW ./ max(st.windMW + st.pvMW, eps);
T.hydroShare = max(0, st.reSharePct - st.nhSharePct) / 100;   % 2019 年水电消纳占比（含区外来水）
names = T.name;

% 盐穴
S = rd('salt_cn.csv');
T.saltTier = inf(nP, 1);
T.saltSites = strings(nP, 1);
[ok, loc] = ismember(S.prov, names);
T.saltTier(loc(ok)) = S.tier(ok);
T.saltSites(loc(ok)) = S.sites(ok);

% 煤电
C = rd('coal_plants_cn.csv');
[~, C.provIdx] = ismember(C.prov, names);
C.young = C.year >= n.coal.yearMin;           % 投运年缺失（NaN）视为非搁浅风险机组
T.gwAll = zeros(nP, 1);
T.gwYoung = zeros(nP, 1);
T.nYoung = zeros(nP, 1);
T.yearYoung = nan(nP, 1);
T.coalLon = T.lon;
T.coalLat = T.lat;
for i = 1:nP
    a = C.provIdx == i;
    y = a & C.young;
    T.gwAll(i) = sum(C.mw(a)) / 1e3;
    T.gwYoung(i) = sum(C.mw(y)) / 1e3;
    T.nYoung(i) = nnz(y);
    if any(y)
        T.yearYoung(i) = sum(C.year(y) .* C.mw(y)) / sum(C.mw(y));
        sel = y;
    else
        sel = a;
    end
    if any(sel)
        [T.coalLon(i), T.coalLat(i)] = wCentroid(C.lon(sel), C.lat(sel), C.mw(sel));
    end
end

% 风光代表点
R = rd('re_points_cn.csv');
[ok, R.provIdx] = ismember(R.prov, names);
if ~all(ok)
    error('natLoadInputs:pts', '风光代表点中有未知省份。');
end
R.key = compose("n%08.3f_%07.3f", R.lon, R.lat);
R.key = replace(R.key, '.', 'p');
T.reLon = T.lon;
T.reLat = T.lat;
T.dLocal = zeros(nP, 1);
for i = 1:nP
    kw = R.provIdx == i & R.kind == "wind";
    ks = R.provIdx == i & R.kind == "pv";
    lon = [R.lon(kw); R.lon(ks)];
    lat = [R.lat(kw); R.lat(ks)];
    w = [R.weight(kw) * T.windMW(i); R.weight(ks) * T.pvMW(i)];
    if sum(w) <= 0
        w = ones(size(w));
    end
    [T.reLon(i), T.reLat(i)] = wCentroid(lon, lat, w);
    sel = C.provIdx == i & C.young;
    if ~any(sel)
        sel = C.provIdx == i;
    end
    if any(sel)
        % 每个风光点到每个电厂的距离，按（风光权重 × 电厂容量）加权平均
        D = natHaversine(lon, lat, C.lon(sel)', C.lat(sel)');
        W = (w / sum(w)) * (C.mw(sel)' / sum(C.mw(sel)));
        T.dLocal(i) = sum(D(:) .* W(:)) * n.rail.detour;
    end
end
T.dLocal = max(T.dLocal, 50);

% 特高压
U = rd('uhv_dc_cn.csv');
[~, U.fromIdx] = ismember(U.fromProv, names);
[~, U.toIdx] = ismember(U.toProv, names);
if any(U.fromIdx == 0 | U.toIdx == 0)
    error('natLoadInputs:uhv', '特高压线路中有未知省份。');
end

N.prov = T;
N.coal = C;
N.pts = R;
N.uhv = U;
N.dHub = natHaversine(T.reLon, T.reLat, T.coalLon', T.coalLat') * n.rail.detour;
N.names = names;
fprintf(['全国评估输入：%d 省；燃煤电厂 %d 座 %.0f GW（其中 %d 年及以后投运 %.0f GW）；风光代表点 %d 个；', ...
    '特高压直流 %d 回；盐穴记录 %d 省。\n'], nP, nnz(C.provIdx > 0), sum(T.gwAll), n.coal.yearMin, ...
    sum(T.gwYoung), height(R), height(U), nnz(isfinite(T.saltTier)));
end

function [lo, la] = wCentroid(lon, lat, w)
% 加权球面中心（三维单位向量加权平均后投回球面）
w = w(:) / sum(w);
x = sum(w .* cosd(lat(:)) .* cosd(lon(:)));
y = sum(w .* cosd(lat(:)) .* sind(lon(:)));
z = sum(w .* sind(lat(:)));
lo = atan2d(y, x);
la = atan2d(z, hypot(x, y));
end
