function out = checkMassBalance(ctx, W, years, c, nDays, seed)
%CHECKMASSBALANCE 活动质量守恒与荷电状态恒等式的数值检查。
%   在 dispatchMode = 'direct' 下以随机动作连续仿真 nDays 天（跨气象年片段衔接，物料状态逐段传递）：
%     随机燃铁量 b ~ U(0, 1.2)·(当日可用铁)、随机还原量 ρ ~ U(0, 1.2)·(当日可用锈)（超出部分由环境截断并记录）、
%     随机发运量（每条线路以 0.5 概率发运 U(0,1)·F̄_e，环境截断到源节点库存）。
%   逐日检查：
%     (1) 全网守恒 |1ᵀx_{k+1} − c| / c（环境内部容差 1e−9 时即报错）；
%     (2) 荷电状态恒等式 SOC_{k+1} − SOC_k = (Σ_j ρ_{j,k} + Σ_j u_{j,k} − Σ_i b_{i,k}) / c；
%         同时报告补铁项 Σu/c 的量级；
%     (3) 锈总量恒等式 ΔOx = Σ(1 − ℓ_i)b_i − Σρ_j，储备恒等式 ΔV = Σℓ_i b_i − Σu_j；
%     (4) 非负性 min(x) ≥ −1e−9·c。
%   输入：W 气象年结构体数组，years 使用的年份（取训练年），c 循环铁总质量（t），nDays 仿真天数。
%   输出 out：maxConsRel、maxSocErr、maxOxErr、maxVErr、minX、maxMakeupTerm、nDays、nShortFe、nShortOx、pass。

p = ctx.p;
idx = ctx.idx;
rs = RandStream('twister', 'Seed', seed);
segLen = min(300, p.weather.daysPerYear);
oxMask = (idx.matOf == 2);
x = [];
gInv = [];
gLine = [];
done = 0;
maxCons = 0;
maxSoc = 0;
maxOx = 0;
maxV = 0;
minX = inf;
maxMk = 0;
nShortFe = 0;
nShortOx = 0;
env = IronRustEnv(ctx);
while done < nDays
    y = years(randi(rs, numel(years)));
    len = min(segLen, nDays - done);
    d0 = randi(rs, [1, p.weather.daysPerYear - len + 1]);
    seg = buildSegment(W(y), d0, len, p);
    sc = struct('seg', seg, 'dispatchMode', 'direct');
    if isempty(x)
        env.reset(seed, c, 0.5, sc);
    else
        sc.x0 = x;
        sc.gInv0 = gInv;
        sc.gLine0 = gLine;
        env.reset(seed, c, 0.5, sc);
    end
    for t = 1:len
        x0 = env.x;
        soc0 = env.soc();
        ox0 = sum(x0(oxMask));
        v0 = x0(idx.V);
        % 当日可用量（含到达）
        arrFe = zeros(idx.n, 1);
        for e = 1:ctx.topo.nE
            arrFe(idx.lineTgt(e)) = arrFe(idx.lineTgt(e)) + x0(idx.qFirst(e));
        end
        avFe = x0(idx.IFe) + arrFe(idx.IFe);
        avOx = x0(idx.SOx) + arrFe(idx.SOx);
        a.burn = 1.2 * rand(rs, ctx.topo.nP, 1) .* avFe;
        a.red = 1.2 * rand(rs, ctx.topo.nR, 1) .* avOx;
        a.f = (rand(rs, ctx.topo.nE, 1) < 0.5) .* rand(rs, ctx.topo.nE, 1) .* ctx.topo.Fcap(:);
        a.o = false(ctx.topo.nP, 1);
        a.bcap = zeros(ctx.topo.nP, 1);
        a.beta = zeros(ctx.topo.nP, 1);
        a.rho = zeros(ctx.topo.nR, 1);
        info = env.step(a);
        x1 = env.x;
        nShortFe = nShortFe + any(info.shortFe > 1e-9);
        nShortOx = nShortOx + any(info.shortOx > 1e-9);
        maxCons = max(maxCons, abs(sum(x1) - c) / c);
        dSoc = env.soc() - soc0;
        pred = (sum(info.rho) + sum(info.u) - sum(info.b)) / c;
        maxSoc = max(maxSoc, abs(dSoc - pred));
        maxMk = max(maxMk, sum(info.u) / c);
        dOx = sum(x1(oxMask)) - ox0;
        maxOx = max(maxOx, abs(dOx - (sum((1 - p.plant.loss(:)) .* info.b) - sum(info.rho))) / c);
        dV = x1(idx.V) - v0;
        maxV = max(maxV, abs(dV - (sum(p.plant.loss(:) .* info.b) - sum(info.u))) / c);
        minX = min(minX, min(x1) / c);
    end
    x = env.x;
    gInv = env.gInv;
    gLine = env.gLine;
    done = done + len;
end
out.nDays = done;
out.maxConsRel = maxCons;
out.maxSocErr = maxSoc;
out.maxOxErr = maxOx;
out.maxVErr = maxV;
out.minXRel = minX;
out.maxMakeupTerm = maxMk;
out.nShortFe = nShortFe;
out.nShortOx = nShortOx;
out.pass = maxCons <= 1e-9 && maxSoc <= 1e-9 && maxOx <= 1e-9 && maxV <= 1e-9 && minX >= -1e-9;
end
