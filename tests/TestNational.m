classdef TestNational < matlab.unittest.TestCase
    %TESTNATIONAL 全国评估模块：
    %   (1) natCost 复现浩吉走廊三路线对比的基准数值（走廊运铁 3.041、西部就地 + 特高压 2.654、
    %       西部氢储能 + 特高压 2.511（储氢 30 元/kWh）与 1.240（3 元/kWh））；
    %   (2) natStorage 在方波风光序列上的解析解（电量平衡容量、序列峰值储能、放电利用小时）；
    %   (3) natCapacityCheck 在方波序列上的临界循环质量构成：M_event − M_sp = δ^U·U_max，D_max 等于缺电持续天数；
    %   (4) natLoadInputs 读取随代码提供的数据（31 省、燃煤电厂、特高压、盐穴）。

    methods (Test)
        function testCostReproducesRouteCompare(tc)
            % 公式回归检验：参数取浩吉走廊三路线对比当时的取值（与当前基准参数无关）
            n = params_national();
            n.fe.etaSt = mean([0.43, 0.38, 0.38, 0.38, 0.44, 0.38]);
            n.fe.capRetro = 400;
            n.fe.etaEl = 0.70;
            n.h2.etaEl = 0.70;
            n.fe.capEl = 3000;
            n.h2.capEl = 3000;
            n.fe.capRed = 7000;
            n.fe.price = 3000;
            n.fe.siloPerT = 50;
            n.fe.loss = 0.005;
            n.fe.kappa = 1.61;
            n.fe.eps = 0.06 * n.fe.hFe; % old dimensionless auxiliary factor -> MWh/t
            n.h2.etaGT = 0.50;
            n.h2.capGT = 3000;
            n.rail.base1 = 0;
            n.rail.perKm = 0.18;
            svc = struct('D', 14, 'hOut', 1500, 'hIn', 2500);
            a = natCost('fe', svc, 0.15, n, 1260, 8);
            b = natCost('fe', svc, 0.15, n, 100, 2) / (1 - 0.065) + 0.0701;
            c = natCost('h2', svc, 0.15, n, 0, 0, 30) / (1 - 0.065) + 0.0701;
            d = natCost('h2', svc, 0.15, n, 0, 0, 3) / (1 - 0.065) + 0.0701;
            eout = n.fe.etaSt*n.fe.hFe;
            inv = @(days) 24*svc.D/eout + svc.hOut/eout/365*days;
            siloOM = @(days) inv(days)*n.fe.siloPerT*n.om/(svc.hOut*1e3);
            expected = [3.04116+siloOM(8), 2.654238+siloOM(2)/(1-.065), 2.510709, 1.23996];
            tc.verifyEqual([a, b, c, d], expected, 'RelTol', 2e-6);
            [~, comp, eta] = natCost('fe', svc, 0.15, n, 1260, 8);
            tc.verifyEqual(sum(comp), a, 'RelTol', 1e-12);
            tc.verifyEqual(eta, n.fe.etaSt / (n.fe.kappa / n.fe.etaEl + n.fe.eps/n.fe.hFe), 'RelTol', 1e-12);
        end

        function testSequentPeakSquareWave(tc)
            % 每 73 天：48 天出力 2、25 天出力 0；负荷恒为 1；η = 0.5
            x = repmat([2 * ones(1, 48), zeros(1, 25)], 1, 10);
            r = reshape(x, 365, 2)';
            d = ones(2, 365);
            s = natStorage(r, d, 0.5, 1, 1);
            tc.verifyEqual(s.Kstar, (1 + 25 / 24) / 2, 'RelTol', 1e-9);
            tc.verifyEqual(s.S, 25, 'AbsTol', 1e-6);
            tc.verifyEqual(s.peakDis, 1, 'AbsTol', 1e-12);
            tc.verifyEqual(s.D, 25, 'AbsTol', 1e-6);
            tc.verifyEqual(s.hOut, 24 * 125, 'AbsTol', 1e-6);
            tc.verifyEqual(s.curt, 0, 'AbsTol', 1e-9);
            s2 = natStorage(r, d, 0.5, 1.5, 1);
            tc.verifyEqual(s2.S, 25, 'AbsTol', 1e-6);
            tc.verifyGreaterThan(s2.curt, 0);
        end

        function testCapacitySquareWave(tc)
            n = params_national();
            x = repmat([2 * ones(1, 48), zeros(1, 25)], 1, 10);
            r = reshape(x, 365, 2)';
            s = natStorage(r, ones(2, 365), 0.5, 1, 1);
            t = natCapacityCheck(s, r, n, 3);
            eOut = n.fe.etaSt * n.fe.hFe;
            tc.verifyEqual(t.Dmax, 25);
            tc.verifyEqual(t.deltaD, 24 / eOut, 'RelTol', 1e-9);
            tc.verifyEqual(t.Mevent - t.Msp, t.deltaU * t.Umax, 'RelTol', 1e-9);
            tc.verifyEqual(t.Msp, 24 * 25 / eOut + t.Phi * 3, 'RelTol', 1e-9);
        end

        function testLoadInputs(tc)
            n = params_national();
            N = natLoadInputs(n);
            tc.verifyEqual(height(N.prov), 31);
            tc.verifyGreaterThan(sum(N.prov.gwAll), 850);          % GCPT 来源记录，31 省约 896 GW
            tc.verifyTrue(all(N.prov.phiW >= 0 & N.prov.phiW <= 1));
            tc.verifyTrue(all(N.prov.dLocal >= 50));
            tc.verifyTrue(all(N.prov.hydroShare >= 0 & N.prov.hydroShare < 0.8));
            tc.verifyEqual(height(N.uhv), 30);          % 29 回线路，昆柳龙三端直流拆为两条记录
            tc.verifyEqual(nnz(isfinite(N.prov.saltTier)), 11);
            tc.verifyEqual(size(N.dHub), [31, 31]);
            tc.verifyTrue(all(ismember(N.pts.kind, ["wind", "pv"])));
        end
    end
end
