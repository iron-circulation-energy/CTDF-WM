classdef TestFrozenPlanMargins < matlab.unittest.TestCase
    methods(Test)
        function plannedShipmentArrivesOnlyAfterItsDelay(tc)
            C=makeTestCase(); ctx=C.ctx; e=find(C.topo.mat==1 & ismember(C.topo.to,C.topo.P),1);
            H=C.topo.tau(e)+1; pl=planFixture(ctx,H);
            pl.x0(ctx.idx.lineSrc(e))=10; pl.shipment(e,1)=4;
            spec=frozenPlanMargins(ctx,pl); S=zeros(ctx.L.D,1); S(1:ctx.idx.n)=pl.x0;
            [fe,ox]=computeMargins(S,ctx,spec);
            tc.verifyEqual(fe,spec.materialPath(ctx.idx.IFe,end)-ctx.safeFe,'AbsTol',1e-10);
            tc.verifyEqual(ox,spec.materialPath(ctx.idx.SOx,end)-ctx.safeOx,'AbsTol',1e-10);
            tc.verifyFalse(spec.hourlyDispatchVerified);
            pl.burn=pl.burn(:,1:H-1); pl.reduction=pl.reduction(:,1:H-1); pl.shipment=pl.shipment(:,1:H-1);
            early=frozenPlanMargins(ctx,pl); [before,~]=computeMargins(S,ctx,early);
            tc.verifyEqual(sum(fe-before),4,'AbsTol',1e-10);
        end
        function infeasiblePlansAreRejectedRatherThanClipped(tc)
            C=makeTestCase(); ctx=C.ctx; pl=planFixture(ctx,2);
            pl.shipment(1,1)=1;
            tc.verifyError(@() frozenPlanMargins(ctx,pl),'frozenPlanMargins:infeasible');
            pl=planFixture(ctx,2); pl.burn(1,1)=1;
            tc.verifyError(@() frozenPlanMargins(ctx,pl),'frozenPlanMargins:infeasible');
            pl=planFixture(ctx,2); e=1;
            pl.x0(ctx.idx.lineSrc(e))=2; pl.x0(ctx.idx.lineTgt(e))=ctx.capInv(ctx.idx.lineTgt(e));
            pl.shipment(e,1)=1;
            tc.verifyError(@() frozenPlanMargins(ctx,pl),'frozenPlanMargins:infeasible');
        end
        function fixedPlanMarginsAreAffine(tc)
            C=makeTestCase(); ctx=C.ctx; pl=planFixture(ctx,2);
            pl.x0(ctx.idx.IFe(1))=5; pl.burn(1,1)=2;
            spec=frozenPlanMargins(ctx,pl); S=zeros(ctx.L.D,2);
            S(1:ctx.idx.n,1)=pl.x0; S(1:ctx.idx.n,2)=2*pl.x0;
            [a,~]=computeMargins(S,ctx,spec);
            [b,~]=computeMargins(mean(S,2),ctx,spec);
            tc.verifyEqual(b,mean(a,2),'AbsTol',1e-10);
            tc.verifyEqual(spec.validationScope,'anchor_material_plan_only');
            tc.verifyEqual(sum(spec.materialPath(:,end)),sum(pl.x0),'AbsTol',1e-10);
        end
        function replayMatchesExecutedMaterialEveryDayWithLossAndPipelines(tc)
            C=makeTestCase(); ctx=C.ctx;
            ctx.p.plant.loss(:)=.1; % Make loss replacement observable.
            e=find(C.topo.mat==1 & ismember(C.topo.to,C.topo.P),1);
            i=find(C.topo.P==C.topo.to(e),1);
            H=C.topo.tau(e)+2;
            pl=planFixture(ctx,H);
            pl.x0(ctx.idx.IFe(i))=10;
            pl.x0(ctx.idx.lineSrc(e))=10;
            pl.x0(ctx.idx.SOx(1))=10;
            pl.x0(ctx.idx.qFirst(e))=2; % Arrives before first-day burning.
            pl.burn(i,1:2)=[3,2];
            pl.reduction(1,1:2)=[2,1];
            pl.shipment(e,1)=4;         % Arrives only after its line delay.
            spec=frozenPlanMargins(ctx,pl);
            env=IronRustEnv(ctx);
            seg=buildSegment(C.W(1),1,H+1,ctx.p);
            env.reset(4,sum(pl.x0),.5,struct('seg',seg,'dispatchMode','direct', ...
                'x0',pl.x0,'gInv0',ones(ctx.idx.nInv,1),'gLine0',ones(ctx.topo.nE,1)));
            for d=1:H
                a=struct('burn',pl.burn(:,d),'red',pl.reduction(:,d), ...
                    'rho',pl.reduction(:,d),'f',pl.shipment(:,d));
                info=env.step(a);
                tc.verifyEqual(info.b,pl.burn(:,d),'AbsTol',1e-12);
                tc.verifyEqual(info.rho,pl.reduction(:,d),'AbsTol',1e-12);
                tc.verifyEqual(info.f,pl.shipment(:,d),'AbsTol',1e-12);
                tc.verifyEqual(env.x,spec.materialPath(:,d+1),'AbsTol',1e-10);
            end
            tc.verifyEqual(env.x(ctx.idx.IFe(i)),11,'AbsTol',1e-12); % 10+2+4-3-2
            tc.verifyEqual(env.x(ctx.idx.IOx(i)),4.5,'AbsTol',1e-12);
            tc.verifyEqual(sum(env.x(ctx.idx.SFe)),3.5,'AbsTol',1e-12); % reduction 3 + replacement .5
            tc.verifyEqual(env.x(ctx.idx.V),0,'AbsTol',1e-12);
        end
    end
end
function pl=planFixture(ctx,H)
pl=struct('x0',zeros(ctx.idx.n,1),'burn',zeros(ctx.topo.nP,H), ...
    'reduction',zeros(ctx.topo.nR,H),'shipment',zeros(ctx.topo.nE,H),'forecastId','test-fixed');
end
