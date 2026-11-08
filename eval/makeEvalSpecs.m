function specs = makeEvalSpecs(p, years, seeds, scenarios, c, extra)
%MAKEEVALSPECS 生成评估回合说明（年份 × 种子 × 工况），供 evalEpisodes 使用。
%   每个回合长度 len = p.exp.warmup + p.exp.evalDays，前 warmup 天不计入指标；
%   Evaluation always starts on day 1 of the declared year. buildEvalSegment prepends
%   historical warm-up, so 365 scored days never include the following year.
%   extra（可选结构体）中的字段原样复制到每个回合说明（例如 carbon、h2、keepTrace）。
%   输出 specs：结构体数组，字段 year、seed、scenario、d0、len、warmup、c、initSOC、keepTrace 及 extra 字段。

if nargin < 6
    extra = struct();
end
if ischar(scenarios) || isstring(scenarios)
    scenarios = cellstr(scenarios);
end
len = p.exp.warmup + p.exp.evalDays;
if p.exp.evalDays > p.weather.daysPerYear
    error('makeEvalSpecs:year', 'Evaluation cannot exceed one declared weather year.');
end
cells = {};
fn = fieldnames(extra);
for y = years(:)'
    for s = seeds(:)'
        for m = 1:numel(scenarios)
            sp = struct();
            sp.year = y;
            sp.seed = s;
            sp.scenario = scenarios{m};
            sp.d0 = 1;
            sp.calendarEvaluation = true;
            sp.len = len;
            sp.warmup = p.exp.warmup;
            sp.c = c;
            sp.initSOC = p.exp.initSOC;
            sp.keepTrace = false;
            for f = 1:numel(fn)
                sp.(fn{f}) = extra.(fn{f});
            end
            cells{end + 1} = sp; %#ok<AGROW>
        end
    end
end
specs = [cells{:}];
end
