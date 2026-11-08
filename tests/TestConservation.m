classdef TestConservation < matlab.unittest.TestCase
    %TESTCONSERVATION 活动质量守恒检验：随机动作（direct 模式）与策略 + 内层调度（lp 模式）下，
    %   逐日 |1ᵀx − c| ≤ 1e−9·c 且 x ≥ −1e−9·c；荷电状态恒等式；随机 MPC 日物料映射的列和。

    properties
        C
    end

    methods (TestClassSetup)
        function setup(tc)
            tc.C = makeTestCase();
        end
    end

    methods (Test)
        function testDirectRandomActions(tc)
            out = checkMassBalance(tc.C.ctx, tc.C.W, 1, tc.C.cNominal, 300, 7);
            tc.verifyLessThanOrEqual(out.maxConsRel, 1e-9);
            tc.verifyLessThanOrEqual(out.maxSocErr, 1e-9);
            tc.verifyLessThanOrEqual(out.maxOxErr, 1e-9);
            tc.verifyLessThanOrEqual(out.maxVErr, 1e-9);
            tc.verifyGreaterThanOrEqual(out.minXRel, -1e-9);
            tc.verifyGreaterThan(out.nShortFe, 0, '随机动作应触发燃铁截断，以检验截断路径。');
        end

        function testPolicyWithInnerLP(tc)
            C = tc.C;
            lib = policyLibrary(C.p, C.topo, C.stats, C.p.seed);
            seg = buildSegment(C.W(1), 30, 16, C.p);
            env = IronRustEnv(C.ctx);
            env.reset(1, C.cNominal, 0.6, struct('seg', seg));
            for m = 1:4
                w = jointPolicy(lib, lib.alignedIds(:, m));
                for t = 1:3
                    env.step(policyAct(env.getObs(), w, C.ctx));
                    tc.verifyLessThanOrEqual(abs(sum(env.x) - C.cNominal) / C.cNominal, 1e-9);
                    tc.verifyGreaterThanOrEqual(min(env.x), -1e-9 * C.cNominal);
                end
            end
        end

        function testRandomInitMaterial(tc)
            rs = RandStream('twister', 'Seed', 3);
            for k = 1:20
                c = 1e5 * (0.5 + rand(rs));
                [x, gInv, gLine] = initMaterial(c, rand(rs), tc.C.ctx, 'random', rs);
                tc.verifyLessThanOrEqual(abs(sum(x) - c), 1e-9 * c);
                tc.verifyGreaterThanOrEqual(min(x), 0);
                tc.verifyTrue(all(gInv >= tc.C.p.aging.floor & gInv <= 1));
                tc.verifyTrue(all(gLine >= tc.C.p.aging.floor & gLine <= 1));
            end
        end

        function testMpcMaterialMap(tc)
            mpc = mpcSetup(tc.C.ctx, tc.C.W, 1);
            M = mpc.M;
            tc.verifyLessThanOrEqual(max(abs(sum(M.Mx, 1) - 1)), 1e-12);
            tc.verifyLessThanOrEqual(max(abs([sum(M.Mb, 1), sum(M.Mr, 1), sum(M.Mf, 1)])), 1e-12);
        end
    end
end
