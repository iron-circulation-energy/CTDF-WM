classdef TestResearchProtocol < matlab.unittest.TestCase
    methods(Test)
        function missingMetricYearsAreNotCountedAsEffectiveClusters(tc)
            T=table((2020:2022)',[NaN;2;4],repmat({'M1'},3,1), ...
                'VariableNames',{'year','lead','method'});
            S=statsUtils('summaryTable',T,{'method'},{'lead'});
            tc.verifyEqual(S.nYears,3);
            tc.verifyEqual(S.lead_nYears,2);
        end
        function noObservedEventsDoNotCrashPairedSummary(tc)
            [pv,dm,n,lo,hi]=statsUtils('clusterPaired',NaN,NaN,2020);
            tc.verifyEqual(n,0);
            tc.verifyTrue(all(isnan([pv dm lo hi])));
        end
        function noEventsOrFlatCurveHasNoIdentifiableKnee(tc)
            for y={[NaN NaN NaN NaN],[0 0 0 0]}
                tc.verifyTrue(isnan(statsUtils('knee2seg',1:4,y{1})));
                tc.verifyTrue(isnan(statsUtils('kneeCurv',1:4,y{1})));
            end
        end
        function duplicatedSeedsDoNotNarrowYearCI(tc)
            y = (2020:2024)'; x = [1; 4; 2; 8; 10];
            T = table(y,x,repmat({'M1'},5,1),'VariableNames',{'year','cost','method'});
            A = statsUtils('summaryTable',T,{'method'},{'cost'});
            B = statsUtils('summaryTable',repmat(T,3,1),{'method'},{'cost'});
            tc.verifyEqual(A.cost_lo,B.cost_lo,'AbsTol',1e-12);
            tc.verifyEqual(A.cost_hi,B.cost_hi,'AbsTol',1e-12);
            tc.verifyEqual(B.nYears,5);
        end
        function singleYearDoesNotCreateConfidence(tc)
            T=table(ones(3,1),[1;2;3],repmat({'M1'},3,1), ...
                'VariableNames',{'year','cost','method'});
            S=statsUtils('summaryTable',T,{'method'},{'cost'});
            tc.verifyTrue(isnan(S.cost_lo));
        end
        function auxiliaryEnergyHasUnitsMWhPerTonne(tc)
            p=params_default('smoke');
            expected=p.iron.hFe*p.station.kappa(:)./p.station.etaEl(:)+p.station.epsAux(:);
            % Conversion capacity must follow the same energy boundary as dispatch.
            tc.verifyEqual(p.station.rhoMax,p.station.pRedMax*24./expected,'RelTol',1e-12);
        end
    end
end
