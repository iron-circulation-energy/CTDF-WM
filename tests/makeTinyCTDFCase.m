function [ds, nrm, ctx, lib, cfg] = makeTinyCTDFCase()
%MAKETINYCTDFCASE Small deterministic numeric fixture for training regressions.
C = makeTestCase();
ctx = C.ctx;
lib = policyLibrary(C.p, C.topo, C.stats, 1);
env = IronRustEnv(ctx);
env.reset(1, C.cNominal, 0.5, struct('seg', buildSegment(C.W(1), 1, 3, C.p)));
ds.S = repmat(single(env.stateVector()), 1, 12);
rs = RandStream('twister', 'Seed', 19);
ds.S(1:ctx.L.n, :) = single(C.cNominal * sampleDirichlet(1, ctx.L.n, 12, rs));
ds.from = 1:11;
ds.to = 2:12;
ds.id = repmat(1 + mod(0:10, lib.nOpt), lib.nAgents, 1);
ds.c = C.cNominal * ones(1, 12);
ds.pert = false(1, 11);
nrm = buildNormalizer(ds, ctx);
cfg = C.p.ctdf;
cfg.width = 16; cfg.dCond = 16; cfg.dT = 8; cfg.nBlocks = 1;
cfg.batch = 8; cfg.nMicro = 2; cfg.nOde = 2; cfg.stepsPerStage = 2;
cfg.gammaStages = [0.8, 0.99]; cfg.diagEvery = 2; cfg.snapEvery = 1;
cfg.useGPU = false; cfg.precision = 'double';
end
