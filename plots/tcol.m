function v = tcol(T, name, default)
%TCOL 读取结果表（table 或由列向量组成的结构体）的一列；不存在时返回 default（缺省为空）。
%   字符串列统一转换为 cellstr，便于 strcmp 比较。
if nargin < 3
    default = [];
end
has = false;
if isstruct(T)
    has = isfield(T, name);
else
    try
        has = any(strcmp(T.Properties.VariableNames, name));
    catch
        has = false;
    end
end
if ~has
    v = default;
    return;
end
v = T.(name);
if ~isnumeric(v) && ~islogical(v)
    v = cellstr(v);
end
end
