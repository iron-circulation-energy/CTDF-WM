function dg = runDiagMass(C, ref, years, seed, pMult, cMass)
%RUNDIAGMASS 循环质量分布诊断：沿 M0 轨迹逐日记录铁与锈在各环节的存量（不训练、不改模型参数）。
%   环节：电厂铁、电厂锈、枢纽铁、枢纽锈、还原站铁、还原站锈、在途铁、在途锈（t）。
%   分别给出全部评估日、失负荷日、失负荷前 3 日的平均占比，并给出还原站日还原能力与实际还原量、
%   电厂铁粉料仓容量，用于判断瓶颈在物流配置（铁滞留在上游）还是在还原环节（锈积压待还原）。
%   pMult、cMass（可选）：还原功率倍数与循环质量（t）；给出时重建算例，并在该设计下重新选取验证成本最低的候选固定策略。

if nargin >= 5 && ~isempty(pMult) && pMult ~= 1
    pv = C.p;
    pv.station.pRedMax = pMult * pv.station.pRedMax;
    pv = deriveParams(pv);
    W0 = C.W;
    C = buildCase(pv, W0);
    lib = policyLibrary(pv, C.topo, C.stats, pv.seed);
    ref = referencePolicy(C.ctx, C.W, lib, years, ifelse(nargin >= 6 && ~isempty(cMass), cMass, C.cNominal), seed);
end
if nargin >= 6 && ~isempty(cMass)
    C.cNominal = cMass;
end
p = C.p;
ctx = C.ctx;
W = C.W;
idx = ctx.idx;
topo = ctx.topo;
eFe = find(topo.mat == 1);
eOx = find(topo.mat == 2);
specs = makeEvalSpecs(p, years, seed, {'normal'}, C.cNominal);
names = {'plantFe', 'plantOx', 'hubFe', 'hubOx', 'stationFe', 'stationOx', 'transitFe', 'transitOx'};
allM = [];
allShed = [];
allRho = [];
for k = 1:numel(specs)
    sp = specs(k);
    [seg, cap] = buildEvalSegment(ctx, W, sp);
    env = IronRustEnv(ctx);
    env.reset(sp.seed, sp.c, sp.initSOC, struct('seg', seg, 'capSched', cap, 'initMode', 'deterministic'));
    Mk = zeros(numel(names), sp.len);
    shk = zeros(1, sp.len);
    rk = zeros(1, sp.len);
    for t = 1:sp.len
        obs = env.getObs();
        x = obs.x;
        qFe = 0;
        for e = eFe(:)'
            qFe = qFe + sum(x(idx.q{e}));
        end
        qOx = 0;
        for e = eOx(:)'
            qOx = qOx + sum(x(idx.q{e}));
        end
        Mk(:, t) = [sum(x(idx.IFe)); sum(x(idx.IOx)); sum(x(idx.HFe)); sum(x(idx.HOx)); sum(x(idx.SFe)); ...
            sum(x(idx.SOx)); qFe; qOx];
        info = env.step(policyAct(obs, ref.w, ctx));
        shk(t) = info.shed;
        rk(t) = sum(info.rho);
    end
    ev = (sp.warmup + 1):sp.len;
    allM = [allM, Mk(:, ev)]; %#ok<AGROW>
    allShed = [allShed, shk(ev)]; %#ok<AGROW>
    allRho = [allRho, rk(ev)]; %#ok<AGROW>
end
tot = sum(allM, 1);
frac = allM ./ max(tot, eps);
isS = allShed > 1e-3;
pre = false(size(isS));
for t = find(isS)
    pre(max(1, t - 3):max(1, t - 1)) = true;
end
pre = pre & ~isS;
dg.share = array2table([mean(frac, 2), mean(frac(:, isS), 2), mean(frac(:, pre), 2), mean(allM, 2) / 1e3], ...
    'RowNames', names, 'VariableNames', {'allDays', 'shedDays', 'pre3Days', 'meanKt'});
dg.refName = ref.name;
dg.summary = struct('years', numel(specs), 'totalKt', mean(tot) / 1e3, 'shedDays', nnz(isS), ...
    'rhoMaxSumTpd', sum(p.station.rhoMax), 'rhoActualMeanTpd', mean(allRho), ...
    'rhoActualOnShedDaysTpd', mean(allRho(isS)), 'plantCapFeKt', sum(p.plant.capFe) / 1e3, ...
    'hubCapFeKt', sum(p.hub.capFe) / 1e3, 'stationCapFeKt', sum(p.station.capFe) / 1e3, ...
    'PhiTpd', C.stats.Phi, 'deltaDTpd', C.stats.deltaD);
end

function v = ifelse(c, a, b)
if c
    v = a;
else
    v = b;
end
end
