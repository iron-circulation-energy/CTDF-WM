function styleColorbar(cb, S, label)
%STYLECOLORBAR 色标样式：无边框、刻度向外、灰色刻度文字，标签深色。

cb.Box = 'off';
cb.TickDirection = 'out';
cb.LineWidth = 0.6;
cb.Color = S.tick;
cb.FontName = S.font;
cb.FontSize = S.fs - 0.5;
if nargin >= 3 && ~isempty(label)
    cb.Label.String = label;
    cb.Label.Color = S.ink;
    cb.Label.FontName = S.font;
    cb.Label.FontSize = S.fs;
end
end
