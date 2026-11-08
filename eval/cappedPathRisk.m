function out = cappedPathRisk(values, gamma, alpha)
%CAPPEDPATHRISK Risk occupancy and finite-path bound for independent paths.
%   values(r,t) is a bounded fixed risk functional on path r at S_t (t>=1).
%   Rows, not individual times or resampled columns, are independent units.
%   Terminal mass is P(T>=H)=gamma^(H-1). The infinite-horizon risk differs
%   by at most P(T>H)=gamma^H because this functional lies in [0,1].
if nargin<3, alpha=.05; end
if ~isnumeric(values)||~isreal(values)||isempty(values)||ndims(values)>2|| ...
        any(~isfinite(values(:)))||any(values(:)<0|values(:)>1)
    error('cappedPathRisk:values','Risk values must be a nonempty finite R-by-H matrix in [0,1].');
end
if ~isnumeric(gamma)||~isreal(gamma)||~isscalar(gamma)||~isfinite(gamma)||gamma<0||gamma>=1
    error('cappedPathRisk:gamma','Discount must satisfy 0 <= gamma < 1.');
end
if ~isnumeric(alpha)||~isreal(alpha)||~isscalar(alpha)||~isfinite(alpha)||alpha<=0||alpha>=1
    error('cappedPathRisk:alpha','Failure probability alpha must be in (0,1).');
end
[R,H]=size(values);
weights=[(1-gamma)*gamma.^(0:H-2),gamma^(H-1)];
out.weights=weights;
out.pathMean=double(values)*weights';
out.mean=mean(out.pathMean);
out.independentPathCount=R;
out.alpha=alpha;
out.hoeffdingHalfWidth=sqrt(log(2/alpha)/(2*R));
out.cappedCI=[max(0,out.mean-out.hoeffdingHalfWidth),min(1,out.mean+out.hoeffdingHalfWidth)];
out.truncationBound=gamma^H;
out.infiniteHorizonCI=[max(0,out.cappedCI(1)-out.truncationBound),min(1,out.cappedCI(2)+out.truncationBound)];
out.scope='fixed bounded risk functional; independent path rows; fitted process conditional on initial state';
end
