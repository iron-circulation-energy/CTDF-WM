classdef TestScalingTiming < matlab.unittest.TestCase
    methods (Test)
        function timingIncludesStepwiseWithDeclaredBudget(tc)
            p=tinyTiming();
            e=runE7Scaling(p,12);
            tc.verifyGreaterThan(e.table.tM3,0);
            tc.verifyEqual(e.table.KM3,3);
            tc.verifyEqual(e.table.TcapM3,4);
            tc.verifyEqual(e.table.KM1,2);
            tc.verifyEqual(sort(e.repetitions.Method),{'M1';'M2';'M3'});
            tc.verifyGreaterThan(e.repetitions.Seconds,0);
            i=strcmp(e.repetitions.Method,'M3');
            tc.verifyEqual(e.repetitions.K(i),3);
            tc.verifyEqual(e.repetitions.Tcap(i),4);
            tc.verifyEqual(e.repetitions.nEvaluated(i),5);   % 五个命名原型（含前瞻补货型），nRandCand = 0
            tc.verifyFalse(e.timingScope.networksTrained);
            tc.verifyEqual(e.timingScope.type,'synthetic_forward_timing_fixture');
        end
        function invalidStepwiseBudgetIsRejected(tc)
            p=tinyTiming(); p.exp.stepwiseK=0;
            tc.verifyError(@() runE7Scaling(p,12),'runE7Scaling:budget');
            p=tinyTiming(); p.exp.stepwiseTcapCtrl=0;
            tc.verifyError(@() runE7Scaling(p,12),'runE7Scaling:budget');
        end
        function figureContainsAllThreeMethodsAndSettingLabel(tc)
            p=tinyTiming(); S=plotStyle(p); S.note='';
            e.table=table([3;6],[.1;.2],[.2;.4],[.3;.6], ...
                'VariableNames',{'nPlants','tM1','tM2','tM3'});
            d=tempname; mkdir(d); cleanup=onCleanup(@() rmdir(d,'s')); %#ok<NASGU>
            F19_scaling(e,S,fullfile(d,'F19'));
            f=openfig(fullfile(d,'F19.fig'),'invisible');
            figCleanup=onCleanup(@() close(f)); %#ok<NASGU>
            ax=findall(f,'Type','axes');
            lines=findall(ax,'Type','line');
            tc.verifyNumElements(lines,3);
            labels={lines.DisplayName};
            tc.verifyTrue(any(strcmp(labels,S.methodLabel('M3'))));
            txt=findall(f,'Type','textboxshape');
            tc.assertNotEmpty(txt);
            textLines=string.empty;
            for k=1:numel(txt)
                textLines=[textLines;string(txt(k).String)]; %#ok<AGROW>
            end
            tc.verifyTrue(any(contains(textLines,'合成拓扑') | contains(textLines,'Synthetic topology')));
        end
    end
end

function p=tinyTiming()
p=params_default('smoke');
p.exp.scaleList=3; p.exp.timingReps=1;
p.exp.stepwiseK=3; p.exp.stepwiseTcapCtrl=4;
p.ctdf.width=8; p.ctdf.dCond=8; p.ctdf.dT=4; p.ctdf.nBlocks=1;
p.ctdf.nOde=1; p.ctdf.K=2; p.ctdf.nRandCand=0;
p.ctdf.gammaStages=.5; p.ctdf.gpiMode='central'; p.ctdf.useGPU=false;
p.mpc.S=1; p.mpc.periods=1; p.mpc.horizonFactor=1;
p.data.useParfor=false;
end
