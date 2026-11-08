classdef TestStorageCapacity < matlab.unittest.TestCase
    methods (Test)
        function initialMassAboveAvailableStoresIsRejected(tc)
            C=makeTestCase();
            cf=sum(C.ctx.capInv(C.idx.matOf(1:C.idx.nInv)==1));
            tc.verifyError(@()initMaterial(cf*1.01,1,C.ctx,'random',RandStream('twister','Seed',1)), ...
                'initMaterial:capacity');
        end
        function shippingReservesDestinationSpace(tc)
            C=makeTestCase(); ctx=C.ctx;
            e=find(C.topo.mat==1,1); src=C.idx.lineSrc(e); dst=C.idx.lineTgt(e);
            ctx.capInv(dst)=10;
            x=zeros(C.idx.n,1); x(src)=100;
            env=resetDirect(C,ctx,x);
            a=emptyAction(C.topo); a.f(e)=100;
            info=env.step(a);
            tc.verifyLessThanOrEqual(info.f(e),10+1e-8);
            tc.verifyEqual(sum(env.x),100,'AbsTol',1e-8);
        end
        function burnCannotOverflowRustStore(tc)
            C=makeTestCase(); ctx=C.ctx; ctx.capInv(C.idx.IOx(1))=5;
            x=zeros(C.idx.n,1); x(C.idx.IFe(1))=100;
            env=resetDirect(C,ctx,x);
            a=emptyAction(C.topo); a.burn(1)=50;
            info=env.step(a);
            tc.verifyLessThanOrEqual(env.x(C.idx.IOx(1)),5+1e-8);
            tc.verifyLessThanOrEqual(info.b(1),5/(1-C.p.plant.loss(1))+1e-8);
            tc.verifyEqual(sum(env.x),100,'AbsTol',1e-8);
        end
        function lossMakeupHasReservedSpace(tc)
            C=makeTestCase(); ctx=C.ctx;
            ctx.capInv(C.idx.SFe)=10;
            x=zeros(C.idx.n,1); x(C.idx.SFe)=10; x(C.idx.IFe(1))=100;
            env=resetDirect(C,ctx,x);
            a=emptyAction(C.topo); a.burn(1)=50;
            info=env.step(a);
            tc.verifyEqual(info.b(1),0,'AbsTol',1e-8);
            tc.verifyEqual(sum(env.x),sum(x),'AbsTol',1e-8);
        end
        function reductionAndMakeupShareIronSpace(tc)
            C=makeTestCase(); ctx=C.ctx;
            ctx.capInv(C.idx.SFe)=5;
            x=zeros(C.idx.n,1); x(C.idx.SOx)=100; x(C.idx.IFe(1))=100;
            env=resetDirect(C,ctx,x);
            a=emptyAction(C.topo); a.burn(1)=20; a.red(:)=10;
            info=env.step(a);
            tc.verifyEqual(info.b(1),20,'AbsTol',1e-8);
            tc.verifyLessThanOrEqual(info.rho+info.u,5+1e-8);
            tc.verifyEqual(sum(env.x),sum(x),'AbsTol',1e-8);
        end
        function initializationRedistributesWithoutLosingMaterial(tc)
            C=makeTestCase(); ctx=C.ctx; ctx.capInv(:)=10;
            cf=sum(ctx.capInv(C.idx.matOf(1:C.idx.nInv)==1));
            co=sum(ctx.capInv(C.idx.matOf(1:C.idx.nInv)==2));
            c=.9*(cf+co); soc=cf/(cf+co);
            [x,~,~]=initMaterial(c,soc,ctx,'random',RandStream('twister','Seed',8));
            tc.verifyEqual(sum(x),c,'AbsTol',1e-8);
            tc.verifyEqual(sum(x(C.idx.matOf==1)),soc*c,'AbsTol',1e-8);
            tc.verifyLessThanOrEqual(ctx.capacityMap*x,ctx.capInv+1e-8);
        end
        function rejectInvalidSuppliedInitialState(tc)
            C=makeTestCase(); ctx=C.ctx;
            x=zeros(C.idx.n,1); x(C.idx.IFe(1))=ctx.capInv(C.idx.IFe(1))+1;
            tc.verifyError(@()resetDirect(C,ctx,x),'IronRustEnv:storageCapacity');
        end
        function lpReservesSpaceForMakeup(tc)
            C=makeTestCase(); p=C.p; p.plant.pmin(:)=0; p.backup.pmax=0;
            T=buildInnerLPTemplate(p,C.ctx.grid);
            day=struct('RE',zeros(24,1),'D',ones(24,1)*10, ...
                'o',true(C.topo.nP,1),'bcap',ones(C.topo.nP,1)*1e4, ...
                'beta',zeros(C.topo.nP,1),'Ech',zeros(C.topo.nR,1), ...
                'redAvail',ones(C.topo.nR,1),'pLast',zeros(C.topo.nP,1), ...
                'etaEff',p.plant.etaSt,'carbon',0,'h2',0, ...
                'roomSFe',zeros(C.topo.nR,1),'eRedEff',C.ctx.eRedNom,'shareR',C.ctx.shareR);
            r=innerDispatchLP(T,day,p);
            tc.verifyEqual(sum(r.shed),240,'AbsTol',1e-6);
        end
        function mpcPlanMatchesDirectExecutionWithReservations(tc)
            C=makeTestCase(); ctx=C.ctx;
            ctx.capInv(:)=50;
            ctx.p.backup.pmax=0;
            [x,~,~]=initMaterial(.8*sum(ctx.capInv),.5,ctx,'deterministic',[]);
            env=resetDirect(C,ctx,x);
            mpc=mpcSetup(ctx,C.W,1,struct('S',1,'horizonFactor',1));
            [~,inf]=stochasticMPC(env.getObs(),ctx,mpc,RandStream('twister','Seed',3));
            a=emptyAction(C.topo);
            a.burn=inf.firstPlan.burn; a.red=inf.firstPlan.red; a.f=inf.firstPlan.f;
            env.step(a);
            tc.verifyLessThanOrEqual(inf.capacityExcess,1e-6);
            tc.verifyEqual(env.x,inf.firstPlan.x,'AbsTol',1e-6);
            tc.verifyLessThanOrEqual(ctx.capacityMap*env.x,ctx.capInv+1e-6);
        end
        function orderedShipmentsCannotBorrowLaterSpace(tc)
            C=makeTestCase(); ctx=C.ctx;
            e=find(C.topo.mat==1 & ismember(C.topo.to,C.topo.H),1);
            j=find(C.topo.mat==1 & C.topo.from==C.topo.to(e) & (1:C.topo.nE)'>e,1);
            tc.assertNotEmpty(j);
            src=C.idx.lineSrc(e); hub=C.idx.lineTgt(e);
            ctx.capInv(hub)=10;
            x=zeros(C.idx.n,1); x(src)=100; x(hub)=10;
            env=resetDirect(C,ctx,x);
            a=emptyAction(C.topo); a.f([e j])=10;
            inf=env.step(a);
            tc.verifyEqual(inf.f(e),0,'AbsTol',1e-8);
            tc.verifyEqual(inf.f(j),10,'AbsTol',1e-8);
            mpc=mpcSetup(ctx,C.W,1,struct('S',1,'horizonFactor',1));
            [A,b]=mpcCapacityBlock(ctx,mpc);
            plan=zeros(mpc.lay.nb,1);
            plan(mpc.lay.iX)=mpc.M.Mx*x+mpc.M.Mf*a.f;
            plan(mpc.lay.iF)=a.f;
            tc.verifyGreaterThan(max(A*plan-b),9.9);
        end
        function rustBlockRequiresFreeProductSpace(tc)
            C=makeTestCase(); ctx=C.ctx;
            ctx.capInv(C.idx.SFe)=10;
            x=zeros(C.idx.n,1); x(C.idx.SFe)=10;
            seg=buildSegment(C.W(1),10,3,C.p);
            seg.EW(:)=1e7; seg.ES(:)=0; seg.EL(:)=0;
            env=IronRustEnv(ctx);
            env.reset(1,sum(x),1,struct('seg',seg,'x0',x, ...
                'gInv0',ones(C.idx.nInv,1),'gLine0',ones(C.topo.nE,1)));
            a=emptyAction(C.topo); a.rho=C.p.station.rhoMax;
            inf=env.step(a);
            tc.verifyGreaterThan(inf.cur,0);
            tc.verifyEqual(inf.rustBlockMWh,0,'AbsTol',1e-8);
            tc.verifyFalse(inf.Bevent);
        end
    end
end
function env=resetDirect(C,ctx,x)
seg=buildSegment(C.W(1),10,3,C.p);
env=IronRustEnv(ctx);
env.reset(1,sum(x),.5,struct('seg',seg,'dispatchMode','direct','x0',x, ...
    'gInv0',ones(C.idx.nInv,1),'gLine0',ones(C.topo.nE,1)));
end
function a=emptyAction(t)
a=struct('o',false(t.nP,1),'bcap',zeros(t.nP,1),'beta',zeros(t.nP,1), ...
    'rho',zeros(t.nR,1),'f',zeros(t.nE,1),'burn',zeros(t.nP,1),'red',zeros(t.nR,1));
end
