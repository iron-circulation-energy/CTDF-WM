classdef TestRetirementAccounting < matlab.unittest.TestCase
    methods (Test)
        function historicalBookValueNeverChangesProspectiveSavings(tc)
            C = makeTestCase(); ctx = C.ctx;
            wx = {struct('RE', zeros(24,1), 'D', zeros(24,1), 'carbon', 100)};
            retro = struct('eueMWh',0,'opCost',0,'curMWh',0,'REMWh',1,'evalDays',365,'c',100);
            ctx.p.plant.bookValueFrac(:) = 0;
            a = retirementCounterfactual(ctx, wx, retro);
            ctx.p.plant.bookValueFrac(:) = 1;
            b = retirementCounterfactual(ctx, wx, retro);
            tc.verifyEqual(a.RV, b.RV, 'AbsTol', 1e-6);
            tc.verifyGreaterThan(b.detail.book, a.detail.book);
        end
        function recoverableIronIncursFinancingOnly(tc)
            C = makeTestCase(); ctx = C.ctx;
            wx = {struct('RE',zeros(24,1),'D',zeros(24,1),'carbon',100)};
            retro = struct('eueMWh',0,'opCost',0,'curMWh',0,'REMWh',1,'evalDays',365,'c',100);
            a = retirementCounterfactual(ctx, wx, retro);
            retro.c = 200;
            b = retirementCounterfactual(ctx, wx, retro);
            tc.verifyEqual(b.Aretro.capex - a.Aretro.capex, 18000, 'AbsTol', 1e-6); %100t*3000CNY/t*6%
        end
        function commonHorizonEndsBeforeAnyPlantRetires(tc)
            C = makeTestCase(); ctx = C.ctx;
            ctx.p.plant.remainLife(:) = 20; ctx.p.plant.remainLife(1) = 4;
            wx = {struct('RE',zeros(24,1),'D',zeros(24,1),'carbon',100)};
            retro = struct('eueMWh',0,'opCost',0,'curMWh',0,'REMWh',1,'evalDays',365,'c',100);
            a = retirementCounterfactual(ctx, wx, retro);
            tc.verifyEqual(a.detail.Nrem, 4);
        end
    end
end
