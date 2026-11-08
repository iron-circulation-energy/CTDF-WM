function [a, matched] = calibrateWindAlpha(U, target, cfg, weights)
%CALIBRATEWINDALPHA Match mean wind CF on alpha in [0.3,3], including cutout.
% U contains equivalent wind speeds. Optional weights have one value per U.
% Wind CF is nondecreasing only BETWEEN cutout breakpoints cfg.windVout/U.
% Search these intervals in order and return the first attainable root.
% If no root exists, matched=false; a is diagnostic only and must not be used
% as a successful calibration. In particular, alpha=3 may yield zero power.
validateattributes(U,{'numeric'},{'real','finite','nonnegative','nonempty'});
validateattributes(target,{'numeric'},{'real','finite','scalar','nonnegative'});
U = U(:);
if nargin < 4 || isempty(weights), weights = ones(size(U)); end
validateattributes(weights,{'numeric'},{'real','finite','nonnegative','numel',numel(U)});
weights = weights(:);
if sum(weights) <= 0, error('calibrateWindAlpha:weights','Wind weights must have a positive sum.'); end
weights = weights / sum(weights);
value = @(x) sum(weights .* windCF(x*U,cfg));
lo = 0.3; hi = 3;
cut = cfg.windVout ./ U(U>0 & weights>0);
edges = unique([lo;cut(cut>lo & cut<=hi);hi]);
a = lo; matched = false; best = abs(value(lo)-target); tol = 1e-11;
for k = 1:numel(edges)-1
    left = edges(k); right = edges(k+1);
    % Exclude the downward jump at the right-hand cutout boundary.
    right = max(left,right-8*eps(right));
    fl = value(left)-target; fr = value(right)-target;
    [err,j] = min(abs([fl,fr]));
    if err < best
        pair = [left,right]; a = pair(j); best = err;
    end
    if abs(fl) <= tol, a = left; matched = true; return; end
    if fl <= 0 && fr >= 0
        for it = 1:60
            mid = (left+right)/2;
            if value(mid) < target, left = mid; else, right = mid; end
        end
        a = (left+right)/2;
        matched = abs(value(a)-target) <= tol;
        return;
    end
end
if abs(value(hi)-target) <= tol, a = hi; matched = true; end
end
