classdef TestPaperDefinitions < matlab.unittest.TestCase
    methods (Test)
        function riskMassMeetsIntegerTailTolerance(tc)
            p.plant.safetyFe = 2; p.station.safetyOx = 3;
            p.stats.epsRisk = 0.2;
            s = struct('Phi', 10, 'deltaD', 7, 'deltaU', 4, 'Dmax', 3, 'Umax', 2, 'qhat', 0.5);
            cm = criticalMass(s, struct('mean', 2), p);
            tc.verifyEqual(cm.M_eps, 54); % reserve20 + rust8 + safety5 + 3 daily buffers of7
            tc.verifyLessThanOrEqual(cm.PF(cm.M_eps), 0.2);
        end
        function turnoverAverageIsReferenceReserve(tc)
            p.plant.safetyFe = 2; p.station.safetyOx = 3; p.stats.epsRisk = 0.2;
            s = struct('Phi', 10, 'deltaD', 7, 'deltaU', 4, 'Dmax', 3, 'Umax', 2, 'qhat', 0.5);
            cm = criticalMass(s, struct('mean', 2), p);
            tc.verifyTrue(isfield(cm, 'referenceOnly'));
            if isfield(cm, 'referenceOnly'), tc.verifyTrue(cm.referenceOnly); end
            p.stats.processReserveT = 70;
            cm = criticalMass(s, struct('mean', 2), p);
            tc.verifyEqual(cm.M_crit, 104);
        end
        function oneDayGeometricTailHasFiniteRiskMass(tc)
            p.plant.safetyFe = 2; p.station.safetyOx = 3; p.stats.epsRisk = 0.2;
            s = struct('Phi',10,'deltaD',7,'deltaU',4,'Dmax',1,'Umax',2,'qhat',0);
            cm = criticalMass(s, struct('mean',2), p);
            tc.verifyEqual(cm.M_eps, 40);
            tc.verifyEqual(cm.PF(cm.M_eps), 0);
            tc.verifyEqual(cm.PF(cm.M_eps - 1), 1);
        end
        function noCrossSplitTrainingWindows(tc)
            p.weather.daysPerYear = 5;
            w.N = 8; w.year = 1; w.sourceYearIndex = [1 1 1 1 1 2 2 2];
            tc.verifyEqual(validWeatherStarts(w, p, 3, 1), 1:3);
            tc.verifyEqual(validWeatherStarts(w, p, 3, [1 2]), 1:5);
        end
        function evaluationDaysRemainInDeclaredYear(tc)
            C = makeTestCase(); p = C.p;
            p.exp.evalDays = 365; p.exp.warmup = 30;
            sp = makeEvalSpecs(p, 1, 1, {'normal'}, C.cNominal);
            ctx = C.ctx; ctx.p = p;
            [seg, ~] = buildEvalSegment(ctx, C.W, sp);
            tc.verifyEqual(seg.EW(31:395), C.W(1).EW(1:365));
            tc.verifyEqual(seg.doy(31:395), 1:365);
        end
        function realisedIronShortageDoesNotCountSafetyOrPowerShortage(tc)
            ctx.p.plant.safetyFe = [10; 10]; ctx.p.iron.hFe = 2;
            ctx.shareP = [0.5; 0.5];
            obs.fc.must = 40;
            info.availableFe = [12; 12]; info.etaEff = [1; 1]; info.nh3ByPlant = [0; 0]; info.shed = 100;
            r = realizedIronShortfall(obs, info, ctx);
            tc.verifyEqual(r.shortfallT, [0; 0]);
            tc.verifyEqual(r.safetyShortfallT, [8; 8]);
            info.availableFe = [6; 12];
            r = realizedIronShortfall(obs, info, ctx);
            tc.verifyEqual(r.shortfallT, [4; 0]);
        end
    end
end
