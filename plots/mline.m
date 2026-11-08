function s = mline(c)
%MLINE 把多行文字（cellstr）合并为含换行符的字符向量；text 对象的 String 因而始终为字符，
%   便于测试与导出脚本统一读取（string(get(t, 'String'))）。输入为字符时原样返回。
if iscell(c)
    s = strjoin(c(:)', char(10));
else
    s = c;
end
end
