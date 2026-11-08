function varargout = statsUtils(op, varargin)
%STATSUTILS 统计工具。用法：
%   [mu, sd, lo, hi] = statsUtils('meanCI', x)            均值、标准差与 t 分布 95% 置信区间（x 为向量，忽略 NaN）
%   [pval, dMean, n] = statsUtils('pairedT', a, b)         配对 t 检验（双侧），a、b 为同一（年份, 种子, 工况）配对的样本
%   [lo, hi] = statsUtils('bootCI', x, fun, B, seed)       百分位自助法 95% 置信区间
%   F = statsUtils('tcdf', t, nu)                          学生 t 分布累积分布函数（由不完全 Beta 函数计算）
%   q = statsUtils('tinv', p, nu)                          学生 t 分布分位数（二分法求解）
%   [b, sse] = statsUtils('knee2seg', x, y)                连续两段线性拟合 y = β0 + β1·min(x − b, 0) + β2·max(x − b, 0)，
%                                                          在细网格上取残差平方和最小的断点 b（E2 拐点方法一）
%   [b, kap] = statsUtils('kneeCurv', x, y, bw)            Nadaraya–Watson 高斯核平滑后（带宽 bw 为 x 跨度的比例，缺省 0.08），
%                                                          在归一化坐标下取曲率 |y''|/(1 + y'^2)^(3/2) 最大点（E2 拐点方法二）
%   T = statsUtils('summaryTable', T, keys, metrics)       按 keys 分组，输出各指标的均值、标准差与 95% 置信区间

switch lower(op)
    case 'meanci'
        [varargout{1:4}] = meanCI(varargin{1});
    case 'pairedt'
        [varargout{1:3}] = pairedT(varargin{1}, varargin{2});
    case 'clusterpaired'
        a = varargin{1}(:); b = varargin{2}(:); years = varargin{3}(:);
        ok = isfinite(a) & isfinite(b);
        if ~any(ok)
            out={NaN,NaN,0,NaN,NaN}; varargout=out(1:nargout); return;
        end
        [~,~,g] = unique(years(ok));
        d = accumarray(g, a(ok)-b(ok), [], @mean);
        [pv,dm,ny] = pairedT(d, zeros(size(d)));
        [~,~,lo,hi] = meanCI(d);
        out = {pv,dm,ny,lo,hi}; varargout = out(1:nargout);
    case 'bootci'
        [varargout{1:2}] = bootCI(varargin{:});
    case 'tcdf'
        varargout{1} = tcdfLocal(varargin{1}, varargin{2});
    case 'tinv'
        varargout{1} = tinvLocal(varargin{1}, varargin{2});
    case 'knee2seg'
        [varargout{1:2}] = knee2seg(varargin{1}, varargin{2});
    case 'kneecurv'
        [varargout{1:2}] = kneeCurv(varargin{:});
    case 'summarytable'
        varargout{1} = summaryTable(varargin{:});
    otherwise
        error('statsUtils:op', '未知操作 %s。', op);
end
end

function [mu, sd, lo, hi] = meanCI(x)
x = x(~isnan(x(:)));
n = numel(x);
mu = mean(x);
if n >= 2
    sd = std(x);
    h = tinvLocal(0.975, n - 1) * sd / sqrt(n);
    lo = mu - h;
    hi = mu + h;
else
    sd = NaN;
    lo = NaN;
    hi = NaN;
end
if n == 0
    mu = NaN;
end
end

function [pval, dMean, n] = pairedT(a, b)
d = a(:) - b(:);
d = d(~isnan(d));
n = numel(d);
dMean = mean(d);
if n < 2
    pval = NaN;
    return;
end
sd = std(d);
if sd == 0
    if dMean == 0
        pval = 1;
    else
        pval = 0;
    end
    return;
end
t = dMean / (sd / sqrt(n));
pval = 2 * (1 - tcdfLocal(abs(t), n - 1));
end

function [lo, hi] = bootCI(x, fun, B, seed)
if nargin < 3 || isempty(B)
    B = 1000;
end
if nargin < 4 || isempty(seed)
    seed = 1;
end
rs = RandStream('twister', 'Seed', seed);
x = x(:);
n = numel(x);
v = zeros(B, 1);
for b = 1:B
    v(b) = fun(x(randi(rs, n, n, 1)));
end
q = quantileLin(v, [0.025, 0.975]);
lo = q(1);
hi = q(2);
end

function F = tcdfLocal(t, nu)
x = nu ./ (nu + t .^ 2);
tail = 0.5 * betainc(x, nu / 2, 0.5);
F = 1 - tail;
F(t < 0) = tail(t < 0);
end

function q = tinvLocal(pr, nu)
lo = -1e3;
hi = 1e3;
for it = 1:200
    mid = 0.5 * (lo + hi);
    if tcdfLocal(mid, nu) < pr
        lo = mid;
    else
        hi = mid;
    end
end
q = 0.5 * (lo + hi);
end

function [bBest, sseBest] = knee2seg(x, y)
x = x(:);
y = y(:);
ok = ~isnan(y);
x = x(ok);
y = y(ok);
bBest=NaN; sseBest=NaN;
if numel(x)<4 || numel(unique(x))<4 || max(y)==min(y), return; end
grid = linspace(min(x), max(x), 400);
grid = grid(2:end - 1);
sseBest = inf;
bBest = NaN;
for b = grid
    A = [ones(numel(x), 1), min(x - b, 0), max(x - b, 0)];
    if rank(A) < 3
        continue;
    end
    coef = A \ y;
    r = y - A * coef;
    sse = r' * r;
    if sse < sseBest
        sseBest = sse;
        bBest = b;
    end
end
end

function [bBest, kap] = kneeCurv(x, y, bw)
if nargin < 3 || isempty(bw)
    bw = 0.08;
end
x = x(:);
y = y(:);
ok = ~isnan(y);
x = x(ok);
y = y(ok);
bBest=NaN; kap=[];
if numel(x)<4 || numel(unique(x))<4 || max(y)==min(y), return; end
xs = (x - min(x)) / max(max(x) - min(x), eps);
ys = (y - min(y)) / max(max(y) - min(y), eps);
g = linspace(0, 1, 400)';
W = exp(-0.5 * ((g - xs') / bw) .^ 2);
ysm = (W * ys) ./ max(sum(W, 2), eps);
d1 = gradient(ysm, g);
d2 = gradient(d1, g);
kap = abs(d2) ./ (1 + d1 .^ 2) .^ 1.5;
inner = g > 0.05 & g < 0.95;
kap(~inner) = 0;
[~, k] = max(kap);
bBest = min(x) + g(k) * (max(x) - min(x));
end

function S = summaryTable(T, keys, metrics)
if ischar(keys)
    keys = {keys};
end
[G, K] = findgroups(T(:, keys));
rows = cell(height(K), 1);
for g = 1:height(K)
    sel = G == g;
    r = K(g, :);
    for m = 1:numel(metrics)
        v = T.(metrics{m})(sel);
        if ismember('year',T.Properties.VariableNames)
            [~,~,gy] = unique(T.year(sel));
            v = accumarray(gy,v,[],@(x) mean(x,'omitnan'));
            r.([metrics{m} '_nYears']) = nnz(isfinite(v));
        end
        [mu, sd, lo, hi] = meanCI(v);
        r.([metrics{m} '_mean']) = mu;
        r.([metrics{m} '_sd']) = sd;
        r.([metrics{m} '_lo']) = lo;
        r.([metrics{m} '_hi']) = hi;
    end
    r.n = nnz(sel);
    if ismember('year',T.Properties.VariableNames)
        r.nYears = numel(unique(T.year(sel)));
        r.ciUnit = {'weather_year'};
    end
    rows{g} = r;
end
S = vertcat(rows{:});
end
