function d = natHaversine(lon1, lat1, lon2, lat2)
%NATHAVERSINE 大圆距离（km，地球半径 6371 km），输入按 MATLAB 隐式扩展规则逐元素计算（度）。
a = sind((lat2 - lat1) / 2) .^ 2 + cosd(lat1) .* cosd(lat2) .* sind((lon2 - lon1) / 2) .^ 2;
d = 2 * 6371 * asin(sqrt(min(1, a)));
end
