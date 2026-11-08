classdef TestCTDFReference < matlab.unittest.TestCase
    methods (Test)
        function cappedRiskUsesCorrectTerminalWeight(tc)
            r=cappedPathRisk([0,1,0;1,0,1],.5,.05);
            tc.verifyEqual(r.weights,[.5,.25,.25],'AbsTol',1e-14);
            tc.verifyEqual(r.pathMean,[.25;.75],'AbsTol',1e-14);
            tc.verifyEqual(r.mean,.5,'AbsTol',1e-14);
            tc.verifyEqual(r.truncationBound,.125,'AbsTol',1e-14);
            tc.verifyEqual(r.independentPathCount,2);
            tc.verifyEqual(r.hoeffdingHalfWidth,sqrt(log(40)/4),'AbsTol',1e-14);
            z=cappedPathRisk([0,1,0;1,0,1],0,.05);
            tc.verifyEqual(z.pathMean,[0;1]);
            tc.verifyEqual(cappedPathRisk([.2;.8],.99,.05).weights,1);
        end
        function boundedRiskInputsMustBeValid(tc)
            tc.verifyError(@() cappedPathRisk([-.1,1],.5,.05),'cappedPathRisk:values');
            tc.verifyError(@() cappedPathRisk([0,1],1,.05),'cappedPathRisk:gamma');
            tc.verifyError(@() cappedPathRisk([0,1],.5,0),'cappedPathRisk:alpha');
        end
        function referenceRetainsBranchAndSourceIdentity(tc)
            [ctx,lib,st,opt]=fixture();
            gt=groundTruthSM(ctx,lib,st,[0,.5],opt);
            tc.verifySize(gt.branchId{2},[8,1]);
            tc.verifySize(gt.stopTime{2},[8,1]);
            tc.verifyEqual(gt.stopTime{1},ones(8,1));
            tc.verifyGreaterThanOrEqual(gt.branchId{2},1);
            tc.verifyLessThanOrEqual(gt.branchId{2},2);
            tc.verifyEqual(gt.year,st.year);
            tc.verifyEqual(gt.day,st.day);
            tc.verifySize(gt.pathRisk{2},[2,1]);
            tc.verifyEqual(gt.pathRiskMean{2},mean(gt.pathRisk{2},1),'AbsTol',1e-14);
            tc.verifyEqual(gt.riskTruncationBound,[0,.125],'AbsTol',1e-14);
            tc.verifyTrue(gt.normalCapacityVerified);
            for a=1:8
                for b=a+1:8
                    if gt.branchId{2}(a)==gt.branchId{2}(b)&&gt.stopTime{2}(a)==gt.stopTime{2}(b)
                        tc.verifyEqual(gt.samples{2}(:,a,1),gt.samples{2}(:,b,1));
                    end
                end
            end
        end
        function repeatedSampleColumnsDoNotCreateIndependentPaths(tc)
            [ctx,lib,st,opt]=fixture();
            a=groundTruthSM(ctx,lib,st,.5,opt);
            opt.nSamples=24;
            b=groundTruthSM(ctx,lib,st,.5,opt);
            tc.verifyEqual(a.pathRisk{1},b.pathRisk{1});
            tc.verifyEqual(a.pathRiskHoeffding{1},b.pathRiskHoeffding{1});
            tc.verifyEqual(b.independentContinuationCount,2);
            tc.verifyEqual(b.sampleCountPerState,24);
        end
        function nonnormalCapacityAndOracleCannotMasqueradeAsNormalKernel(tc)
            [ctx,lib,st,opt]=fixture();
            st.S0(ctx.L.xi.Fcap(1),1)=.5;
            tc.verifyError(@() groundTruthSM(ctx,lib,st,.5,opt),'groundTruthSM:capacity');
            ctx.p.forecast.mode='oracle';
            tc.verifyError(@() groundTruthSM(ctx,lib,st,.5,opt),'groundTruthSM:forecast');
        end
        function fixedMarginAndCacheIdentityArePreserved(tc)
            [ctx,lib,st,opt]=fixture();
            dir0=tempname; mkdir(dir0);
            cleanup=onCleanup(@() rmdir(dir0,'s')); %#ok<NASGU>
            opt.partDir=dir0;
            spec=ctx.margin;
            spec.GFe(:)=0; spec.gFe0(:)=0; spec.kind='frozen_affine_test';
            opt.marginSpec=spec;
            a=groundTruthSM(ctx,lib,st,.5,opt);
            tc.verifyEqual(a.pathRisk{1},.5*ones(2,1),'AbsTol',1e-14);
            th=ctx.p.ctdf.varthetaDays*max(mean(ctx.stats.deltaDbarP),1e-6);
            spec.gFe0(:)=th*log(3); opt.marginSpec=spec;
            b=groundTruthSM(ctx,lib,st,.5,opt);
            tc.verifyEqual(b.pathRisk{1},.25*ones(2,1),'AbsTol',1e-14);
            c=groundTruthSM(ctx,lib,st,.5,opt);
            tc.verifyEqual(c.samples,b.samples);
            tc.verifyEqual(c.pathRisk,b.pathRisk);
        end
        function neuralSnapshotsAndDeterministicRiskAreSeparate(tc)
            [ds,nrm,ctx,lib,cfg]=makeTinyCTDFCase();
            cfg.nMat=nrm.n;
            [net,meta]=buildVelocityNet(nrm.D,lib.dimEmb,cfg,3);
            model=struct('cfg',cfg,'meta',meta,'norm',nrm,'gammaFinal',.99, ...
                'ema',structfun(@extractdata,net,'UniformOutput',false),'snaps',{{}});
            gt=struct('S0',double(ds.S(:,1)),'c0',ds.c(1), ...
                'emb0',embeddingsFromIds(lib,ds.id(:,1)),'gammas',.99,'samples',{{ds.S(:,2:3)}});
            vp=checkModelProperties(model,ctx,lib,ds,gt,struct(),struct('K',2,'nBatch',2));
            tc.verifyTrue(vp.exactOperator.pass);
            tc.verifyTrue(isfield(vp.neuralDiagnostics,'snapshotDistance'));
            tc.verifyEqual(vp.riskErr.MCerr,zeros(height(vp.riskErr),1));
            tc.verifyTrue(all(vp.riskErr.RiskErr<=vp.riskErr.LW1+vp.riskErr.Tolerance));
            gt.gammas=.8;
            tc.verifyError(@() checkModelProperties(model,ctx,lib,ds,gt,struct(),struct('K',2,'nBatch',2)), ...
                'checkModelProperties:gamma');
        end
        function projectionRejectsReferenceWithWrongActiveMass(tc)
            [ds,nrm,ctx,lib,cfg]=makeTinyCTDFCase(); cfg.nMat=nrm.n;
            [net,meta]=buildVelocityNet(nrm.D,lib.dimEmb,cfg,3);
            model=struct('cfg',cfg,'meta',meta,'norm',nrm,'gammaFinal',.99, ...
                'ema',structfun(@extractdata,net,'UniformOutput',false),'snaps',{{}});
            ref=ds.S(:,2:3); ref(1:nrm.n,:)=1.1*ref(1:nrm.n,:);
            gt=struct('S0',double(ds.S(:,1)),'c0',ds.c(1), ...
                'emb0',embeddingsFromIds(lib,ds.id(:,1)),'gammas',.99,'samples',{{ref}});
            tc.verifyError(@() checkModelProperties(model,ctx,lib,ds,gt,struct(),struct('K',2,'nBatch',2)), ...
                'checkModelProperties:referenceSupport');
        end
    end
end

function [ctx,lib,st,opt]=fixture()
C=makeTestCase(); ctx=C.ctx; ctx.p.exp.warmup=0;
lib=policyLibrary(ctx.p,C.topo,C.stats,4);
w=jointPolicy(lib,3*ones(lib.nAgents,1));
st=sampleStates(ctx,C.W,lib,1,1,w,C.cNominal,9);
opt=struct('R',2,'Tcap',3,'nSamples',8,'seed',7,'useParfor',false);
end
