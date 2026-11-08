classdef TestEventRiskDomain < matlab.unittest.TestCase
    methods (Test)
        function nondecayingTailIsRejectedBeforeGridAllocation(tc)
            C=makeTestCase(); st=C.stats; st.qhat=1; st.qhatIdentified=true;
            tc.verifyError(@()checkEventRisk(C.ctx,st,C.cm,20,1), ...
                'checkEventRisk:nondecayingTail');
        end
        function unidentifiedTailCannotBeReportedAsVerified(tc)
            C=makeTestCase(); st=C.stats; st.qhat=0; st.qhatIdentified=false;
            tc.verifyError(@()checkEventRisk(C.ctx,st,C.cm,20,1), ...
                'checkEventRisk:unidentifiedTail');
        end
        function zeroDepletionIsOutsideGeometricThresholdDomain(tc)
            C=makeTestCase(); st=C.stats; st.deltaD=0;
            tc.verifyError(@()checkEventRisk(C.ctx,st,C.cm,20,1), ...
                'checkEventRisk:noDepletion');
        end
        function zeroContinuationProbabilityIsAOneDayEvent(tc)
            C=makeTestCase(); st=C.stats; st.qhat=0; st.qhatIdentified=true;
            cm=criticalMass(st,C.Tl,C.p);
            out=checkEventRisk(C.ctx,st,cm,20,1);
            tc.verifyTrue(all(isfinite(out.table.c)));
            tc.verifyEqual(out.table.Ptheory,[1;0;0;0]);
            tc.verifyEqual(out.table.Pemp,[1;0;0;0]);
            tc.verifyEqual(out.slopeTheory,-Inf);
        end
    end
end
