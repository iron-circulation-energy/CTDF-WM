function spec = frozenPlanMargins(ctx, plan)
%FROZENPLANMARGINS Fixed-plan affine inventory margins with an anchor replay.
% plan.x0, burn(nP,H), reduction(nR,H), shipment(nE,H) specify ACTUAL material
% quantities, not dispatch requests. Optional Fcap/rhoAvail are fixed schedules.
% The plan is replayed without clipping in the environment's event order:
% arrivals, conversions and loss replacement, ordered shipments, pipe shift.
% Day-d shipments arrive on day d+tau; initial q_1 arrives on day 1.
% Anchor replay checks material feasibility of the plan from x0; the burn bound is a nominal daily limit.
p=ctx.p; t=ctx.topo; ix=ctx.idx; H=size(plan.burn,2);
validateattributes(H,{'numeric'},{'scalar','integer','positive'});
checkArray(plan.x0,[ix.n,1]); checkArray(plan.burn,[t.nP,H]);
checkArray(plan.reduction,[t.nR,H]); checkArray(plan.shipment,[t.nE,H]);
F=getf(plan,'Fcap',repmat(t.Fcap(:),1,H));
ra=getf(plan,'rhoAvail',ones(t.nR,H));
checkArray(F,[t.nE,H]); checkArray(ra,[t.nR,H]);
if any(F>t.Fcap(:)+1e-9,'all') || any(ra>1,'all')
    error('frozenPlanMargins:infeasible','Capacity schedule exceeds nominal installed capability.');
end
x=double(plan.x0); mass=sum(x); tol=1e-9*max(1,mass);
if any(ctx.capacityMap*x>ctx.capInv+tol)
    error('frozenPlanMargins:infeasible','Initial inventory plus inbound reservation exceeds storage.');
end
path=zeros(ix.n,H+1); path(:,1)=x;
for d=1:H
    for e=1:t.nE
        x(ix.lineTgt(e))=x(ix.lineTgt(e))+x(ix.qFirst(e)); x(ix.qFirst(e))=0;
    end
    b=plan.burn(:,d); r=plan.reduction(:,d);
    loss=sum(p.plant.loss(:).*b); room=ctx.capInv-ctx.capacityMap*x;
    valid=all(b<=x(ix.IFe)+tol) && all(r<=x(ix.SOx)+tol) && ...
        all(b.*(1-p.plant.loss(:))<=room(ix.IOx)+tol) && ...
        all(r+ctx.shareR*loss<=room(ix.SFe)+tol) && ...
        all(r<=p.station.rhoMax(:).*ra(:,d)+tol) && ...
        all(b<=24*p.plant.pmax(:)./(ctx.etaNom*p.iron.hFe)+tol);
    if ~valid, error('frozenPlanMargins:infeasible','Infeasible conversion on day %d.',d); end
    x(ix.IFe)=x(ix.IFe)-b; x(ix.IOx)=x(ix.IOx)+(1-p.plant.loss(:)).*b;
    x(ix.SOx)=x(ix.SOx)-r; x(ix.SFe)=x(ix.SFe)+r+ctx.shareR*loss;
    reserved=ctx.capacityMap*x;
    for e=1:t.nE
        src=ix.lineSrc(e); dst=ix.lineTgt(e); f=plan.shipment(e,d);
        if f>min([F(e,d),x(src),ctx.capInv(dst)-reserved(dst)])+tol
            error('frozenPlanMargins:infeasible','Infeasible shipment on day %d, edge %d.',d,e);
        end
        x(src)=x(src)-f; reserved(src)=reserved(src)-f; reserved(dst)=reserved(dst)+f;
    end
    for e=1:t.nE
        q=ix.q{e}; x(q(1:end-1))=x(q(2:end)); x(q(end))=plan.shipment(e,d);
    end
    if any(x<-tol) || abs(sum(x)-mass)>tol || any(ctx.capacityMap*x>ctx.capInv+tol)
        error('frozenPlanMargins:infeasible','Material invariant failed on day %d.',d);
    end
    path(:,d+1)=x;
end
GFe=zeros(t.nP,ctx.L.D); GOx=zeros(t.nR,ctx.L.D);
for i=1:t.nP
    GFe(i,ix.IFe(i))=1;
    for e=ctx.inFe{t.P(i)}, GFe(i,ix.q{e}(1:min(H,t.tau(e))))=1; end
end
for j=1:t.nR
    GOx(j,ix.SOx(j))=1;
    for e=ctx.inOx{t.R(j)}, GOx(j,ix.q{e}(1:min(H,t.tau(e))))=1; end
end
% Offset from the replay includes only the frozen plan (new arrivals,
% conversions and any sink-node outbound shipments). No future actual data.
s0=zeros(ctx.L.D,1); s0(1:ix.n)=plan.x0;
spec=struct('kind','frozen_material_plan','H',H,'GFe',sparse(GFe),'GOx',sparse(GOx), ...
    'gFe0',path(ix.IFe,end)-ctx.safeFe-GFe*s0, ...
    'gOx0',path(ix.SOx,end)-ctx.safeOx-GOx*s0, ...
    'plan',plan,'materialPath',path,'anchorMass',mass, ...
    'forecastId',getf(plan,'forecastId','unspecified'), ...
    'validationScope','anchor_material_plan_only','hourlyDispatchVerified',false, ...
    'sampledStateFeasibilityVerified',false);
end
function checkArray(x,sz)
if ~isnumeric(x) || ~isreal(x) || ~isequal(size(x),sz) || any(~isfinite(x)|x<0,'all')
    error('frozenPlanMargins:input','Expected finite nonnegative array of size %s.',mat2str(sz));
end
end
function v=getf(s,f,d)
if isfield(s,f)&&~isempty(s.(f)), v=s.(f); else, v=d; end
end
