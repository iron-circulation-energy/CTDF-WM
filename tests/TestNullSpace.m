classdef TestNullSpace < matlab.unittest.TestCase
    %TESTNULLSPACE 零空间投影 P = I − (1/n)11ᵀ：投影后物料分量和为零；非物料分量不变；
    %   对任意满足 1ᵀu_mat = 0 的目标 u，‖P·v − u‖ ≤ ‖v − u‖；P 幂等。

    methods (Test)
        function testProperties(tc)
            rs = RandStream('twister', 'Seed', 8);
            n = 12;
            D = 30;
            B = 500;
            V = randn(rs, D, B);
            PV = nullSpaceProj(V, n);
            tc.verifyEqual(sum(PV(1:n, :), 1), zeros(1, B), 'AbsTol', 1e-12);
            tc.verifyEqual(PV(n + 1:end, :), V(n + 1:end, :));
            tc.verifyEqual(nullSpaceProj(PV, n), PV, 'AbsTol', 1e-12);
            U = randn(rs, D, B);
            U(1:n, :) = U(1:n, :) - mean(U(1:n, :), 1);
            tc.verifyLessThanOrEqual(sum((PV - U) .^ 2, 1), sum((V - U) .^ 2, 1) + 1e-12);
        end

        function testMatrixForm(tc)
            rs = RandStream('twister', 'Seed', 9);
            n = 6;
            v = randn(rs, n, 1);
            P = eye(n) - ones(n) / n;
            tc.verifyEqual(nullSpaceProj(v, n), P * v, 'AbsTol', 1e-14);
        end
    end
end
