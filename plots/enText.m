function s = enText(s)
%ENTEXT 把图中残留的中文（来自结果表或参数的标签）替换为英文，并把全角标点换成半角。
%   s 为字符向量、字符串或元胞数组；替换顺序：完整短语 → 省份与站点名 → 全角标点 → 末尾“年”。
persistent D
if isempty(D)
    D = dict();
end
if iscell(s)
    for i = 1:numel(s)
        s{i} = enText(s{i});
    end
    return;
end
wasStr = isstring(s);
if wasStr
    if numel(s) ~= 1
        s = string(enText(cellstr(s)));
        return;
    end
    s = char(s);
end
if ~ischar(s) || isempty(s)
    if wasStr, s = string(s); end
    return;
end
if size(s, 1) > 1                                          % 多行字符矩阵
    c = cellstr(s);
    s = char(enText(c));
    if wasStr, s = string(s); end
    return;
end
if any(s > 127)
    for k = 1:size(D, 1)
        if contains(s, D{k, 1})
            s = strrep(s, D{k, 1}, D{k, 2});
        end
    end
    s = regexprep(s, '(\d{4})\s*年', '$1');
end
if wasStr
    s = string(s);
end
end

function D = dict()
ph = {
    % E1 分项
    '新建并网接入（双方对称）', 'New grid connections'; '拆除费用推迟', 'Deferred decommissioning';
    '延寿改造投资', 'Life extension'; '保留机组固定运维', 'Retained-unit fixed O&M';
    '剔除弃电惩罚', 'Curtailment penalty removed'; '替代方案跨区域特高压输能', 'UHV for the alternative';
    '铁路按边际运营成本计价', 'Rail at marginal cost'; '2030 年电解与还原投资', '2030 electrolysis and reduction';
    '2030 年碳价', '2030 carbon price'; '储氢缓冲与还原厂按平均通量配置', 'H_2 buffer for reduction';
    '盐穴垫底气', 'Salt-cavern cushion gas'; '富余时段售氢', 'Hydrogen sales'; '电解副产氧气', 'By-product oxygen';
    '电解余热供热', 'Electrolysis heat'; '同步机组转动惯量', 'Synchronous inertia';
    '消纳责任权重履约（绿证）', 'Green certificates';
    '替代方案复用原址并网接入', 'Grid-connection reuse by the alternative';
    '全面核算合计', 'Comprehensive total'; '基准核算', 'Base account';
    % E5 要素
    '终端投影（训练相同，仅推理不同）', 'Terminal projection'; '速度投影', 'Velocity projection';
    'Dirichlet 源', 'Dirichlet source'; '时域课程', 'Horizon curriculum';
    % E6 因素
    '往返效率', 'Round-trip efficiency'; '还原氢耗', 'Reduction H_2 use'; '运输方式', 'Transport mode';
    '运输距离', 'Transport distance'; '改造成本', 'Retrofit cost'; '碳价', 'Carbon price'; '氢价', 'Hydrogen price';
    % 站点
    '荆州江陵枢纽', 'Jingzhou hub'; '岳阳华容枢纽', 'Yueyang hub'; '乌审旗', 'Uxin Banner'; '靖边', 'Jingbian';
    '杭锦旗', 'Hanggin Banner'; '华电江陵', 'Huadian Jiangling'; '华能荆门', 'Huaneng Jingmen';
    '华电常德', 'Huadian Changde'; '华能岳阳', 'Huaneng Yueyang'; '华润蒲圻', 'CR Puqi'; '国能九江', 'Guoneng Jiujiang';
    % 其他
    '测试年', 'Test year'; '基准', 'Base'};
zh = {'内蒙古自治区', '广西壮族自治区', '宁夏回族自治区', '新疆维吾尔自治区', '西藏自治区', ...
    '北京市', '天津市', '上海市', '重庆市', '河北省', '山西省', '辽宁省', '吉林省', '黑龙江省', '江苏省', '浙江省', ...
    '安徽省', '福建省', '江西省', '山东省', '河南省', '湖北省', '湖南省', '广东省', '海南省', '四川省', '贵州省', ...
    '云南省', '陕西省', '甘肃省', '青海省', '黑龙江', '内蒙古', '北京', '天津', '河北', '山西', '辽宁', '吉林', '上海', ...
    '江苏', '浙江', '安徽', '福建', '江西', '山东', '河南', '湖北', '湖南', '广东', '广西', '海南', '重庆', '四川', ...
    '贵州', '云南', '西藏', '陕西', '甘肃', '青海', '宁夏', '新疆', '台湾', '香港', '澳门'};
pv = cellfun(@(z) char(provEnglish({z})), zh, 'UniformOutput', false);
pr = [zh(:), pv(:)];
punct = {'（', ' ('; '）', ')'; '；', '; '; '，', ', '; '：', ': '; '、', ', '; '。', '. '; '“', '"'; '”', '"'; ...
    '‘', ''''; '’', ''''; '【', '['; '】', ']'; '～', '–'; '％', '%'; '　', ' '};
D = [ph; pr; punct];
[~, o] = sort(cellfun(@numel, D(:, 1)), 'descend');      % 长短语优先，避免被短词截断
D = D(o, :);
end
