classdef TestExactCTDFOperator < matlab.unittest.TestCase
    % Independent small laws catch weighting, timing and metric mistakes.
    methods (Test)
        function nonuniformWeightsAndDifferentSupports(tc)
            [d,c] = weightedW1([0,2],[.5,.5],[1,3],[.9,.1]);
            tc.verifyEqual(d,1,'AbsTol',1e-10);
            tc.verifyLessThan(c.marginalResidual,1e-9);
            tc.verifyGreaterThan(c.exitflag,0);
            tc.verifyEqual(weightedW1([0,2,99],[.5,.5,0],[1,3],[.9,.1]),1,'AbsTol',1e-10);
        end
        function multivariateWeightedDistance(tc)
            X=[1,0;0,1];
            tc.verifyEqual(weightedW1(X,[.7,.3],X,[.2,.8]),sqrt(2)/2,'AbsTol',1e-10);
            tc.verifyEqual(weightedW1(X,[.7,.3],X,[.7,.3]),0,'AbsTol',1e-10);
        end
        function invalidWeightsAreNotSilentlyNormalised(tc)
            tc.verifyError(@() weightedW1([0,1],[1,1],[0,1],[.5,.5]),'weightedW1:weights');
            tc.verifyError(@() weightedW1([0,1],[-.1,1.1],[0,1],[.5,.5]),'weightedW1:weights');
            tc.verifyError(@() weightedW1([0,NaN],[.5,.5],[0,1],[.5,.5]),'weightedW1:points');
        end
        function successorStartsAtNextState(tc)
            P=[0,1;1,0];
            [M,c]=exactSuccessorKernel(P,.5);
            tc.verifyEqual(M,[1,2;2,1]/3,'AbsTol',1e-12);
            tc.verifyEqual(M(1,:)*[-2;-5]/.5,-8,'AbsTol',1e-12);
            tc.verifyEqual(exactSuccessorKernel(P,0),P,'AbsTol',1e-14);
            tc.verifyLessThan(c.fixedPointResidual,1e-12);
        end
        function absorbingChainAndExactUpdate(tc)
            P=[.5,.5;0,1];
            M=exactSuccessorKernel(P,.5);
            tc.verifyEqual(M,[1/3,2/3;0,1],'AbsTol',1e-12);
            tc.verifyEqual(exactSuccessorUpdate(P,eye(2),0),P);
            tc.verifyEqual(exactSuccessorUpdate(P,M,.5),M,'AbsTol',1e-12);
            tc.verifyError(@() exactSuccessorKernel([1,1;0,1],.5),'exactSuccessorUpdate:transition');
            tc.verifyError(@() exactSuccessorKernel(P,1),'exactSuccessorUpdate:gamma');
        end
        function tightContractionHasFactorGamma(tc)
            P=eye(2); X=[1,0;0,1]; M=[1,0;1,0]; N=[0,1;0,1];
            A=exactSuccessorUpdate(P,M,.9); B=exactSuccessorUpdate(P,N,.9);
            for k=1:2
                tc.verifyEqual(weightedW1(X,A(k,:),X,B(k,:)),.9*sqrt(2),'AbsTol',1e-10);
            end
        end
        function riskBoundUsesWeightsAndCoordinateScale(tc)
            s=struct('G',[1,0],'b',0,'theta',.5,'coordinateScale',[2;1]);
            r=affineRiskBound([0;0],1,[.1;0],1,s);
            tc.verifyEqual(r.L,1,'AbsTol',1e-14);
            tc.verifyEqual(r.W1,.1,'AbsTol',1e-14);
            tc.verifyEqual(r.lhs,.5-1/(1+exp(.4)),'AbsTol',1e-14);
            tc.verifyTrue(r.pass);
            tc.verifyEqual(r.mcAllowance,0);
        end
        function riskBoundZeroRowsAndInvalidScale(tc)
            s=struct('G',zeros(1,2),'b',3,'theta',1);
            r=affineRiskBound([0;0],1,[10;10],1,s);
            tc.verifyEqual([r.lhs,r.rhs,r.L],[0,0,0]);
            s.theta=0;
            tc.verifyError(@() affineRiskBound([0;0],1,[10;10],1,s),'affineRiskBound:spec');
        end
        function finiteOperatorChecksPass(tc)
            r=checkExactOperator(struct('gammas',[0,.5,.99]));
            tc.verifyTrue(all(r.table.Pass));
            tc.verifyTrue(all(strcmp(r.table.CheckType,'exact_finite_operator')));
            tc.verifyGreaterThan(height(r.table),10);
            tc.verifyEqual(r.tightRatio(2),.5,'AbsTol',1e-10);
        end
    end
end
