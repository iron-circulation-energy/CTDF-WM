function st = natRouteStyle(S)
%NATROUTESTYLE 全国评估路线的配色与图例名称（图 N03、N04、N06—N08 共用）；S.lang 为 'en' 时为英文名称。
%   st.keys（1×6 cellstr）、st.colors（6×3）、st.labels（1×6 cellstr）、st.color(key)、st.label(key)。
%   铁燃料路线为暖色（与本文方法同一色系），氢为青/浅蓝，绿氨为紫；key 可为字符向量或 string 标量。

st.keys = {'FeL', 'FeX', 'FeT', 'H2S', 'H2T', 'NH3L'};
hex = {'#B9532F', '#E0A33E', '#7A3B26', '#3E9089', '#9CC3DA', '#8E6BB0'};   % 六条路线两两可分（含色觉缺陷）
st.colors = cell2mat(cellfun(@(h) [hex2dec(h(2:3)), hex2dec(h(4:5)), hex2dec(h(6:7))] / 255, hex(:), ...
    'UniformOutput', false));
st.labels = {'省内铁粉循环（改造本省煤电）', '跨省铁路运铁', '送端铁粉循环 + 特高压直流', '盐穴储氢 + 氢燃机', ...
    '地面储罐储氢 + 氢燃机', '绿氨 + 改造煤电纯氨燃烧'};
if nargin >= 1 && isfield(S, 'lang') && strcmpi(S.lang, 'en')
    st.labels = {'Local iron loop', 'Cross-province iron by rail', 'Sending-end iron with UHV', ...
        'Salt-cavern hydrogen', 'Tank hydrogen', 'Green ammonia in retrofitted units'};
end
keys = st.keys;
cols = st.colors;
labs = st.labels;
st.color = @(k) pick(cols, keys, k, [0.80, 0.80, 0.80]);
st.label = @(k) pickLabel(labs, keys, k);
end

function c = pick(cols, keys, k, d)
i = find(strcmp(keys, char(k)), 1);
if isempty(i)
    c = d;
else
    c = cols(i, :);
end
end

function s = pickLabel(labs, keys, k)
i = find(strcmp(keys, char(k)), 1);
if isempty(i)
    s = char(k);
else
    s = labs{i};
end
end
