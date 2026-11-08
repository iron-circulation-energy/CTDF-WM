function [seg, cap, ext] = buildEvalSegment(ctx, W, spec)
%BUILDEVALSEGMENT 由评估回合说明 spec 构造气象片段与时变容量表。
%   spec 字段：year、d0、len（= warmup + evalDays）、warmup、scenario（'normal'、'drought'、'outage'、
%   'stationOut'）、可选 carbon、h2（覆盖该年碳价、氢价，E6 用）。
%   极端事件自第 warmup + p.exp.extremeStart 天开始：
%     drought     连续 p.exp.droughtDays 天低风光（injectExtremes）；
%     outage      p.exp.outageLines 中断 p.exp.outageDays 天，缺省为全部“还原站→枢纽”铁路铁线路；
%     stationOut  还原站 p.exp.outStations 故障 p.exp.stationOutDays 天。
%   输出 seg（含预测 F）、cap（Fcap、rhoAvail）、ext（注入的事件说明）。

p = ctx.p;
topo = ctx.topo;
if isfield(spec, 'calendarEvaluation') && spec.calendarEvaluation
    seg = calendarSegment(W, spec, p);
else
    seg = buildSegment(W(spec.year), spec.d0, spec.len, p);
end
if isfield(spec, 'carbon') && ~isempty(spec.carbon)
    seg.carbon = spec.carbon;
end
if isfield(spec, 'h2') && ~isempty(spec.h2)
    seg.h2 = spec.h2;
end
st = spec.warmup + p.exp.extremeStart;
switch lower(spec.scenario)
    case 'normal'
        ext = struct('type', 'none');
    case 'drought'
        ext = struct('type', 'drought', 'start', st, 'days', p.exp.droughtDays);
    case 'outage'
        lines = p.exp.outageLines;
        if isempty(lines)
            lines = find(topo.mat == 1 & topo.mode == 1 & ...
                strcmp(topo.nodeType(topo.from), 'R') & strcmp(topo.nodeType(topo.to), 'H'));
            if isempty(lines)
                lines = find(topo.mat == 1 & topo.mode == 1);
            end
        end
        ext = struct('type', 'outage', 'start', st, 'days', p.exp.outageDays, 'lines', lines(:)');
    case 'stationout'
        ext = struct('type', 'stationOut', 'start', st, 'days', p.exp.stationOutDays, 'stations', p.exp.outStations);
    otherwise
        error('buildEvalSegment:scenario', '未知工况 %s。', spec.scenario);
end
[seg, cap] = injectExtremes(seg, ext, p, topo);
end

function seg = calendarSegment(W, spec, p)
% Prepend only prior observations. First available year uses a labelled cyclic warm-up.
nd = p.weather.daysPerYear;
nw = spec.warmup;
ne = spec.len - nw;
if nw > nd || ne > nd
    error('buildEvalSegment:calendar', 'Warm-up and scored interval must each fit a weather year.');
end
y = spec.year;
yp = max(1, y - 1);
pre = (nd - nw + 1):nd;
body = 1:ne;
fields = {'reg','eW','eS','eL','doy','EW','ES','EL'};
wy = W(y);
for k = 1:numel(fields)
    f = fields{k};
    wy.(f) = [W(yp).(f)(pre), W(y).(f)(body)];
end
wy.N = spec.len;
wy.sourceYearIndex = [yp * ones(1, nw), y * ones(1, ne)];
seg = buildSegment(wy, 1, spec.len, p);
seg.sourceYearIndex = wy.sourceYearIndex;
seg.warmupSource = 'previous observed year';
if y == 1, seg.warmupSource = 'cyclic first-year warm-up (no earlier record)'; end
seg.scoredYear = y;
end
