classdef TestPaperEvaluation < matlab.unittest.TestCase
    methods(Test)
        function injectedWindowDoesNotCountUnrelatedAnnualEvents(tc)
            s=fixtureSeries(); s.shed([3 6 9])=[100 10 20];
            s.safetySlack(1,6)=-1; s.risk(4)=.8;
            e=eventWindowMetrics(s,struct('type','drought','start',5,'days',3),2,2,.5);
            tc.verifyEqual(e.core.shedMWh,10);
            tc.verifyEqual(e.followup.shedMWh,30);
            tc.verifyEqual(e.core.safeAllPlantDays,2);
            tc.verifyEqual(e.warningLeadDays,2);
            tc.verifyTrue(e.core.complete);
        end
        function clippedOrMissingEventIsMarkedIncomplete(tc)
            e=eventWindowMetrics(fixtureSeries(),struct('type','drought','start',11,'days',4),2,2,.5);
            tc.verifyFalse(e.core.complete); tc.verifyFalse(e.followup.complete);
            tc.verifyEqual(e.core.observedDays,2);
            n=eventWindowMetrics(fixtureSeries(),struct('type','none'),2,2,.5);
            tc.verifyFalse(n.available); tc.verifyTrue(isnan(n.warningLeadDays));
        end
        function distributedDiagnosticsDescribeExecutedCandidate(tc)
            [ds,nrm,ctx,lib,cfg]=makeTinyCTDFCase();
            cfg.nMat=nrm.n; cfg.K=2;
            [net,meta]=buildVelocityNet(nrm.D,lib.dimEmb,cfg,3);
            mdl=struct('cfg',cfg,'meta',meta,'norm',nrm,'gammaFinal',.99, ...
                'ema',structfun(@extractdata,net,'UniformOutput',false),'useGPU',false);
            obs=struct('s',double(ds.S(:,1)),'c',ds.c(1));
            [id,out]=gpiSelect(mdl,obs,ctx,lib,struct('mode','distributed', ...
                'rs',RandStream('twister','Seed',5)));
            tc.verifyEqual(out.selected.id,id);
            tc.verifyTrue(all(isfinite([out.selected.Q,out.selected.R])));
            tc.verifyEqual(out.selected.Q,out.lastResponse.Q(out.lastResponse.chosen));
            tc.verifyEqual(out.selected.R,out.lastResponse.R(out.lastResponse.chosen));
            opts=struct('mode','distributed','prevId',ones(lib.nAgents,1), ...
                'rs',RandStream('twister','Seed',5));
            [~,outPrev]=gpiSelect(mdl,obs,ctx,lib,opts);
            tc.verifyEqual(outPrev.initialResponseId,lib.candidates(:,outPrev.central.best));
            tc.verifyEqual(outPrev.id,id);
        end
    end
end
function s=fixtureSeries()
s=struct('shed',zeros(1,12),'cur',zeros(1,12),'ironShortT',zeros(1,12), ...
    'forecastMin',ones(1,12),'safetySlack',ones(2,12),'risk',zeros(1,12));
end
