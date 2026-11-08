classdef TestODE < matlab.unittest.TestCase
    %TESTODE 中点法生成 ODE（odeMidpoint，零空间投影）：
    %   (1) 速度场经零空间投影时，物料分量之和全程守恒（双精度舍入误差量级）；不投影时一般不守恒；
    %   (2) 二阶收敛：时间嵌入权重置零使速度场光滑且与 t 无关，相对 1280 步参考解，20 步与 40 步误差之比约为 4；
    %   (3) dlarray 输入与数值输入结果一致（训练与采样共用同一前向函数）。

    properties
        net
        meta
        cfg
        n = 7
        D = 16
        dimW = 5
    end

    methods (TestClassSetup)
        function setup(tc)
            cfg = struct('width', 32, 'dCond', 16, 'dT', 8, 'nBlocks', 2, 'precision', 'double', ...
                'useNullSpaceProj', true, 'nMat', tc.n);
            [nt, mt] = buildVelocityNet(tc.D, tc.dimW, cfg, 3);
            rs = RandStream('twister', 'Seed', 4);
            fn = fieldnames(nt);
            for m = 1:numel(fn)
                v = extractdata(nt.(fn{m}));
                if startsWith(fn{m}, 'W2')
                    v = 0.3 * randn(rs, size(v)) / sqrt(size(v, 2));
                elseif strcmp(fn{m}, 'Wt1')
                    v = zeros(size(v));                % 去掉高频时间特征，便于检验收敛阶
                elseif strcmp(fn{m}, 'Wout')
                    v = v * 50;
                end
                nt.(fn{m}) = v;
            end
            tc.net = nt;
            tc.meta = mt;
            tc.cfg = cfg;
        end
    end

    methods (Test)
        function testConservation(tc)
            rs = RandStream('twister', 'Seed', 5);
            B = 64;
            [X0, cond, w] = tc.inputs(rs, B);
            X1 = odeMidpoint(tc.net, X0, cond, w, 1, 10, tc.meta, tc.cfg);
            tc.verifyEqual(sum(X1(1:tc.n, :), 1), sum(X0(1:tc.n, :), 1), 'AbsTol', 1e-10);
            c2 = tc.cfg;
            c2.useNullSpaceProj = false;
            X2 = odeMidpoint(tc.net, X0, cond, w, 1, 10, tc.meta, c2);
            tc.verifyGreaterThan(max(abs(sum(X2(1:tc.n, :), 1) - sum(X0(1:tc.n, :), 1))), 1e-8);
        end

        function testSecondOrder(tc)
            rs = RandStream('twister', 'Seed', 6);
            B = 32;
            [X0, cond, w] = tc.inputs(rs, B);
            ref = odeMidpoint(tc.net, X0, cond, w, 1, 1280, tc.meta, tc.cfg);
            e20 = max(abs(odeMidpoint(tc.net, X0, cond, w, 1, 20, tc.meta, tc.cfg) - ref), [], 'all');
            e40 = max(abs(odeMidpoint(tc.net, X0, cond, w, 1, 40, tc.meta, tc.cfg) - ref), [], 'all');
            tc.verifyGreaterThan(e20 / e40, 2.5);
            tc.verifyLessThan(e20 / e40, 6.5);
        end

        function testDlarrayConsistency(tc)
            rs = RandStream('twister', 'Seed', 7);
            B = 8;
            [X0, cond, w] = tc.inputs(rs, B);
            t = rand(rs, 1, B);
            v1 = velocityForward(tc.net, X0, cond, w, t, tc.meta);
            nd = structfun(@dlarray, tc.net, 'UniformOutput', false);
            v2 = extractdata(velocityForward(nd, dlarray(X0), dlarray(cond), dlarray(w), dlarray(t), tc.meta));
            tc.verifyEqual(v2, v1, 'AbsTol', 1e-10);
        end
    end

    methods
        function [X0, cond, w] = inputs(tc, rs, B)
            X0 = randn(rs, tc.D, B);
            X0(1:tc.n, :) = tc.n * sampleDirichlet(1, tc.n, B, rs);
            cond = randn(rs, tc.D + 1, B);
            w = rand(rs, tc.dimW, B);
        end
    end
end
