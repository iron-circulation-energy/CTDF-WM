classdef TestMPCExecution < matlab.unittest.TestCase
    methods (Test)
        function partLoadBlendPlanExecutesWithoutArtificialShedding(tc)
            [env,ctx,mpc] = lowLoadCase(240);
            [a,plan] = stochasticMPC(env.getObs(),ctx,mpc,RandStream('twister','Seed',3));
            plannedIronMWh = sum(plan.firstPlan.burn.*ctx.p.plant.etaSt*ctx.p.iron.hFe);
            tc.assertEqual(plannedIronMWh,192,'AbsTol',1e-6);
            out = env.step(a);
            tc.verifyEqual(out.nh3MWh,48,'AbsTol',1e-6);
            tc.verifyEqual(out.shed,0,'AbsTol',1e-6);
            tc.verifyEqual(out.ironMWh,plannedIronMWh,'AbsTol',1e-6);
        end
        function idlePlanHasFiniteZeroBlend(tc)
            [env,ctx,mpc] = lowLoadCase(0);
            a = stochasticMPC(env.getObs(),ctx,mpc,RandStream('twister','Seed',3));
            tc.verifyEqual(a.beta,zeros(ctx.topo.nP,1));
            out = env.step(a);
            tc.verifyEqual(out.shed,0,'AbsTol',1e-6);
        end
    end
end

function [env,ctx,mpc] = lowLoadCase(loadMWh)
C=makeTestCase(); ctx=C.ctx; p=ctx.p;
p.plant.pmin(:)=0; p.plant.cop(:)=0; p.plant.betaMax(:)=.2;
p.backup.pmax=0; p.cost.nh3Base=0; p.cost.nh3PerH2=0;
p.cost.cMk=10000; p.mpc.terminalFrac=0; p.mpc.burnSlack=0;
p.aging.enable=false; ctx.p=p; ctx.lpT=buildInnerLPTemplate(p,ctx.grid);
x=zeros(ctx.idx.n,1); x(ctx.idx.IFe)=10000;
seg=buildSegment(C.W(1),10,3,p);
seg.EW(:)=0; seg.ES(:)=0; seg.EL(:)=loadMWh; seg.carbon=0; seg.h2=0;
seg.F.EW(:)=0; seg.F.ES(:)=0; seg.F.EL(:)=loadMWh;
env=IronRustEnv(ctx);
env.reset(1,sum(x),1,struct('seg',seg,'x0',x, ...
    'gInv0',ones(ctx.idx.nInv,1),'gLine0',ones(ctx.topo.nE,1)));
mpc=mpcSetup(ctx,C.W,1,struct('S',1,'horizonFactor',1));
% Isolate the first-day plan/action contract from future rust requirements.
mpc.Hm=1; mpc.Hf=0;
end
