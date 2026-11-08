classdef TestReferenceCalendar < matlab.unittest.TestCase
    methods(Test)
        function stateAfterYearBoundaryUsesItsActualSourceYear(tc)
            C=makeTestCase(); ctx=C.ctx; ctx.p.exp.warmup=1;
            W=[C.W,C.W]; W(1).sourceYearIndex=zeros(1,W(1).N);
            W(1).sourceYearIndex(365)=1; W(1).sourceYearIndex(366:end)=2;
            lib=policyLibrary(ctx.p,C.topo,C.stats,1); w=jointPolicy(lib,lib.alignedIds(:,1));
            st=sampleStates(ctx,W,lib,[1,2],1,w,C.cNominal,11);
            tc.verifyEqual(st.year,2);
            tc.verifyLessThanOrEqual(st.day,365);
            tc.verifyEqual(st.day,st.hs{1}.doy);
        end
    end
end
