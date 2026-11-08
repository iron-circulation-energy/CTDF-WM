function s = natStorage(r, d, eta, lambda, pinQ, years)
%NATSTORAGE “风光 + 季节性储能”稳定供电单元的储能需求（带效率的序列峰值法，日尺度）。
%   s = natStorage(r, d, eta, lambda, pinQ, years)
%   r       Y×365 风光组合日平均容量因子（每单位风光装机的日平均出力）
%   d       Y×365 日平均负荷（以多年平均负荷为 1 归一化）
%   eta     储能往返效率（富余电量 → 可放出电量）
%   lambda  风光超配倍数（≥ 1，相对电量平衡容量 K*）
%   pinQ    充电功率取正富余功率的 pinQ 分位数（1 为最大值）；超过充电功率的富余电量弃用
%   years   可选真实历年，须与矩阵行一一对应并严格递增连续。省略时调用方承诺各行
%           为按时间顺序相邻的合成年段；不能将不连续观测年份当作相邻行传入。
%   单位：功率以平均负荷为 1（即每 1 MW 平均负荷），能量以“平均负荷日”计（1 = 24 MWh/MW）。
%
%   方法：
%     1 电量平衡容量 K*：η·Σ min(u⁺, P_in) = Σ u⁻，u = K·r − d（全记录，二分法求解）；K = λ·K*。
%     2 序列峰值（循环）：z_t = max(0, z_{t−1} + u⁻_t − η·min(u⁺_t, P_in))，z 为距满库的亏欠量；
%       以第一遍末值为初值再算一遍，S = max z（满足全记录不缺电的最小储能能量，可放出电量口径）。
%     3 储能服务：放电功率 P_dis = max u⁻；年放电量 E_out = Σu⁻/Y；年充电量 E_in = E_out/η；
%       放电利用小时 h_out = 24·E_out/P_dis；充电利用小时 h_in = 24·E_in/P_in；
%       满功率自治天数 D = S/P_dis（与成本模型 natCost 的 D 口径一致）。
%   输出 s：K、Kstar、Pin、S、peakDis、Eout、Ein、hOut、hIn、D、curt（弃电占风光发电量比例）、
%           direct（风光直接供电占负荷比例）、z、de、ch（Y×365：亏欠量、日缺电量、日充电量）。
%   参考：序列峰值法（sequent-peak）是水库调节计算的经典方法；以多年再分析数据确定 100% 风光系统储能能量需求的
%   做法见 Ruhnau & Qvist (2022, Environ. Res. Lett. 17:044018)。

if nargin < 4 || isempty(lambda)
    lambda = 1;
end
if nargin < 5 || isempty(pinQ)
    pinQ = 1;
end
if ~isscalar(lambda) || ~isfinite(lambda) || lambda < 1
    error('natStorage:lambda', 'The common service reference requires lambda >= 1.');
end
validateattributes(eta, {'numeric'}, {'scalar','finite','>',0,'<=',1});
validateattributes(pinQ, {'numeric'}, {'scalar','finite','>',0,'<=',1});
validateattributes(r, {'numeric'}, {'nonnegative','finite','nonempty'});
validateattributes(d, {'numeric'}, {'nonnegative','finite','size',size(r)});
[Y, nd] = size(r);
if nargin < 6
    years = [];
end
if ~isempty(years) && (~isnumeric(years) || ~isreal(years) || ~isvector(years) || ...
        numel(years)~=Y || any(~isfinite(years)) || any(years~=fix(years)) || any(diff(years(:))~=1))
    error('natStorage:nonConsecutiveYears', ...
        'Provided years must match the rows and be strictly increasing consecutive integer calendar years.');
end
x = reshape(r', [], 1);
y = reshape(d', [], 1);
bal = @(K) balance(K, x, y, eta, pinQ);
lo = 0;
hi = 1;
it = 0;
while bal(hi) < 0
    hi = 2 * hi;
    it = it + 1;
    if it > 20
        error('natStorage:balance', '风光出力过低，无法达到电量平衡。');
    end
end
for it = 1:80
    m = (lo + hi) / 2;
    if bal(m) < 0
        lo = m;
    else
        hi = m;
    end
    if hi-lo <= 1e-12*max(1,hi)
        break;
    end
end
Kstar = hi;
K = lambda * Kstar;
[~, ch, de, Pin] = balance(K, x, y, eta, pinQ);
% Cyclic route sizing below supplies the converged deficit trajectory.
z = zeros(numel(x), 1);
s.K = K;
s.Kstar = Kstar;
s.Pin = Pin;
s.S = max(z);
s.peakDis = max(de);
s.Eout = sum(de) / Y;
s.Ein = s.Eout / eta;
s.hOut = 24 * s.Eout / max(s.peakDis, eps);
s.hIn = 24 * s.Ein / max(Pin, eps);
s.D = s.S / max(s.peakDis, eps);
gen = K * sum(x);
s.direct = sum(min(K * x, y)) / sum(y);
s.curt = max(0, gen - sum(min(K * x, y)) - sum(de) / eta) / gen;
s.z = reshape(z, nd, Y)';
s.de = reshape(de, nd, Y)';
s.ch = reshape(ch, nd, Y)';
s.chAvailable = s.ch;
s.years = years(:)';
s = natRouteService(s, eta);
end

function [f, ch, de, Pin] = balance(K, x, y, eta, pinQ)
u = K * x - y;
sur = max(u, 0);
de = max(-u, 0);
pos = sur(sur > 0);
if isempty(pos)
    Pin = 0;
else
    Pin = quantileLin(pos, pinQ);
end
ch = min(sur, Pin);
f = eta * sum(ch) - sum(de);
end
