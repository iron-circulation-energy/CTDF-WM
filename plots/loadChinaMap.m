function G = loadChinaMap()
%LOADCHINAMAP 读取中国省级行政区底图（plots/geo/china_map.mat，由用户提供的 GeoJSON 转换，EPSG:4490 经纬度）。
%   字段：provName（省级名称，由 provNameCode 转换）、provRings（各省多边形环，元胞嵌套，每环 K×2 [经度, 纬度]）、
%   provLabel（最大环形心）、bndLines（境界线，含南海断续线）、bndIsNanhai（是否为南海断续线）、source（数据说明）。
%   原始数据见 plots/geo/china_provinces.geojson；论文中使用地图时须注明底图的审图号。

persistent cache
if isempty(cache)
    f = fullfile(fileparts(mfilename('fullpath')), 'geo', 'china_map.mat');
    if ~isfile(f)
        error('loadChinaMap:file', '找不到底图文件 %s。', f);
    end
    cache = load(f);
    % 名称以 UTF-16 码元（uint16）保存，避免不同版本读取 UTF-8 字符数据的差异
    cache.provName = cellfun(@(c) char(double(c)), cache.provNameCode, 'UniformOutput', false);
    cache.source = char(double(cache.sourceCode));
    cache.bndIsNanhai = logical(cache.bndIsNanhai);
end
G = cache;
end
