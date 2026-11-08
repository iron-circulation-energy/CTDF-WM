function files = saveChunked(ds, dirOut, prefix, chunkCols)
%SAVECHUNKED 数据集分块保存为 .mat：状态矩阵 S 按列分块（每块 chunkCols 列），
%   其余字段（转移下标、策略编号、元信息）保存在 <prefix>_index.mat。
%   读取：loadChunked(dirOut, prefix)。

if ~exist(dirOut, 'dir')
    mkdir(dirOut);
end
M = size(ds.S, 2);
nCh = max(1, ceil(M / chunkCols));
files = cell(1, nCh + 1);
for k = 1:nCh
    cols = (k - 1) * chunkCols + 1:min(M, k * chunkCols);
    Sk = ds.S(:, cols); %#ok<NASGU>
    files{k} = fullfile(dirOut, sprintf('%s_S_%03d.mat', prefix, k));
    save(files{k}, 'Sk', 'cols', '-v7.3');
end
meta = rmfield(ds, 'S'); %#ok<NASGU>
files{end} = fullfile(dirOut, sprintf('%s_index.mat', prefix));
% 索引文件最后写入并以“临时文件 + 改名”原子替换：索引存在即表示全部分块已写完（断点续跑据此判断）
tmp = fullfile(dirOut, sprintf('%s_index.tmp.mat', prefix));
save(tmp, 'meta', 'M', 'nCh', '-v7.3');
movefile(tmp, files{end}, 'f');
end
