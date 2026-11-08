classdef TestPhysicsCorrections < matlab.unittest.TestCase
    methods (Test)
        function ammoniaCannotReplaceAllIronAtPartLoad(tc)
            C = makeTestCase(); p = C.p;
            p.plant.pmin(:) = 0; p.backup.pmax = 0;
            T = buildInnerLPTemplate(p, C.ctx.grid);
            day = struct('RE', zeros(24,1), 'D', ones(24,1)*10, ...
                'o', true(C.topo.nP,1), 'bcap', zeros(C.topo.nP,1), ...
                'beta', ones(C.topo.nP,1)*0.2, 'Ech', zeros(C.topo.nR,1), ...
                'redAvail', ones(C.topo.nR,1), 'pLast', zeros(C.topo.nP,1), ...
                'etaEff', p.plant.etaSt, 'carbon', 0, 'h2', 0);
            a = innerDispatchLP(T, day, p);
            tc.verifyLessThanOrEqual(a.eNH3, 0.2*sum(a.p,2)+1e-7);
            tc.verifyEqual(sum(a.shed),240,'AbsTol',1e-6);
        end

        function auxiliaryEnergyIsPerTonne(tc)
            n = params_national();
            svc = struct('D',14,'hOut',1500,'hIn',2500);
            [~,~,eta] = natCost('fe',svc,0.15,n,100,2);
            tc.verifyEqual(eta,n.fe.hFe*n.fe.etaSt / ...
                (n.fe.hFe*n.fe.kappa/n.fe.etaEl+n.fe.eps),'RelTol',1e-12);
        end

        function rejectUnderbalancedReference(tc)
            tc.verifyError(@()natStorage([2 0], [1 1], .5, .5, 1), ...
                'natStorage:lambda');
        end

        function fixedServiceRejectsInsufficientCharging(tc)
            ref = natStorage([2 0], [1 1], .5, 1, 1);
            s = natRouteService(ref, .25);
            tc.verifyFalse(s.feasible);
            tc.verifyGreaterThan(s.energyShortfall,0);
            tc.verifyEqual(s.de,ref.de);
        end

        function fixedServiceClosesCycleAndPreservesDemand(tc)
            ref = natStorage([0 2 0 2], ones(1,4), .5, 1, 1);
            s = natRouteService(ref, .8);
            tc.verifyTrue(s.feasible);
            tc.verifyEqual(s.de,ref.de);
            tc.verifyEqual(s.Eout,ref.Eout,'AbsTol',1e-9);
            tc.verifyLessThanOrEqual(s.cycleResidual,1e-8);
            tc.verifyEqual(.8*sum(s.ch(:)),sum(ref.de(:)),'AbsTol',1e-8);
            tc.verifyLessThanOrEqual(s.ch,ref.chAvailable+1e-9);
        end
    end
end
