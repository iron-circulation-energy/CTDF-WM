function R = newRunDir(root, expName, stamp, p, extra)
%NEWRUNDIR 建立结果目录 results/<实验名>/<时间戳>/ 并保存可复现信息（第一、十二部分）。
%   保存 config.mat（完整参数 p、时间戳、附加信息 extra，例如种子与依赖的公共结果目录）、
%   ver.txt（MATLAB 与工具箱版本、主机信息、GPU 信息），并打开 log.txt。
%   输出 R：dir（目录）、fid（日志文件句柄）、stamp。用毕调用 fclose(R.fid)。

if nargin < 5
    extra = struct();
end
R.dir = fullfile(root, expName, stamp);
if ~exist(R.dir, 'dir')
    mkdir(R.dir);
end
cfgInfo = extra; %#ok<NASGU>
save(fullfile(R.dir, 'config.mat'), 'p', 'stamp', 'cfgInfo');
txt = evalc('ver');
host = getenv('COMPUTERNAME');
if isempty(host)
    host = getenv('HOSTNAME');
end
gpuTxt = '无可用 GPU';
try
    if canUseGPU()
        g = gpuDevice();
        gpuTxt = sprintf('GPU：%s（计算能力 %s）。注意：GPU 上的归约与卷积运算可能不确定，同一种子的结果可能有微小差异。', ...
            g.Name, g.ComputeCapability);
    end
catch
end
fidv = fopen(fullfile(R.dir, 'ver.txt'), 'w');
fprintf(fidv, '%s\n主机：%s\n计算机架构：%s\n逻辑核数：%d\n%s\n', txt, host, computer('arch'), ...
    feature('numcores'), gpuTxt);
fclose(fidv);
R.fid = fopen(fullfile(R.dir, 'log.txt'), 'a');
R.stamp = stamp;
logMsg(R.fid, '结果目录：%s', R.dir);
end
