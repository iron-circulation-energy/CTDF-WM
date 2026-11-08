function te = sinusoidalEmbed(t, dT)
%SINUSOIDALEMBED 流时间 t ∈ [0,1] 的正弦嵌入（dT 维，频率在 1~1000 间按几何级数分布）。
%   t：1×B；te：dT×B，与 t 同类型（numeric、gpuArray 或 dlarray）。

half = floor(dT / 2);
k = (0:half - 1)';
freq = exp(log(1000) * k / max(half - 1, 1));
if isa(t, 'dlarray')
    freq = cast(freq, 'like', extractdata(t));
else
    freq = cast(freq, 'like', t);
end
ang = 2 * pi * freq .* t;
te = [sin(ang); cos(ang)];
if size(te, 1) < dT
    te = [te; zeros(dT - size(te, 1), size(t, 2), 'like', te)];
end
end
