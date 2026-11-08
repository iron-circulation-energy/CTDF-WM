function s = siteEnglish(id, fallback)
%SITEENGLISH 浩吉通道节点与示意线路的英文名称（英文图用），id 为 p.site 的 id 或 p.siteLines 的 style。
k = {'R1', 'R2', 'R3', 'H1', 'H2', 'P1', 'P2', 'P3', 'P4', 'P5', 'P6', 'rail', 'river'};
v = {'Uxin Banner', 'Jingbian', 'Hanggin Banner', 'Jingzhou hub', 'Yueyang hub', 'Huadian Jiangling', ...
    'Huaneng Jingmen', 'Huadian Changde', 'Huaneng Yueyang', 'CR Puqi', 'Guoneng Jiujiang', ...
    'Haoji railway, schematic', 'Yangtze River'};
i = find(strcmp(k, id), 1);
if isempty(i)
    s = fallback;
else
    s = v{i};
end
end
