classdef TestInnerLP < matlab.unittest.TestCase
    %TESTINNERLP 内层 24 小时线性规划（—(12)）：随机生成 100 组输入，检查
    %   功率平衡残差 ≤ 1e−6；电厂日电量上限 Σ_t p_{i,t} − E^NH3_i ≤ η_i·h_Fe·b̄_i；掺氨上限 E^NH3_i ≤ β_i·p̄_i·24；
    %   E^NH3_i ≤ Σ_t p_{i,t}（反算燃铁量非负）；还原日电量 Σ_t p^red_{j,t} ≤ E^ch_j；出力上下限；
    %   由 反算的 b、ρ 满足 0 ≤ b ≤ b̄、0 ≤ ρ ≤ E^ch/e^red。

    properties
        C
    end

    methods (TestClassSetup)
        function setup(tc)
            tc.C = makeTestCase();
        end
    end

    methods (Test)
        function testRandomInputs(tc)
            C = tc.C;
            p = C.p;
            nP = C.topo.nP;
            nR = C.topo.nR;
            rs = RandStream('twister', 'Seed', 11);
            eRed = p.iron.hFe * p.station.kappa(:) ./ p.station.etaEl(:) + p.station.epsAux(:);
            tol = 1e-6;
            for k = 1:100
                d = randi(rs, 365);
                EW = p.re.capW * 24 * 0.6 * rand(rs);
                ES = p.re.capS * 24 * 0.3 * rand(rs);
                EL = p.load.mean * 24 * (0.8 + 0.4 * rand(rs));
                [RE, D] = hourlyProfiles(EW, ES, EL, d, p.weather);
                o = rand(rs, nP, 1) < 0.6;
                pLast = (rand(rs, nP, 1) < 0.5) .* (p.plant.pmin(:) + rand(rs, nP, 1) .* (p.plant.pmax(:) - p.plant.pmin(:)));
                eta = p.plant.etaSt(:) .* (1 - 0.1 * rand(rs, nP, 1));
                beta = p.plant.betaMax(:) .* rand(rs, nP, 1);
                Emin = plantMinEnergy(p, pLast);
                bcap = (Emin + rand(rs, nP, 1) .* p.plant.pmax(:) * 24) ./ (eta * p.iron.hFe);
                Ech = rand(rs, nR, 1) .* p.station.pRedMax(:) * 24;
                day = struct('RE', RE, 'D', D, 'o', o, 'bcap', bcap, 'beta', beta, 'Ech', Ech, ...
                    'redAvail', ones(nR, 1), 'pLast', pLast .* o, 'etaEff', eta, 'carbon', 100, 'h2', 25);
                r = innerDispatchLP(C.ctx.lpT, day, p);
                tc.verifyLessThanOrEqual(r.balRes, tol);
                Ep = sum(r.p, 2);
                tc.verifyLessThanOrEqual(Ep - r.eNH3, eta * p.iron.hFe .* bcap + tol);
                tc.verifyLessThanOrEqual(r.eNH3, beta .* p.plant.pmax(:) * 24 + tol);
                tc.verifyLessThanOrEqual(r.eNH3, Ep + tol);
                tc.verifyLessThanOrEqual(sum(r.red, 2), Ech + tol);
                tc.verifyLessThanOrEqual(max(r.p, [], 2), p.plant.pmax(:) .* o + tol);
                on = find(o);
                for i = on'
                    tc.verifyGreaterThanOrEqual(min(r.p(i, :)), p.plant.pmin(i) - tol);
                end
                b = max(0, (Ep - r.eNH3) ./ (eta * p.iron.hFe));
                rho = sum(r.red, 2) ./ eRed;
                tc.verifyLessThanOrEqual(b, bcap + tol);
                tc.verifyLessThanOrEqual(rho, Ech ./ eRed + tol);
                tc.verifyGreaterThanOrEqual(min([r.cur, r.shed, r.bk, r.ovg]), -tol);
            end
        end
    end
end
