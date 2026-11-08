function s = lab(S, zh, en)
%LAB 图中文字的中英文选择：S.lang 为 'en' 时返回 en，否则返回 zh。
if isfield(S, 'lang') && strcmpi(S.lang, 'en')
    s = en;
else
    s = zh;
end
end
