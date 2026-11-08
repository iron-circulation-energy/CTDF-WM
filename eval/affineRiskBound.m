function out = affineRiskBound(X, a, Y, b, spec, opts)
%AFFINERISKBOUND Deterministic KR inequality for two finite probability laws.
%   spec.G, spec.b define fixed margins in physical coordinates. Optional
%   coordinateScale/coordinateOffset declare S=scale.*X+offset. The same
%   fixed function is applied to both laws. No MC allowance is added.
if nargin<6, opts=struct(); end
D=size(X,1);
required={'G','b','theta'};
if ~isstruct(spec)||~all(isfield(spec,required))
    error('affineRiskBound:spec','Provide fixed G, b and a positive smoothing scale theta.');
end
G=double(spec.G); b0=double(spec.b(:)); th=spec.theta;
sc=getf(spec,'coordinateScale',ones(D,1)); sc=double(sc(:));
off=getf(spec,'coordinateOffset',zeros(D,1)); off=double(off(:));
if isempty(G)||size(G,2)~=D||size(G,1)~=numel(b0)||numel(sc)~=D||numel(off)~=D|| ...
        ~isreal(G)||~isreal(b0)||~isreal(sc)||~isreal(off)|| ...
        any(~isfinite([G(:);b0;sc;off]))||any(sc<=0)|| ...
        ~isnumeric(th)||~isreal(th)||~isscalar(th)||~isfinite(th)||th<=0
    error('affineRiskBound:spec','Fixed margins and coordinate transform must be finite and dimensionally valid.');
end
Gm=G.*sc'; bm=G*off+b0;
[d,cert]=weightedW1(X,a,Y,b,opts);
fx=1./(1+exp(min(Gm*double(X)+bm,[],1)/th));
fy=1./(1+exp(min(Gm*double(Y)+bm,[],1)/th));
out.expectationX=fx*(a(:)/sum(a));
out.expectationY=fy*(b(:)/sum(b));
out.lhs=abs(out.expectationX-out.expectationY);
out.L=max(vecnorm(Gm,2,2))/(4*th);
out.W1=d;
out.rhs=out.L*d;
out.slack=out.rhs-out.lhs;
out.tolerance=getf(opts,'atol',1e-10)+getf(opts,'rtol',1e-9)*max(out.rhs,out.lhs);
out.pass=out.lhs<=out.rhs+out.tolerance;
out.mcAllowance=0;
out.checkType='empirical_measure_identity';
out.metric='exact_weighted_w1_declared_coordinates';
out.transportCoupling=cert;
end

function v=getf(s,f,d)
if isfield(s,f)&&~isempty(s.(f)), v=s.(f); else, v=d; end
end
