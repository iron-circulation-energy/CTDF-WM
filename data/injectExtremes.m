function [seg, capSched] = injectExtremes(seg, ext, p, topo)
%INJECTEXTREMES 向气象片段注入极端事件，并生成时变容量表。
%   ext 字段：type（'none'、'drought'、'outage'、'stationOut'，可为元胞数组组合多个事件）、
%             start（片段内开始日）、days（持续天数）、lines（中断线路编号）、stations（故障还原站编号）。
%   'drought'    将连续 days 天强制为低风光状态，并由原 AR 残差重算日电量；
%   'surplus'    将连续 days 天强制为富余状态（完整网络环境检查用）；
%   'outage'     线路运力 F̄_e(k) 置零；
%   'stationOut' 还原站可用率 ρ̄_j(k) 置零。
%   注入后重新计算 seg.F，使预测器只在事件发生后才“看到”低风光（事件本身不可预知）。
%   输出 capSched：Fcap（nE×N，t/d）、rhoAvail（nR×N，0~1）。

N = numel(seg.EW);
capSched.Fcap = repmat(topo.Fcap(:), 1, N);
capSched.rhoAvail = ones(topo.nR, N);
if nargin < 2 || isempty(ext)
    return;
end
if ~iscell(ext)
    ext = {ext};
end
changed = false;
for m = 1:numel(ext)
    e = ext{m};
    if ~isfield(e, 'type') || strcmpi(e.type, 'none')
        continue;
    end
    dd = e.start:min(N, e.start + e.days - 1);
    switch lower(e.type)
        case {'drought', 'surplus'}
            if strcmpi(e.type, 'drought')
                seg.reg(dd) = 2;
            else
                seg.reg(dd) = 3;
            end
            [EW, ES, EL] = weatherEnergies(seg.reg(dd), seg.eW(dd), seg.eS(dd), seg.eL(dd), seg.doy(dd), p);
            seg.EW(dd) = EW;
            seg.ES(dd) = ES;
            seg.EL(dd) = EL;
            changed = true;
        case 'outage'
            capSched.Fcap(e.lines, dd) = 0;
        case 'stationout'
            capSched.rhoAvail(e.stations, dd) = 0;
        otherwise
            error('injectExtremes:type', '未知极端事件类型 %s。', e.type);
    end
end
if changed || ~isfield(seg, 'F')
    seg.F = forecaster(seg, p);
end
end
