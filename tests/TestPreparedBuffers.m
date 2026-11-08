classdef TestPreparedBuffers < matlab.unittest.TestCase
    % Fixed process/safety allocations cannot be lent to event buffers.
    methods (Test)
        function specifiedReserveControlsGeometricThreshold(tc)
            % Catches using the old 20 t pipeline instead of the declared 70 t reserve.
            [ctx, st, cm] = bufferFixture();
            out = checkEventRisk(ctx, st, cm, 100, 13);
            tc.verifyEqual(out.thresholdMatch, 1);
        end

        function formulaAndConstructionShareTheSameReserve(tc)
            [ctx, st, cm] = bufferFixture();
            tc.assertTrue(isfield(cm, 'bufferSpec'), 'criticalMass must return the shared specification.');
            tc.verifyEqual(cm.M_LL, 20);
            tc.verifyEqual(cm.M_occ, 70);
            tc.verifyEqual(cm.M_0, 83);
            tc.verifyEqual(cm.M_crit, 104);
            out = checkCriticalMass(ctx, st, cm);
            tc.verifyEqual(out.Mcrit, 104);
            tc.verifyEqual(out.bufferSpec.M_occ, 70);
            tc.verifyTrue(out.summary.aPass);
            tc.verifyTrue(out.summary.bPass);
            sel = startsWith(out.table.Case, '(a)');
            tc.verifyEqual(out.table.InitialFreeFe(sel), [21; 21]);
            tc.verifyEqual(out.table.InitialFreeOx(sel), [8; 8]);
        end

        function samePreparationSurvivesEitherIsolatedWorstEvent(tc)
            spec = fixtureSpec(tc);
            a = preparedBufferSim(104, spec, 'DDD');
            b = preparedBufferSim(104, spec, 'UU');
            tc.verifyEqual(a.initialFree, [21, 8]);
            tc.verifyEqual(b.initialFree, [21, 8]);
            tc.verifyEqual([a.violFe, a.violOx, b.violFe, b.violOx], [0, 0, 0, 0]);
            tc.verifyEqual(a.traceFree(end,:), [0, 29]);
            tc.verifyEqual(b.traceFree(end,:), [29, 0]);
            tc.verifyEqual(a.traceReserve, 70*ones(4,1));
            tc.verifyEqual(a.traceSafety, 5*ones(4,1));
            tc.verifyLessThanOrEqual(a.consErr, 1e-12);
        end

        function missingIronOrRustCannotBeReplacedByProcessReserve(tc)
            spec = fixtureSpec(tc);
            a = preparedBufferSim(104, spec, 'D', struct('initialFree',[0,29]));
            b = preparedBufferSim(104, spec, 'U', struct('initialFree',[29,0]));
            tc.verifyEqual(a.shortFe, 7);
            tc.verifyEqual(b.shortOx, 4);
            tc.verifyEqual(a.traceReserve, [70;70]);
            tc.verifyEqual(b.traceSafety, [5;5]);
            tc.verifyFalse(a.eventPrepared(1));
            tc.verifyFalse(b.eventPrepared(1));
        end

        function belowThresholdFailsAnAttainableEventFromSamePreparation(tc)
            spec = fixtureSpec(tc);
            a = preparedBufferSim(103, spec, 'DDD');
            b = preparedBufferSim(103, spec, 'UU');
            tc.verifyEqual(a.initialFree, b.initialFree);
            tc.verifyGreaterThan(a.violFe+b.violOx, 0);
            % This allocation covers D exactly, forcing the missing tonne to fail U.
            d = preparedBufferSim(103, spec, 'DDD', struct('initialFree',[21,7]));
            u = preparedBufferSim(103, spec, 'UU', struct('initialFree',[21,7]));
            tc.verifyEqual(d.violFe, 0);
            tc.verifyEqual(sum(u.shortOx), 1);
        end

        function normalDaysDoNotRestoreWithoutExplicitCapacity(tc)
            spec = fixtureSpec(tc);
            out = preparedBufferSim(104, spec, 'DDDNDDD');
            tc.verifyEqual(out.eventStartDays, [1;5]);
            tc.verifyEqual(out.eventPrepared, [true;false]);
            tc.verifyEqual(out.traceFree(5,:), [0,29]);
            tc.verifyEqual(sum(out.shortFe), 21);
            tc.verifyFalse(out.restored);
            tc.verifyEqual(out.recoveryRateT, 0);
        end

        function explicitRecoveryRespectsItsRateAndBothTargets(tc)
            spec = fixtureSpec(tc);
            slow = preparedBufferSim(104, spec, 'DDDNDDD', struct('recoveryRateT',7));
            full = preparedBufferSim(104, spec, 'DDDNNNDDD', struct('recoveryRateT',7));
            tc.verifyEqual(slow.eventPrepared, [true;false]);
            tc.verifyEqual(sum(slow.shortFe), 14);
            tc.verifyEqual(full.eventPrepared, [true;true]);
            tc.verifyEqual(full.violFe, 0);
            tc.verifyEqual(full.traceFree(7,:), [21,8]);
            tc.verifyLessThanOrEqual(full.consErr, 1e-12);
        end

        function safetyAndProcessMassCannotBeNegativeOrDoubleAllocated(tc)
            spec = fixtureSpec(tc);
            out = preparedBufferSim(74, spec, 'D');
            tc.verifyFalse(out.allocationFeasible);
            tc.verifyEqual(out.violBase, 1);
            tc.verifyEqual(out.baseShortfallT, 1);
            tc.verifyError(@()preparedBufferSim(104,spec,'D',struct('initialFree',[21,9])), ...
                'preparedBufferSim:allocationMass');
        end

        function empiricalQuantilesStayEnvelopes(tc)
            [ctx, st] = bufferFixture();
            ctx.p.stats.deltaQuantile = 0.95;
            cm = criticalMass(st,ctx.Tl,ctx.p);
            tc.assertTrue(isfield(cm,'bufferSpec'));
            tc.verifyEqual(cm.bufferSpec.boundKind,'empirical_quantile');
            tc.verifyFalse(cm.designExact);
            tc.verifyFalse(cm.bufferSpec.networkExact);
            ctx.p.stats = rmfield(ctx.p.stats,'processReserveT');
            ref = criticalMass(st,ctx.Tl,ctx.p);
            tc.verifyTrue(ref.bufferSpec.referenceOnly);
            tc.verifyEqual(ref.bufferSpec.M_occ,20);
        end

        function zeroDrawsPreserveAnEmptyFreeBuffer(tc)
            [ctx, st] = bufferFixture();
            st.deltaD = 0; st.deltaU = 0;
            cm = criticalMass(st,ctx.Tl,ctx.p);
            tc.assertTrue(isfield(cm,'bufferSpec'));
            out = preparedBufferSim(75,cm.bufferSpec,'DUNN');
            tc.verifyEqual(out.initialFree,[0,0]);
            tc.verifyEqual([out.violFe,out.violOx], [0,0]);
            tc.verifyTrue(out.restored);
            tc.verifyEqual(cm.M_eps,75);
        end

        function bufferRejectsAStaleFormulaRatherThanChangingThreshold(tc)
            [ctx, st, cm] = bufferFixture();
            tc.assertTrue(isfield(cm,'bufferSpec'));
            cm.M_crit = cm.M_crit + 1;
            tc.verifyError(@()checkCriticalMass(ctx,st,cm),'bufferSpec:massMismatch');
        end
    end
end

function [ctx, st, cm] = bufferFixture()
p.plant.safetyFe = 2;
p.station.safetyOx = 3;
p.stats = struct('epsRisk',.2,'processReserveT',70,'deltaQuantile',1,'dQuantile',1);
p.exp.bufferEta = [.01,.1];
p.exp.networkEventGap = 1;
st = struct('Phi',10,'deltaD',7,'deltaU',4,'Dmax',3,'Umax',2,'qhat',.5,'Amean',12);
Tl = struct('mean',2,'max',2,'tauFe',1,'tauOx',1);
ctx = struct('p',p,'Tl',Tl,'shareP',1);
cm = criticalMass(st,Tl,p);
end

function spec = fixtureSpec(tc)
[~,~,cm] = bufferFixture();
tc.assertTrue(isfield(cm,'bufferSpec'),'The prepared-buffer simulator needs a shared specification.');
spec = cm.bufferSpec;
end
