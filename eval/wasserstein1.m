function d = wasserstein1(X, Y, opts)
%WASSERSTEIN1 两个经验分布之间的 1-Wasserstein 距离（列为样本，欧氏距离）。
%   opts.method：
%     'auto'   （默认）样本数不超过 opts.exactMax（默认 512）时精确求解，否则用切片 W1；
%     'exact'  等样本数时用 matchpairs 求最优指派（精确），不等时用 linprog 求运输问题（精确）；
%     'sliced' 随机方向投影后一维 W1 的平均（opts.nDirs 个方向，opts.seed 固定方向），乘 √D 校正到与欧氏 W1 同量级。
%   两种方法在小样本上交叉校验（见 tests/TestW1）。

if nargin < 3
    opts = struct();
end
method = getf(opts, 'method', 'auto');
exactMax = getf(opts, 'exactMax', 512);
nX = size(X, 2);
nY = size(Y, 2);
if strcmpi(method, 'auto')
    if max(nX, nY) <= exactMax
        method = 'exact';
    else
        method = 'sliced';
    end
end
X = double(X);
Y = double(Y);
switch lower(method)
    case 'exact'
        C2 = zeros(nX, nY);                       % 逐维累加差的平方（避免展开式的舍入抵消）
        for d = 1:size(X, 1)
            C2 = C2 + (X(d, :)' - Y(d, :)) .^ 2;
        end
        C = sqrt(C2);                             % nX×nY
        if nX == nY
            M = matchpairs(C, nX * max(C(:)) + 1);   % 未匹配代价大于任一完全匹配的总代价，保证完全匹配
            d = sum(C(sub2ind(size(C), M(:, 1), M(:, 2)))) / nX;
        else
            a = ones(nX, 1) / nX;
            b = ones(nY, 1) / nY;
            Aeq = [kron(ones(1, nY), speye(nX)); kron(speye(nY), ones(1, nX))];
            beq = [a; b];
            opt = optimoptions('linprog', 'Display', 'none');
            [~, d] = linprog(C(:), [], [], Aeq, beq, zeros(nX * nY, 1), [], opt);
        end
    case 'sliced'
        nDirs = getf(opts, 'nDirs', 256);
        rs = RandStream('twister', 'Seed', getf(opts, 'seed', 1));
        Dm = size(X, 1);
        V = randn(rs, Dm, nDirs);
        V = V ./ sqrt(sum(V .^ 2, 1));
        px = sort(V' * X, 2);
        py = sort(V' * Y, 2);
        % Integrate empirical inverse CDFs over their combined jump grid.
        % A max(nX,nY)-point midpoint rule is not exact when counts differ.
        edges = unique([(0:nX)/nX, (0:nY)/nY]);
        weights = diff(edges);
        qs = edges(1:end-1) + weights/2;
        ix = min(nX, max(1, ceil(qs*nX)));
        iy = min(nY, max(1, ceil(qs*nY)));
        d1 = abs(px(:,ix)-py(:,iy))*weights';
        d = mean(d1) * sqrt(Dm);
    otherwise
        error('wasserstein1:method', '未知方法 %s。', method);
end
end

function v = getf(s, f, dflt)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = dflt;
end
end
