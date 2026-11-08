classdef TestTurnoverTiming < matlab.unittest.TestCase
    methods(Test)
        function defaultTimingContainsOnlyExecutedDelays(tc)
            p=params_default('smoke');
            tc.verifyEqual([p.loop.dwellPlant,p.loop.dwellStation,p.loop.tRed],[0 0 0]);
            Tl=computeTloop(buildTopology(p),p);
            tc.verifyEqual(Tl.perPlant,Tl.tauFe+Tl.tauOx);
            tc.verifyFalse(Tl.processApplied);
        end
        function hypotheticalDwellDoesNotChangeExecutedCycle(tc)
            p=params_default('smoke');
            p.loop.dwellPlant=1; p.loop.dwellStation=2; p.loop.tRed=3;
            topo=buildTopology(p);
            Tl=computeTloop(topo,p);
            tc.verifyEqual(Tl.perPlant,Tl.tauFe+Tl.tauOx);
            tc.verifyEqual(Tl.reference.perPlant,Tl.perPlant+6);
            tc.verifyEqual(Tl.H,ceil(Tl.mean));
            ctx=struct('p',p,'shareP',Tl.share,'Tl',Tl);
            stats=struct('Phi',10,'deltaD',2,'deltaU',3,'Dmax',2,'Umax',2,'Amean',15);
            fl=fluidParams(ctx,stats);
            tc.verifyEqual([fl.tP,fl.tR,fl.tRed],[0 0 0]);
        end
    end
end
