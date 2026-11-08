classdef TestNationalFinance < matlab.unittest.TestCase
    methods (Test)
        function zeroDiscountAnnualizesIronAssetsOverTheirLives(tc)
            n=params_national(); n.r=0; n.om=0;
            n.fe.hFe=1; n.fe.etaSt=1; n.fe.kappa=1; n.fe.etaEl=1; n.fe.eps=0;
            n.fe.capEl=100; n.fe.capRed=200; n.fe.capRetro=300;
            n.fe.lifeSt=10; n.fe.lifeRetro=20; n.fe.siloPerT=10; n.fe.loss=0;
            n.rail.base1=0; n.rail.perKm=0;
            svc=struct('D',2,'hOut',1000,'hIn',2000);
            [cost,parts]=natCost('fe',svc,.5,n,0,0);
            % 150k charging / 10y + 300k retrofit / 20y; 48t silo / 10y.
            tc.verifyEqual(parts,[.5,.03,.000048,0],'AbsTol',1e-12);
            tc.verifyEqual(cost,.530048,'AbsTol',1e-12);
        end
        function zeroDiscountAnnualizesHydrogenAssetsOverTheirLives(tc)
            n=params_national(); n.r=0; n.om=0;
            n.h2.etaEl=.5; n.h2.etaGT=.5;
            n.h2.capEl=100; n.h2.capGT=200; n.h2.life=10; n.h2.lifeStore=20;
            svc=struct('D',2,'hOut',1000,'hIn',2000);
            [cost,parts]=natCost('h2',svc,0,n,0,0,30);
            % 400k conversion / 10y; 2.88m storage / 20y; 1000 MWh/y output.
            tc.verifyEqual(parts,[0,.04,.144,0],'AbsTol',1e-12);
            tc.verifyEqual(cost,.184,'AbsTol',1e-12);
        end
    end
end
