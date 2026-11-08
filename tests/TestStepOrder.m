classdef TestStepOrder < matlab.unittest.TestCase
    %TESTSTEPORDER 单日推进顺序检验：
    %   (1) 日初到达先于燃铁：电厂库存为零而当日到达 A 时，可燃 A 且无缺铁截断；
    %   (2) 当日燃烧生成的锈可在当日发运（发运在燃铁之后）；
    %   (3) 燃铁请求超过可用铁时截断并记录；
    %   (4) 补铁：当日损耗先计入虚拟储备 V，再按 u ≤ V 等量补回还原站（V 初值为 0 时 V 保持为 0）；
    %   (5) lp 模式下动作可行化：燃铁上限截断到库存并记录。

    properties
        C
    end

    methods (TestClassSetup)
        function setup(tc)
            tc.C = makeTestCase();
        end
    end

    methods (Test)
        function testArrivalBeforeBurn(tc)
            [env, ctx, x0] = tc.freshEnv();
            idx = ctx.idx;
            i = 1;
            g = ctx.topo.P(i);
            e = ctx.inFe{g}(1);
            A = x0(idx.IFe(i)) + x0(idx.qFirst(e));        % 把电厂库存全部移入最近管道格（总量不变）
            x0(idx.IFe(i)) = 0;
            x0(idx.qFirst(e)) = A;
            env = tc.resetWith(env, x0);
            a = zeroAction(ctx.topo);
            a.burn(i) = A;
            info = env.step(a);
            tc.verifyEqual(info.b(i), A, 'RelTol', 1e-12);
            tc.verifyEqual(info.shortFe(i), 0, 'AbsTol', 1e-9);
        end

        function testRustShippedSameDay(tc)
            [env, ctx, x0] = tc.freshEnv();
            idx = ctx.idx;
            i = 1;
            g = ctx.topo.P(i);
            eo = ctx.outOx{g}(1);
            x0(idx.V) = x0(idx.V) + x0(idx.IOx(i));
            x0(idx.IOx(i)) = 0;
            env = tc.resetWith(env, x0);
            lossI = tc.C.p.plant.loss(i);
            b = min(0.5 * x0(idx.IFe(i)), 0.5 * ctx.topo.Fcap(eo) / (1 - lossI));   % 发运量不超过线路运力
            a = zeroAction(ctx.topo);
            a.burn(i) = b;
            a.f(eo) = (1 - tc.C.p.plant.loss(i)) * b;
            info = env.step(a);
            tc.verifyEqual(info.f(eo), (1 - tc.C.p.plant.loss(i)) * b, 'RelTol', 1e-12);
            tc.verifyEqual(info.trunc.f, 0, 'AbsTol', 1e-9);
        end

        function testBurnTruncation(tc)
            [env, ctx, x0] = tc.freshEnv();
            idx = ctx.idx;
            env = tc.resetWith(env, x0);
            arr = zeros(ctx.topo.nP, 1);
            for i = 1:ctx.topo.nP
                for e = ctx.inFe{ctx.topo.P(i)}
                    arr(i) = arr(i) + x0(idx.qFirst(e));
                end
            end
            av = x0(idx.IFe) + arr;
            a = zeroAction(ctx.topo);
            a.burn = 2 * av;
            info = env.step(a);
            tc.verifyEqual(info.b, av, 'RelTol', 1e-12);
            tc.verifyEqual(info.shortFe, av, 'RelTol', 1e-12);
        end

        function testMakeupFromReserve(tc)
            [env, ctx, x0] = tc.freshEnv();
            idx = ctx.idx;
            x0(idx.SFe(1)) = x0(idx.SFe(1)) + x0(idx.V);
            x0(idx.V) = 0;
            env = tc.resetWith(env, x0);
            sfe0 = x0(idx.SFe);
            a = zeroAction(ctx.topo);
            a.burn = 0.5 * x0(idx.IFe);
            info = env.step(a);
            lossT = sum(tc.C.p.plant.loss(:) .* info.b);
            tc.verifyGreaterThan(lossT, 0);
            tc.verifyEqual(info.u, lossT * ctx.shareR, 'RelTol', 1e-12);
            tc.verifyEqual(env.x(idx.V), 0, 'AbsTol', 1e-9 * tc.C.cNominal);
            tc.verifyEqual(env.x(idx.SFe), sfe0 + info.u, 'RelTol', 1e-12);
        end

        function testLpFeasibilization(tc)
            C = tc.C;
            seg = buildSegment(C.W(1), 40, 3, C.p);
            env = IronRustEnv(C.ctx);
            env.reset(2, C.cNominal, 0.6, struct('seg', seg));
            obs = env.getObs();
            lib = policyLibrary(C.p, C.topo, C.stats, C.p.seed);
            a = policyAct(obs, jointPolicy(lib, lib.alignedIds(:, 2)), C.ctx);
            a.bcap = a.bcap + 10 * C.cNominal;                % 远超库存的燃铁上限
            info = env.step(a);
            tc.verifyGreaterThan(info.trunc.b, 0);
            tc.verifyLessThanOrEqual(abs(sum(env.x) - C.cNominal) / C.cNominal, 1e-9);
        end
    end

    methods
        function [env, ctx, x0] = freshEnv(tc)
            ctx = tc.C.ctx;
            [x0, ~, ~] = initMaterial(tc.C.cNominal, 0.6, ctx, 'deterministic', []);
            env = IronRustEnv(ctx);
        end

        function env = resetWith(tc, env, x0)
            seg = buildSegment(tc.C.W(1), 10, 3, tc.C.p);
            env.reset(1, sum(x0), 0.6, struct('seg', seg, 'dispatchMode', 'direct', 'x0', x0, ...
                'gInv0', ones(tc.C.idx.nInv, 1), 'gLine0', ones(tc.C.topo.nE, 1)));
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
