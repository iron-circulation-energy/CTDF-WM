function ds = loadChunked(dirOut, prefix)
%LOADCHUNKED 读取 saveChunked 分块保存的数据集。

L = load(fullfile(dirOut, sprintf('%s_index.mat', prefix)));
ds = L.meta;
first = load(fullfile(dirOut, sprintf('%s_S_%03d.mat', prefix, 1)));
ds.S = zeros(size(first.Sk, 1), L.M, 'like', first.Sk);
ds.S(:, first.cols) = first.Sk;
for k = 2:L.nCh
    c = load(fullfile(dirOut, sprintf('%s_S_%03d.mat', prefix, k)));
    ds.S(:, c.cols) = c.Sk;
end
end
