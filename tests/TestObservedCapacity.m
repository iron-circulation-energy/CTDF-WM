classdef TestObservedCapacity < matlab.unittest.TestCase
    methods(Test)
        function currentConstraintsArePartOfTheConditioningState(tc)
            C=makeTestCase();
            seg=buildSegment(C.W(1),20,4,C.p);
            a=IronRustEnv(C.ctx); b=IronRustEnv(C.ctx);
            a.reset(1,C.cNominal,.6,struct('seg',seg));
            cap=a.capSched;
            cap.Fcap(1,1)=0; cap.rhoAvail(1,1)=.25;
            b.reset(1,C.cNominal,.6,struct('seg',seg,'capSched',cap));
            tc.verifyNotEqual(a.stateVector(),b.stateVector());
            sa=a.stateVector(); sb=b.stateVector();
            tc.verifyEqual(sa(C.ctx.L.xi.Fcap(1)),1);
            tc.verifyEqual(sb(C.ctx.L.xi.Fcap(1)),0);
            tc.verifyEqual(sb(C.ctx.L.xi.rhoAvail(1)),.25);
        end
        function futureOutageScheduleDoesNotLeakIntoCurrentState(tc)
            C=makeTestCase();
            seg=buildSegment(C.W(1),20,4,C.p);
            a=IronRustEnv(C.ctx); b=IronRustEnv(C.ctx);
            a.reset(1,C.cNominal,.6,struct('seg',seg));
            cap=a.capSched; cap.Fcap(:,2:end)=0; cap.rhoAvail(:,2:end)=0;
            b.reset(1,C.cNominal,.6,struct('seg',seg,'capSched',cap));
            tc.verifyEqual(a.stateVector(),b.stateVector());
            tc.verifyEqual(a.getObs().s,b.getObs().s);
        end
    end
end
