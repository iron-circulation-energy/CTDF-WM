classdef TestW1 < matlab.unittest.TestCase
    %TESTW1 1-Wasserstein 距离（wasserstein1）：
    %   (1) 一维等样本数时精确解等于排序差的均值；(2) 平移不变：W1(μ, μ + v) = ‖v‖；
    %   (3) 不等样本数（linprog 运输问题）与等价的等样本数（matchpairs）结果一致；
    %   (4) 一维时切片 W1 与精确解一致；多维时二者量级一致（交叉校验，比值在 [0.3, 3] 内）。

    methods (Test)
        function testOneDim(tc)
            rs = RandStream('twister', 'Seed', 1);
            x = randn(rs, 1, 60);
            y = 0.5 + 2 * randn(rs, 1, 60);
            d = wasserstein1(x, y, struct('method', 'exact'));
            tc.verifyEqual(d, mean(abs(sort(x) - sort(y))), 'AbsTol', 1e-10);
            ds = wasserstein1(x, y, struct('method', 'sliced', 'nDirs', 16, 'seed', 2));
            tc.verifyEqual(ds, d, 'AbsTol', 1e-10);
        end

        function testTranslation(tc)
            rs = RandStream('twister', 'Seed', 3);
            X = randn(rs, 4, 40);
            v = [1; -2; 0.5; 3];
            d = wasserstein1(X, X + v, struct('method', 'exact'));
            tc.verifyEqual(d, norm(v), 'AbsTol', 1e-9);
        end

        function testUnequalSizes(tc)
            rs = RandStream('twister', 'Seed', 4);
            X = randn(rs, 3, 20);
            Y = randn(rs, 3, 20) + 1;
            d1 = wasserstein1(X, Y, struct('method', 'exact'));
            d2 = wasserstein1(X, [Y, Y], struct('method', 'exact'));
            tc.verifyEqual(d2, d1, 'RelTol', 1e-6);
            tc.verifyEqual(wasserstein1(X, [X, X], struct('method', 'exact')), 0, 'AbsTol', 1e-8);
        end

        function testSlicedCrossCheck(tc)
            rs = RandStream('twister', 'Seed', 5);
            X = randn(rs, 3, 200);
            Y = 0.7 * randn(rs, 3, 200) + [1; 0; -1];
            de = wasserstein1(X, Y, struct('method', 'exact'));
            ds = wasserstein1(X, Y, struct('method', 'sliced', 'nDirs', 256, 'seed', 6));
            tc.verifyGreaterThan(ds / de, 0.3);
            tc.verifyLessThan(ds / de, 3);
        end
    end
end
