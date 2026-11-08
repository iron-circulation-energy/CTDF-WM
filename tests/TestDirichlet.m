classdef TestDirichlet < matlab.unittest.TestCase
    %TESTDIRICHLET Dirichlet(α·1) 抽样（；Marsaglia–Tsang，不依赖统计工具箱）：非负、列和为 1、
    %   均值 1/n、方差 (n − 1)/(n²(nα + 1))，同一种子可复现；源分布物料分量和为 n（缩放单纯形）。

    methods (Test)
        function testMoments(tc)
            n = 5;
            B = 4e4;
            for alpha = [0.5, 1, 2]
                rs = RandStream('twister', 'Seed', 10);
                X = sampleDirichlet(alpha, n, B, rs);
                tc.verifyGreaterThanOrEqual(min(X(:)), 0);
                tc.verifyEqual(sum(X, 1), ones(1, B), 'AbsTol', 1e-12);
                tc.verifyEqual(mean(X, 2), ones(n, 1) / n, 'AbsTol', 0.01);
                vth = (n - 1) / (n ^ 2 * (n * alpha + 1));
                tc.verifyEqual(var(X, 0, 2), vth * ones(n, 1), 'RelTol', 0.08);
            end
        end

        function testReproducible(tc)
            X1 = sampleDirichlet(0.7, 4, 100, RandStream('twister', 'Seed', 3));
            X2 = sampleDirichlet(0.7, 4, 100, RandStream('twister', 'Seed', 3));
            tc.verifyEqual(X1, X2);
        end

        function testSourceOnScaledSimplex(tc)
            meta.dimX = 20;
            cfg = struct('sourceType', 'dirichlet', 'alphaDir', 1, 'precision', 'double');
            X0 = sampleSource(meta, 8, 8, 500, cfg, RandStream('twister', 'Seed', 4));
            tc.verifyEqual(sum(X0(1:8, :), 1), 8 * ones(1, 500), 'AbsTol', 1e-12);
            tc.verifyGreaterThan(min(min(X0(1:8, :))), 0);
        end
    end
end
