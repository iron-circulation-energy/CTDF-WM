function starts = validWeatherStarts(Wy, p, len, allowedYears, baseOnly)
%VALIDWEATHERSTARTS Starts whose entire len-day STATE window belongs to the allowed split.
% len already includes any terminal state needed by the caller; no extra day is added here.
% Historical CSV tails identify their real source year. Synthetic continuations belong to
% their generating year. Without provenance we conservatively use the 365-day body only.
if nargin < 5, baseOnly = true; end
validateattributes(len, {'numeric'}, {'scalar','integer','positive'});
if isfield(Wy, 'sourceYearIndex') && numel(Wy.sourceYearIndex) == Wy.N
    ok = ismember(Wy.sourceYearIndex(:)', allowedYears);
elseif strcmpi(p.weather.source, 'synthetic')
    ok = repmat(ismember(Wy.year, allowedYears), 1, Wy.N);
else
    ok = false(1, Wy.N);
    ok(1:min(Wy.N, p.weather.daysPerYear)) = ismember(Wy.year, allowedYears);
end
last = Wy.N - len + 1;
if baseOnly, last = min(last, p.weather.daysPerYear); end
starts = [];
if last < 1, return; end
badPrefix = [0, cumsum(~ok)];
candidates = 1:last;
starts = candidates(badPrefix(candidates + len) - badPrefix(candidates) == 0);
end
