classdef TestCTDFRegressions < matlab.unittest.TestCase
    methods (Test)
        function zeroDrawRiskIsFinite(tc)
            [model, ctx] = toyModel();
            rv = riskValue(model, zeros(5, 1), 10, zeros(2, 1), ctx, ...
                RandStream('twister', 'Seed', 4), struct('K', 8));
            tc.verifyEqual(rv.R, 0.5, 'AbsTol', 1e-12);
            tc.verifyTrue(all(isfinite([rv.Q, rv.R, rv.nodeFe, rv.nodeOx])));
        end

        function invalidDirichletConcentrationFailsClearly(tc)
            tc.verifyError(@() sampleDirichlet(0, 3, 2, RandStream('twister', 'Seed', 1)), ...
                'sampleDirichlet:alpha');
        end

        function datasetCacheChangesWithPhysicalCost(tc)
            C = makeTestCase();
            ctx = C.ctx;
            ctx.p.data.nTransitions = 2; ctx.p.data.episodeLen = 2;
            ctx.p.data.blockEpisodes = 1;
            lib = policyLibrary(ctx.p, C.topo, C.stats, 3);
            part = tempname;
            mkdir(part);
            cleanup = onCleanup(@() rmdir(part, 's')); %#ok<NASGU>
            a = collectDataset(ctx, C.W, lib, 1, C.cNominal, 7, part);
            ctx.p.cost.cHold = ctx.p.cost.cHold + 1;
            b = collectDataset(ctx, C.W, lib, 1, C.cNominal, 7, part);
            tc.verifyGreaterThan(mean(b.cost - a.cost), 0);
            tc.verifyEqual(b.S, a.S); % Holding price does not change physical transitions.
        end

        function stateStoresPhysicalCostQuantities(tc)
            C = makeTestCase();
            tc.verifyEqual(C.ctx.L.nZ, C.topo.nP + C.topo.nE + 7);
            seg = buildSegment(C.W(1), 1, 3, C.p);
            env = IronRustEnv(C.ctx);
            env.reset(3, C.cNominal, 0.5, struct('seg', seg));
            lib = policyLibrary(C.p, C.topo, C.stats, 3);
            info = env.step(policyAct(env.getObs(), jointPolicy(lib, 3 * ones(lib.nAgents, 1)), C.ctx));
            [total, components] = physicalQuantityCost(env.z, C.ctx, seg.carbon, seg.h2);
            tc.verifyEqual(total, info.cost, 'RelTol', 1e-12, 'AbsTol', 1e-5);
            tc.verifyEqual(components, info.z, 'RelTol', 1e-12, 'AbsTol', 1e-5);
            S = env.stateVector();
            tc.verifyEqual(stateReward(S, C.ctx), -info.cost / C.ctx.Cref, 'RelTol', 1e-12);
            prices = struct('carbon', seg.carbon + 10, 'h2', seg.h2 + 1);
            increase = 10 * C.p.backup.ef * info.bkMWh + C.p.cost.nh3PerH2 * info.nh3MWh;
            tc.verifyEqual(stateReward(S, C.ctx, prices), -(info.cost + increase) / C.ctx.Cref, ...
                'RelTol', 1e-12, 'AbsTol', 1e-9);
        end

        function zeroDrawPropertyBoundIsFinite(tc)
            [ds, nrm, ctx, lib, cfg] = makeTinyCTDFCase();
            cfg.nMat = nrm.n;
            [net, meta] = buildVelocityNet(nrm.D, lib.dimEmb, cfg, 3);
            model = struct('cfg', cfg, 'meta', meta, 'norm', nrm, 'gammaFinal', 0.99, ...
                'ema', structfun(@extractdata, net, 'UniformOutput', false), 'snaps', {{}});
            ctx.stats.deltaDbarP(:) = 0;
            gt = struct('S0', double(ds.S(:, 1)), 'c0', ds.c(1), ...
                'emb0', embeddingsFromIds(lib, ds.id(:, 1)), 'gammas', 0.99, ...
                'samples', {{ds.S(:, 2:3)}});
            vp = checkModelProperties(model, ctx, lib, ds, gt, struct(), struct('K', 2, 'nBatch', 2));
            tc.verifyTrue(isfinite(vp.riskErrL));
            tc.verifyTrue(all(isfinite(vp.riskErr{:,:}), 'all'));
        end
    end
end

function [model, ctx] = toyModel()
p = params_default('smoke');
cfg = p.ctdf;
cfg.width = 8; cfg.dCond = 8; cfg.dT = 4; cfg.nBlocks = 1;
cfg.nMat = 3; cfg.nOde = 1; cfg.precision = 'double'; cfg.useGPU = false;
[net, meta] = buildVelocityNet(5, 2, cfg, 2);
model = struct('cfg', cfg, 'meta', meta, 'gammaFinal', 0.9, 'useGPU', false);
model.ema = structfun(@extractdata, net, 'UniformOutput', false);
model.norm = struct('n', 3, 'D', 5, 'matScale', 3, 'mu', zeros(2, 1), ...
    'sd', ones(2, 1), 'cRef', 10);
ctx.Cref = 1;
ctx.L.iZ = 5;
ctx.L.xi = struct('carbon', 4, 'h2', 4);
keys = {'plantMWh', 'backupMWh', 'ammoniaMWh', 'shipmentTonnes', 'holdingTonnes', ...
    'makeupTonnes', 'curtailMWh', 'shortageMWh', 'overflowTonnes'};
for k = 1:numel(keys), ctx.L.z.(keys{k}) = 1; end
ctx.p = p;
ctx.p.plant.cop = 0;
ctx.lineCostPerT = 0;
ctx.margin = struct('GFe', zeros(1, 5), 'GOx', zeros(1, 5), 'gFe0', 0, 'gOx0', 0);
ctx.stats = struct('deltaDbarP', 0, 'deltaUbarR', 0);
end
