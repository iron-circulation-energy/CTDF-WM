classdef TestSimplexProjection < matlab.unittest.TestCase
    %TESTSIMPLEXPROJECTION 缩放单纯形欧氏投影 Π（Duchi 等排序算法，终端投影）：可行性、幂等性、非扩张性，
    %   并与二分法求阈值 θ（Σ max(y − θ, 0) = s）的独立实现比较最优性。

    methods (Test)
        function testFeasibleAndOptimal(tc)
            rs = RandStream('twister', 'Seed', 5);
            n = 20;
            B = 200;
            s = 3.7;
            Y = 2 * randn(rs, n, B);
            X = projectSimplex(Y, s);
            tc.verifyGreaterThanOrEqual(min(X(:)), 0);
            tc.verifyEqual(sum(X, 1), s * ones(1, B), 'AbsTol', 1e-12);
            for b = 1:B
                th = bisectTheta(Y(:, b), s);
                tc.verifyEqual(X(:, b), max(Y(:, b) - th, 0), 'AbsTol', 1e-9);
            end
        end

        function testIdempotentAndNonexpansive(tc)
            rs = RandStream('twister', 'Seed', 6);
            n = 15;
            B = 100;
            s = 15;
            A = randn(rs, n, B) * 3;
            Bm = randn(rs, n, B) * 3;
            PA = projectSimplex(A, s);
            PB = projectSimplex(Bm, s);
            tc.verifyEqual(projectSimplex(PA, s), PA, 'AbsTol', 1e-12);
            dP = sqrt(sum((PA - PB) .^ 2, 1));
            d0 = sqrt(sum((A - Bm) .^ 2, 1));
            tc.verifyLessThanOrEqual(dP, d0 + 1e-12);
        end

        function testPerColumnScale(tc)
            rs = RandStream('twister', 'Seed', 7);
            Y = rand(rs, 8, 10);
            s = 1 + rand(rs, 1, 10);
            X = projectSimplex(Y, s);
            tc.verifyEqual(sum(X, 1), s, 'AbsTol', 1e-12);
        end
    end
end

function th = bisectTheta(y, s)
lo = min(y) - s - 1;
hi = max(y);
for it = 1:200
    mid = 0.5 * (lo + hi);
    if sum(max(y - mid, 0)) > s
        lo = mid;
    else
        hi = mid;
    end
end
th = 0.5 * (lo + hi);
end
