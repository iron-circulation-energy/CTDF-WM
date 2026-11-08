function seg = buildSegment(Wy, d0, len, p, withForecast)
%BUILDSEGMENT 从气象年 Wy 截取第 d0 天起的片段，长度 len 天（另附 Hmax 天前瞻尾部，若年内可用）。
%   withForecast 为真（默认）时调用 forecaster 生成 seg.F。
%   输出 seg：reg、eW、eS、eL、doy、EW、ES、EL（1×Nseg）、carbon、h2、year、d0、len、N、F。

if nargin < 5
    withForecast = true;
end
Hm = p.forecast.Hmax;
if d0 < 1 || d0 + len - 1 > Wy.N
    error('buildSegment:range', '片段超出气象年长度（d0 = %d，len = %d，N = %d）。', d0, len, Wy.N);
end
last = min(Wy.N, d0 + len - 1 + Hm);
ix = d0:last;
seg.reg = Wy.reg(ix);
seg.eW = Wy.eW(ix);
seg.eS = Wy.eS(ix);
seg.eL = Wy.eL(ix);
seg.doy = Wy.doy(ix);
seg.EW = Wy.EW(ix);
seg.ES = Wy.ES(ix);
seg.EL = Wy.EL(ix);
seg.carbon = Wy.carbon;
seg.h2 = Wy.h2;
seg.year = Wy.year;
seg.d0 = d0;
seg.len = len;
seg.N = numel(ix);
if withForecast
    seg.F = forecaster(seg, p);
end
end
