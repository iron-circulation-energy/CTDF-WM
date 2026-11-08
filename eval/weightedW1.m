function [d, cert] = weightedW1(X, a, Y, b, opts)
%WEIGHTEDW1 Euclidean W1 of two finite probability laws by a transport LP.
%   Columns are atoms; a and b are their probabilities, not sample counts.
%   This is an exact finite transport problem solved to numerical tolerance,
%   not a sliced distance or an estimate of a population transport distance.
if nargin < 5, opts=struct(); end
wt=getf(opts,'weightTolerance',1e-10);
ft=getf(opts,'feasibilityTolerance',1e-8);
if ~isnumeric(X)||~isnumeric(Y)||~isreal(X)||~isreal(Y)||isempty(X)||isempty(Y)|| ...
        size(X,1)~=size(Y,1)||any(~isfinite(X(:)))||any(~isfinite(Y(:)))
    error('weightedW1:points','Atoms must be finite real matrices with the same nonzero dimension.');
end
if ~isscalar(wt)||~isfinite(wt)||wt<=0||~isscalar(ft)||~isfinite(ft)||ft<=0
    error('weightedW1:tolerance','Tolerances must be positive finite scalars.');
end
a=double(a(:)); b=double(b(:));
if numel(a)~=size(X,2)||numel(b)~=size(Y,2)||~isreal(a)||~isreal(b)|| ...
        any(~isfinite([a;b]))||any([a;b]<0)||abs(sum(a)-1)>wt||abs(sum(b)-1)>wt
    error('weightedW1:weights','Weights must be nonnegative finite probabilities summing to one.');
end
cert.weightNormalisation=[sum(a)-1,sum(b)-1];
a=a/sum(a); b=b/sum(b);
ia=a>0; ib=b>0;
X=double(X(:,ia)); Y=double(Y(:,ib)); a=a(ia); b=b(ib);
nx=numel(a); ny=numel(b);
C=zeros(nx,ny);
for k=1:size(X,1), C=hypot(C,X(k,:)'-Y(k,:)); end
if any(~isfinite(C(:)))
    error('weightedW1:distance','Atom distances overflow; use an explicitly declared finite metric scale.');
end
costScale=max(1,max(C(:)));
Aeq=[kron(ones(1,ny),speye(nx));kron(speye(ny),ones(1,nx))];
beq=[a;b];
op=optimoptions('linprog','Display','none');
[pi,~,flag,out]=linprog(C(:)/costScale,[],[],Aeq,beq,zeros(nx*ny,1),[],op);
if flag<=0||isempty(pi)||any(~isfinite(pi))
    error('weightedW1:solver','Transport LP failed (exitflag %g).',flag);
end
res=max(abs(Aeq*pi-beq));
if res>ft||min(pi)<-ft
    error('weightedW1:feasibility','Transport solution violates probability constraints.');
end
d=max(0,C(:)'*pi);
cert.method='exact_weighted_w1';
cert.exitflag=flag;
cert.marginalResidual=res;
cert.minimumTransportMass=min(pi);
cert.costScale=costScale;
cert.solverOutput=out;
cert.nAtoms=[nx,ny];
if getf(opts,'keepCoupling',false), cert.coupling=reshape(pi,nx,ny); end
end

function v=getf(s,f,d)
if isfield(s,f)&&~isempty(s.(f)), v=s.(f); else, v=d; end
end
