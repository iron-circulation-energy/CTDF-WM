classdef TestWeatherFit < matlab.unittest.TestCase
    %TESTWEATHERFIT 实测数据接口（prepareRealData 链路）的一致性：
    %   (1) fitWeatherModel 估计参数后，readWeatherCSV 反解的隐状态经 weatherEnergies 精确复现日电量（观测方程互逆），
    %       转移矩阵为随机矩阵，季节均值等于训练年样本均值；
    %   (2) windCF 的切入、额定、切出边界与单调性；
    %   (3) era5ToHourly：闰年删除 2 月 29 日后为 24×365，光伏夜间为零、正午附近最大且不超过 1，风速密度修正方向正确。

    methods (Test)
        function testRoundTrip(tc)
            p = params_default('smoke');
            p.weather.Y = 6;
            p.weather.train = 1:4;
            p.weather.val = 5;
            p.weather.test = 6;
            W = genWeatherYears(p, 11);
            Y = numel(W);
            EW = zeros(Y, 365);
            ES = EW;
            EL = EW;
            for y = 1:Y
                EW(y, :) = W(y).EW(1:365);
                ES(y, :) = W(y).ES(1:365);
                EL(y, :) = W(y).EL(1:365);
            end
            q = fitWeatherModel(p, EW, ES, EL, p.weather.train, []);
            tc.verifyEqual(sum(q.weather.P, 2), ones(3, 1), 'AbsTol', 1e-12);
            tc.verifyGreaterThanOrEqual(q.weather.P(:), 0);
            tc.verifyEqual(q.weather.cfW0, mean(reshape(EW(1:4, :), [], 1)) / (p.re.capW * 24), 'RelTol', 1e-9);
            f = [tempname, '.csv'];
            yy = repmat((1:Y)', 1, 365)';
            dd = repmat((1:365)', 1, Y);
            T = table(yy(:), dd(:), reshape(EW', [], 1), reshape(ES', [], 1), reshape(EL', [], 1), ...
                'VariableNames', {'year', 'day', 'EW', 'ES', 'EL'});
            writetable(T, f);
            c = onCleanup(@() delete(f));
            R = readWeatherCSV(f, q);
            tc.verifyNumElements(R, Y);
            for y = 1:Y
                [ew, es, el] = weatherEnergies(R(y).reg, R(y).eW, R(y).eS, R(y).eL, R(y).doy, q);
                tc.verifyEqual(ew, R(y).EW, 'RelTol', 1e-9, 'AbsTol', 1e-6);
                tc.verifyEqual(es, R(y).ES, 'RelTol', 1e-9, 'AbsTol', 1e-6);
                tc.verifyEqual(el, R(y).EL, 'RelTol', 1e-9);
            end
            % 最后一年只作尾部
            q.weather.csvLastIsTail = true;
            R2 = readWeatherCSV(f, q);
            tc.verifyNumElements(R2, Y - 1);
            tc.verifyEqual(R2(end).EW(366:end), EW(Y, 1:q.weather.tailDays), 'RelTol', 1e-12);
        end

        function testWindCurve(tc)
            p = params_default('haoji');
            e = p.weather.era5;
            U = [0, 2.9, e.windVin, 0.5 * (e.windVin + e.windVr), e.windVr, 24.9, e.windVout, 30];
            cf = windCF(U, e);
            tc.verifyEqual(cf([1, 2, 3, 7, 8]), zeros(1, 5));
            tc.verifyEqual(cf([5, 6]), (1 - e.windLoss) * ones(1, 2), 'AbsTol', 1e-12);
            tc.verifyGreaterThan(cf(4), 0);
            tc.verifyLessThan(cf(4), 1 - e.windLoss);
            u = linspace(0, e.windVr, 200);
            tc.verifyGreaterThanOrEqual(diff(windCF(u, e)), 0);
        end

        function testEra5Hourly(tc)
            p = params_default('haoji');
            e = p.weather.era5;
            site = e.reSites(1);
            t = datetime(2020, 1, 1, 0, 0, 0) + hours(0:8783)';     % 闰年
            hr = hour(t);
            G = 800 * max(0, sin(pi * (hr - 6) / 12));                 % 示意辐照（W/m²）
            T = table(t, 8 * ones(8784, 1), 15 * ones(8784, 1), 850 * ones(8784, 1), G, 0.8 * G, 0.2 * G, ...
                'VariableNames', {'time', 'wind_speed_100m', 'temperature_2m', 'surface_pressure', ...
                'shortwave_radiation', 'direct_radiation', 'diffuse_radiation'});
            o = era5ToHourly(T, site, 'pv', e);
            tc.verifySize(o.CF, [24, 365]);
            tc.verifyEqual(o.CF([1:4, 22:24], :), zeros(7, 365));
            tc.verifyLessThanOrEqual(max(o.CF(:)), 1);
            [~, hmax] = max(mean(o.CF, 2));
            tc.verifyTrue(hmax >= 11 && hmax <= 15);
            w = era5ToHourly(T, site, 'wind', e);
            tc.verifySize(w.U, [24, 365]);
            rho = 850 * 100 / (287.05 * (15 + 273.15));                % 约 1.03 kg/m³（高原）
            tc.verifyEqual(w.U(1), 8 * (rho / 1.225) ^ (1 / 3), 'RelTol', 1e-12);
            tc.verifyLessThan(w.U(1), 8);
            m = era5ToHourly(T, site, 'temp', e);
            tc.verifyEqual(m.Tday, 15 * ones(1, 365), 'AbsTol', 1e-12);
        end
    end
end
