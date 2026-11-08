classdef TestNationalContinuity < matlab.unittest.TestCase
    methods (Test)
        function nationalAssessmentRejectsYearGaps(tc)
            [n,N,Cl] = nationalFixture(tc,[2014 2015 2019]);
            tc.verifyError(@()natAssess(n,N,Cl),'natAssess:nonConsecutiveYears');
        end
        function nationalAssessmentRejectsDuplicateOrReversedYears(tc)
            [n,N,Cl] = nationalFixture(tc,[2014 2014 2015]);
            tc.verifyError(@()natAssess(n,N,Cl),'natAssess:nonConsecutiveYears');
            Cl.years = [2015 2014 2016];
            tc.verifyError(@()natAssess(n,N,Cl),'natAssess:nonConsecutiveYears');
        end
        function lowEventContinuesAcrossRealYearBoundary(tc)
            n=params_national(); n.stats.dQuantile=1;
            r=ones(2,365); r(1,end-3:end)=0; r(2,1:6)=0;
            s=natStorage(r,ones(size(r)),.5,1,1);
            t=natCapacityCheck(s,r,n,3);
            tc.verifyEqual(t.Dmax,10);
        end
        function surplusEventContinuesAcrossRealYearBoundary(tc)
            n=params_national(); n.stats.dQuantile=1;
            r=ones(2,365); r(1,end-3:end)=2; r(2,1:6)=2;
            s=natStorage(r,ones(size(r)),.5,1,1);
            t=natCapacityCheck(s,r,n,3);
            tc.verifyEqual(t.Umax,10);
        end
        function eventStatisticsDoNotWrapRecordEndpoints(tc)
            n=params_national(); n.stats.dQuantile=1;
            r=ones(2,365); r(1,1:4)=0; r(2,end-5:end)=0;
            s=natStorage(r,ones(size(r)),.5,1,1);
            t=natCapacityCheck(s,r,n,3);
            tc.verifyEqual(t.Dmax,6);
        end
        function optionalCalendarYearsPreserveSyntheticSizing(tc)
            r=ones(2,365); r(1,end-3:end)=0; r(2,1:6)=0;
            a=natStorage(r,ones(size(r)),.5,1,1);
            b=natStorage(r,ones(size(r)),.5,1,1,[2014 2015]);
            tc.verifyEqual(b.S,a.S,'AbsTol',1e-9);
            tc.verifyEqual(b.years,[2014 2015]);
            tc.verifyError(@()natStorage(r,ones(size(r)),.5,1,1,[2014 2019]), ...
                'natStorage:nonConsecutiveYears');
            n=params_national(); b.years=[2014 2019];
            tc.verifyError(@()natCapacityCheck(b,r,n,3),'natCapacityCheck:nonConsecutiveYears');
        end
        function zeroRateDoesNotBreakValidChronology(tc)
            [n,N,Cl]=nationalFixture(tc,[2014 2015 2016]);
            n.r=0;
            R=natAssess(n,N,Cl);
            tc.verifyTrue(all(isfinite(R.T.lcoe)));
            tc.verifyTrue(all(isfinite(R.T.pin)));
            tc.verifyTrue(all(isfinite(R.T.H2T)));
            tc.verifyEqual(R.info.svc{1}.years,Cl.years);
        end
    end
end
function [n,N,Cl]=nationalFixture(tc,years)
n=params_national(); n.scenarios=n.scenarios(1);
folder=tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
n.outDir=folder.Folder;
N=natLoadInputs(n);
v=repmat([ones(1,48)*.6 zeros(1,25)],1,5);
cf=repmat(reshape(v,1,1,365),height(N.prov),numel(years),1);
Cl=struct('years',years,'cfW',cf,'cfS',cf,'load',ones(size(cf)));
end
