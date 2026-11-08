function en = provEnglish(names)
%PROVENGLISH 省级行政区中文名（全称或简称）对应的英文名，用于英文图的刻度与标注。
zh = {'北京', '天津', '河北', '山西', '内蒙古', '辽宁', '吉林', '黑龙江', '上海', '江苏', '浙江', '安徽', '福建', ...
    '江西', '山东', '河南', '湖北', '湖南', '广东', '广西', '海南', '重庆', '四川', '贵州', '云南', '西藏', '陕西', ...
    '甘肃', '青海', '宁夏', '新疆', '香港', '澳门', '台湾'};
ev = {'Beijing', 'Tianjin', 'Hebei', 'Shanxi', 'Inner Mongolia', 'Liaoning', 'Jilin', 'Heilongjiang', 'Shanghai', ...
    'Jiangsu', 'Zhejiang', 'Anhui', 'Fujian', 'Jiangxi', 'Shandong', 'Henan', 'Hubei', 'Hunan', 'Guangdong', ...
    'Guangxi', 'Hainan', 'Chongqing', 'Sichuan', 'Guizhou', 'Yunnan', 'Tibet', 'Shaanxi', 'Gansu', 'Qinghai', ...
    'Ningxia', 'Xinjiang', 'Hong Kong', 'Macao', 'Taiwan'};
names = cellstr(names);
en = names;
for k = 1:numel(names)
    s = regexprep(names{k}, '(省|市|壮族自治区|回族自治区|维吾尔自治区|自治区|特别行政区)$', '');
    i = find(strcmp(zh, s), 1);
    if ~isempty(i)
        en{k} = ev{i};
    end
end
end
