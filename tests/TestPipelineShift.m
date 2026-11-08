classdef TestPipelineShift < matlab.unittest.TestCase
    %TESTPIPELINESHIFT 在途管道移位检验：第 1 天在线路 e 上发运 f，则第 k 天末该批物料位于
    %   q_{e,τ_e−k+1}（k = 1..τ_e），第 τ_e + 1 天日初到达目标节点库存；其余管道格与库存不受影响。

    properties
        C
    end

    methods (TestClassSetup)
        function setup(tc)
            tc.C = makeTestCase();
        end
    end

    methods (Test)
        function testShiftAndArrival(tc)
            C = tc.C;
            ctx = C.ctx;
            idx = ctx.idx;
            topo = C.topo;
            e = find(topo.tau >= 2, 1);
            tau = topo.tau(e);
            seg = buildSegment(C.W(1), 1, tau + 3, C.p);
            [x0, gInv, gLine] = initMaterial(C.cNominal, 0.6, ctx, 'deterministic', []);
            pipes = idx.pipeMask;
            x0(idx.V) = x0(idx.V) + sum(x0(pipes));
            x0(pipes) = 0;
            env = IronRustEnv(ctx);
            env.reset(1, C.cNominal, 0.6, struct('seg', seg, 'dispatchMode', 'direct', 'x0', x0, ...
                'gInv0', gInv, 'gLine0', gLine));
            src = idx.lineSrc(e);
            tgt = idx.lineTgt(e);
            amt = 0.3 * x0(src);
            tgt0 = x0(tgt);
            for day = 1:tau + 1
                a = zeroAction(topo);
                if day == 1
                    a.f(e) = amt;
                end
                env.step(a);
                q = idx.q{e};
                if day <= tau
                    expect = zeros(tau, 1);
                    expect(tau - day + 1) = amt;
                    tc.verifyEqual(env.x(q), expect, 'AbsTol', 1e-9 * C.cNominal);
                else
                    tc.verifyEqual(env.x(tgt), tgt0 + amt, 'AbsTol', 1e-9 * C.cNominal);
                    tc.verifyEqual(sum(env.x(q)), 0, 'AbsTol', 1e-9 * C.cNominal);
                end
            end
            tc.verifyEqual(sum(env.x), C.cNominal, 'RelTol', 1e-12);
        end
    end
end

function a = zeroAction(topo)
a.o = false(topo.nP, 1);
a.bcap = zeros(topo.nP, 1);
a.beta = zeros(topo.nP, 1);
a.rho = zeros(topo.nR, 1);
a.f = zeros(topo.nE, 1);
a.burn = zeros(topo.nP, 1);
a.red = zeros(topo.nR, 1);
end
