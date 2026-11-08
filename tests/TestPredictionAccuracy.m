classdef TestPredictionAccuracy < matlab.unittest.TestCase
    methods (Test)
        function lateReferenceSamplesChangeMeasuredError(tc)
            [C,gt,model] = predictionFixture();
            a=runE4Horizon(C,gt,struct('M1',model),1);
            gt.samples{1}(end,3:end,:)=gt.samples{1}(end,3:end,:)+10000*model.norm.sd(end);
            b=runE4Horizon(C,gt,struct('M1',model),1);
            tc.verifyGreaterThan(abs(b.table.W1-a.table.W1),1);
        end
        function allReferenceSamplesAndExplicitModelBudgetAreDisclosed(tc)
            [C,gt,model]=predictionFixture();
            C.p.exp.predictionSamples=3;
            out=runE4Horizon(C,gt,struct('M1',model),4);
            tc.assertTrue(isfield(out,'raw'));
            tc.verifyEqual(out.raw.referenceSamples,[6;6]);
            tc.verifyEqual(out.raw.modelSamples,[3;3]);
            tc.verifyEqual(out.raw.distanceMethod,["scaled_sliced";"scaled_sliced"]);
            tc.verifyEqual(out.raw.seed,[4;4]);
            tc.verifyEqual(out.raw.year,[2020;2021]);
            tc.verifyEqual(out.table.Properties.VariableNames(1:11), ...
                {'Method','gamma','Horizon','W1','W1lo','W1hi','ValueErr','VElo','VEhi','ConsErr','NegFrac'});
        end
        function stepwiseAndReferenceTailsRemainVisible(tc)
            [C,gt,model]=predictionFixture();
            C.p.exp.stepwiseTcap=2;
            out=runE4Horizon(C,gt,struct('M3',model),1);
            tc.assertTrue(isfield(out,'raw'));
            tc.verifyEqual(out.raw.referenceTail,repmat(.8^4,2,1),'AbsTol',1e-12);
            tc.verifyEqual(out.raw.modelTail,repmat(.8^2,2,1),'AbsTol',1e-12);
            tc.verifyEqual(out.raw.tailMismatch,[1;1]);
            tc.verifyEqual(out.raw.referenceSamples,[6;6]);
        end
        function smallFullSampleSetsUseExactDistance(tc)
            [C,gt,model]=predictionFixture();
            C.p.exp.exactW1Max=6;
            out=runE4Horizon(C,gt,struct('M1',model),1);
            tc.verifyEqual(out.raw.referenceSamples,[6;6]);
            tc.verifyEqual(out.raw.distanceMethod,["exact";"exact"]);
            tc.verifyEqual(out.table.distanceMethod,"exact");
        end
        function unequalSampleSlicedUsesEmpiricalMassWeights(tc)
            d=wasserstein1([0,20],[0,1,2],struct('method','sliced','nDirs',1,'seed',1));
            tc.verifyEqual(d,28/3,'AbsTol',1e-12);
        end
        function duplicatedTrainingSeedsDoNotNarrowWeatherInterval(tc)
            tc.assertEqual(exist('summarizePredictionAccuracy','file'),2);
            raw=rawFixture([0;0;10],[2020;2020;2021],[1;1;1]);
            [a,meta]=summarizePredictionAccuracy(raw);
            twice=[raw;raw]; twice.seed(4:6)=2;
            b=summarizePredictionAccuracy(twice);
            tc.verifyEqual(a.W1,5);
            tc.verifyEqual([a.W1lo,a.W1hi],[b.W1lo,b.W1hi],'AbsTol',1e-12);
            tc.verifyEqual(a.nYears,2);
            tc.verifyEqual(b.nSeeds,2);
            tc.verifyEqual(meta.ciUnit,'weather year');
        end
        function missingOrSingleYearHasNoWeatherIntervals(tc)
            tc.assertEqual(exist('summarizePredictionAccuracy','file'),2);
            missing=summarizePredictionAccuracy(rawFixture([1;3],[2020;NaN],[1;2]));
            single=summarizePredictionAccuracy(rawFixture([1;3],[2020;2020],[1;2]));
            tc.verifyTrue(all(isnan([missing.W1lo,missing.W1hi,single.W1lo,single.W1hi])));
            tc.verifyFalse(missing.yearKnown);
        end
        function differentDistanceDefinitionsAreNotAveragedTogether(tc)
            tc.assertEqual(exist('summarizePredictionAccuracy','file'),2);
            raw=rawFixture([1;3],[2020;2021],[1;1]);
            raw.distanceMethod=["exact";"scaled_sliced"];
            T=summarizePredictionAccuracy(raw);
            tc.verifyEqual(height(T),2);
            tc.verifyEqual(sort(T.W1),[1;3]);
        end
        function elementRunRetainsEveryReferenceSampleAndStateRow(tc)
            [C,gt,model,lib]=predictionFixture();
            C.p.exp.evalDays=1; C.p.exp.warmup=0; C.ctx.p=C.p;
            C.p.exp.e5Scenarios={'normal'};
            abl=struct('name','full','label','Full','factory',@(s)model,'terminalProj',[]);
            out=runE5Elements(C,gt,abl,lib,1,1);
            tc.assertTrue(isfield(out,'predictionRaw'));
            tc.verifyEqual(height(out.predictionRaw),2);
            tc.verifyEqual(out.predictionRaw.referenceSamples,[6;6]);
            tc.verifyEqual(out.predictionRaw.modelSamples,[6;6]);
            tc.verifyEqual(out.table.DistanceMethod,"scaled_sliced");
        end
        function figurePlotsDistanceAgainstHorizonAndScalesAreaByValue(tc)
            p=params_default('smoke'); S=plotStyle(p);
            T=table({'M1';'M1'},[.8;.95],[5;20],[2;4],[1;3],[3;5],[.1;.4],[0;0],[.2;.5],[0;0],[0;0], ...
                'VariableNames',{'Method','gamma','Horizon','W1','W1lo','W1hi','ValueErr','VElo','VEhi','ConsErr','NegFrac'});
            T.distanceMethod=["scaled_sliced";"scaled_sliced"];
            folder=tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            base=fullfile(folder.Folder,'horizon');
            F10_horizonBubbles(struct('table',T,'Tloop',10),S,base);
            f=openfig([base,'.fig'],'invisible'); cleanup=onCleanup(@()close(f)); %#ok<NASGU>
            pts=findobj(f,'Tag','PredictionDistance');
            tc.assertEqual(numel(pts),1);
            tc.verifyEqual(numel(pts.XData),2);
            tc.verifyEqual(pts.YData(:),[2;4],'AbsTol',1e-12);   % 无 raw 时箱体由 W1lo、W1、W1hi 三点代表，均值等于 W1
            sz=pts.SizeData;
            tc.verifyEqual(sz(2)/sz(1),4,'AbsTol',1e-12);
            loop=findobj(f,'Tag','MaterialLoopTime');
            tc.verifyEqual(loop.UserData,10);
        end
    end
end

function [C,gt,model,lib]=predictionFixture()
[ds,nrm,ctx,lib,cfg]=makeTinyCTDFCase();
C=makeTestCase(); C.ctx=ctx; C.p=ctx.p;
C.p.exp.exactW1Max=2; C.p.exp.slicedDirs=8; C.p.exp.stepwiseTcap=2;
cfg.nMat=nrm.n; cfg.K=2;
[net,meta]=buildVelocityNet(nrm.D,lib.dimEmb,cfg,13);
params=structfun(@extractdata,net,'UniformOutput',false);
model=struct('cfg',cfg,'meta',meta,'norm',nrm,'ema',params,'gammaFinal',.8, ...
    'stage',struct('gamma',.8,'ema',params),'useGPU',false);
gt=struct('S0',double(ds.S(:,1:2)),'c0',ds.c(1:2), ...
    'emb0',embeddingsFromIds(lib,ds.id(:,1:2)),'gammas',.8,'year',[2020,2021], ...
    'day',[10,20],'Tcap',4,'truncMass',.8^4,'R',2);
gt.samples={repmat(reshape(double(ds.S(:,3:4)),nrm.D,1,2),1,6,1)};
end

function T=rawFixture(values,years,seeds)
n=numel(values);
T=table(repmat({'M1'},n,1),repmat(.8,n,1),repmat(5,n,1),(1:n)',years,seeds, ...
    values,.1*values,zeros(n,1),zeros(n,1),repmat("exact",n,1), ...
    'VariableNames',{'Method','gamma','Horizon','state','year','seed','W1','ValueErr','ConsErr','NegFrac','distanceMethod'});
end
