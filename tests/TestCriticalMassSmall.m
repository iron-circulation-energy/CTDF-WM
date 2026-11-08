classdef TestCriticalMassSmall < matlab.unittest.TestCase
    %TESTCRITICALMASSSMALL 临界循环质量与事件风险的小算例（流体模型 fluidLoopSim，两座电厂）：
    %   (a) c = M_crit：全部对抗序列族下无缺铁断供、无锈阻塞，守恒误差 ≤ 1e−9·c；
    %   (b) c = 0.9·M_crit：存在违约序列；c < W + 安全库存：初始即不可行；
    %   (c) 事件风险：'rustFirst' 分配下单次低风光事件的断供阈值 D* = ⌊(c − M_0)/δ^D⌋ + 1；
    %   (d) 还原功率上限低于 Φ̄ + δ^U 时报告功率违约。

    properties
        fl
    end

    methods (TestClassSetup)
        function setup(tc)
            f.Phi = 100;
            f.deltaD = 50;
            f.deltaU = 40;
            f.Dmax = 5;
            f.Umax = 4;
            f.dR = 30;
            f.share = [0.4; 0.6];
            f.tauFe = [2; 3];
            f.tauOx = [2; 3];
            f.tP = 1;
            f.tR = 1;
            f.tRed = 1;
            f.safeFe = [20; 30];
            f.safeOx = 25;
            f.gap = ceil(max(f.deltaD * f.Dmax, f.deltaU * f.Umax) / f.dR) + 3 + 1 + 3 + 1 + 1 + 5;
            tc.fl = f;
        end
    end

    methods (Test)
        function testSufficiencyAtMcrit(tc)
            f = tc.fl;
            seqs = worstCaseSequence(f.Dmax, f.Umax, f.gap, 3);
            fam = fieldnames(seqs);
            Mc = fluidLoopSim(1e12, f, 'N').Mcrit;
            for k = 1:numel(fam)
                r = fluidLoopSim(Mc, f, seqs.(fam{k}));
                tc.verifyEqual(r.violFe, 0, sprintf('序列族 %s 出现缺铁断供。', fam{k}));
                tc.verifyEqual(r.violOx, 0, sprintf('序列族 %s 出现锈阻塞。', fam{k}));
                tc.verifyLessThanOrEqual(r.consErr, 1e-9 * Mc);
            end
        end

        function testNecessityBelowMcrit(tc)
            f = tc.fl;
            seqs = worstCaseSequence(f.Dmax, f.Umax, f.gap, 3);
            fam = fieldnames(seqs);
            Mc = fluidLoopSim(1e12, f, 'N').Mcrit;
            viol = 0;
            for k = 1:numel(fam)
                r = fluidLoopSim(0.9 * Mc, f, seqs.(fam{k}));
                viol = viol + r.violFe + r.violOx;
            end
            tc.verifyGreaterThan(viol, 0);
            r0 = fluidLoopSim(0.5 * r.W, f, 'NNN');
            tc.verifyEqual(r0.violFe, Inf);
        end

        function testEventRiskThreshold(tc)
            f = tc.fl;
            probe = fluidLoopSim(1e12, f, 'N');
            M0 = probe.Mcrit - f.deltaD * f.Dmax;
            for units = [0.5, 1.5, 2.5, 3.5]
                c = M0 + units * f.deltaD;
                Dstar = NaN;
                for D = 1:20
                    r = fluidLoopSim(c, f, [repmat('D', 1, D), repmat('N', 1, 12)], struct('split', 'rustFirst'));
                    if r.violFe > 0
                        Dstar = D;
                        break;
                    end
                end
                tc.verifyEqual(Dstar, floor(units) + 1);
            end
        end

        function testA3Violation(tc)
            f = tc.fl;
            Mc = fluidLoopSim(1e12, f, 'N').Mcrit;
            seq = worstCaseSequence(f.Dmax, f.Umax, f.gap, 1).U1;
            r = fluidLoopSim(Mc, f, seq, struct('redCap', f.Phi + 0.5 * f.deltaU));
            tc.verifyGreaterThan(r.violCap, 0);
        end
    end
end
