classdef TestWeatherEventStats < matlab.unittest.TestCase
    methods (Test)
        function joinsOnlyTrulyAdjacentObservedYears(tc)
            [W, p] = fixture();
            W(1).calendarYear = 2020; W(2).calendarYear = 2021; W(3).calendarYear = 2023;
            s = estimateStats(W, 1:3, p, struct('mean', 2));
            tc.verifyEqual(sort(s.Druns), [2, 4]);
            tc.verifyEqual(s.Dmax, 4);
            tc.verifyEqual(s.qhat, 4 / 6, 'AbsTol', 1e-12);
            tc.verifyLessThanOrEqual(max(s.bootRaw.Dmax), 4);
        end

        function rightCensoringDoesNotInventAnExit(tc)
            [W, p] = fixture();
            W(1).reg(1:4) = [1, 2, 2, 2];
            s = estimateStats(W, 1, p, struct('mean', 2));
            tc.verifyEqual(s.qhat, 1);
        end

        function independentSyntheticYearsRemainSeparate(tc)
            [W, p] = fixture();
            s = estimateStats(W, 1:2, p, struct('mean', 2));
            tc.verifyEqual(sort(s.Druns), [2, 2]);
            tc.verifyEqual(s.Dmax, 2);
        end
    end
end

function [W, p] = fixture()
p = params_default('smoke');
p.weather.Y = 3; p.weather.daysPerYear = 4; p.stats.bootB = 50;
W = genWeatherYears(p, 9);
W(1).reg(1:4) = [1, 1, 2, 2];
W(2).reg(1:4) = [2, 2, 1, 1];
W(3).reg(1:4) = [2, 2, 3, 3];
end
