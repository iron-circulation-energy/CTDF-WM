function logMsg(fid, fmt, varargin)
%LOGMSG 同时向命令行与日志文件输出带时间戳的信息（fid 为空或 < 0 时只输出到命令行）。

msg = sprintf(fmt, varargin{:});
line = sprintf('[%s] %s\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), msg);
fprintf('%s', line);
if ~isempty(fid) && fid > 0
    fprintf(fid, '%s', line);
end
end
