function seqs = worstCaseSequence(Dmax, Umax, gap, reps)
%WORSTCASESEQUENCE 有界扰动集下的对抗事件序列族（临界循环质量检查）。
%   'N' 常规日，'D' 低风光日，'U' 富余日；相邻事件之间留 gap 天恢复期（A4）。
%   族：DU（低风光与富余交替，低风光先）、UD（富余先）、DD（连续低风光事件）、UU（连续富余事件）、
%       D1（单次低风光）、U1（单次富余）。各事件取最大持续天数 D_max、U_max。
%   输出 seqs：结构体，各字段为字符行向量。

if nargin < 4
    reps = 3;
end
Dm = round(Dmax);
Um = round(Umax);
N = repmat('N', 1, gap);
Dd = repmat('D', 1, Dm);
Uu = repmat('U', 1, Um);
seqs.DU = [repmat([N, Dd, N, Uu], 1, reps), N];
seqs.UD = [repmat([N, Uu, N, Dd], 1, reps), N];
seqs.DD = [repmat([N, Dd], 1, reps), N];
seqs.UU = [repmat([N, Uu], 1, reps), N];
seqs.D1 = [N, Dd, N];
seqs.U1 = [N, Uu, N];
end
