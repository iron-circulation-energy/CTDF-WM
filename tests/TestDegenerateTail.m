classdef TestDegenerateTail < matlab.unittest.TestCase
    methods(Test)
        function unobservedExitDoesNotYieldFiniteRiskMass(tc)
            p=params_default('smoke');
            st=struct('Phi',10,'deltaD',2,'deltaU',3,'Dmax',4,'Umax',2,'qhat',1);
            cm=criticalMass(st,struct('mean',2),p);
            tc.verifyEqual(cm.M_eps,Inf);
            tc.verifyFalse(cm.finiteRiskCalibration);
            tc.verifyEqual(cm.PF([0 1e6]),[1 1]);
        end
        function infiniteBootstrapUpperBoundIsRetained(tc)
            tc.verifyEqual(quantileLin([1 2 Inf Inf],1),Inf);
            tc.verifyEqual(quantileLin([1 2 Inf Inf],0.975),Inf);
            tc.verifyEqual(quantileLin([1 2 Inf],0.5),2);
        end
        function absentTailObservationsAreNotAZeroRiskEstimate(tc)
            p=params_default('smoke');
            st=struct('Phi',10,'deltaD',2,'deltaU',3,'Dmax',4,'Umax',2, ...
                'qhat',0,'qhatIdentified',false);
            cm=criticalMass(st,struct('mean',2),p);
            tc.verifyTrue(isnan(cm.M_eps));
            tc.verifyFalse(cm.finiteRiskCalibration);
            tc.verifyTrue(all(isnan(cm.PF([0 1e6]))));
            tc.verifyTrue(isnan(cm.Meps(0.05)));
        end
        function unidentifiedBootstrapDrawsAreReported(tc)
            p=params_default('smoke');
            st=struct('Phi',10,'deltaD',2,'deltaU',3,'Dmax',4,'Umax',2,'qhat',0.5);
            st.bootRaw=table([10;10],[2;2],[3;3],[4;4],[2;2],[0.5;0],[true;false], ...
                'VariableNames',{'Phi','deltaD','deltaU','Dmax','Umax','qhat','qhatIdentified'});
            cm=criticalMass(st,struct('mean',2),p);
            tc.verifyEqual(cm.riskBootstrapIdentifiedFraction,0.5);
            tc.verifyTrue(all(isnan(cm.ci.M_eps)));
        end
    end
end
