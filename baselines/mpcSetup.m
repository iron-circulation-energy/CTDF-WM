function mpc = mpcSetup(ctx, W, trainYears, opts)
%MPCSETUP 随机 MPC（M2）的静态数据：时域、场景库与日物料线性映射。
%   日物料映射与环境 step 的顺序一致（—(5)）：
%       x_{k+1} = M_x·x_k + M_b·b_k + M_ρ·ρ_k + M_f·f_k
%   M_x：到达 a_{e,k} = q_{e,1,k} 计入目标库存，其余管道格前移一格；
%   M_b：燃铁 b_i 扣减 I^Fe_i，(1 − ℓ_i)·b_i 进入 I^Ox_i，损耗 ℓ_i·b_i 进入 V 后当日按还原站份额补回
%        （u_j = 份额_j·Σ_i ℓ_i·b_i，与环境补铁规则在 V 充足时一致）；
%   M_ρ：还原 ρ_j 由 S^Ox_j 转入 S^Fe_j；M_f：发运自源节点进入管道最远格 q_{e,τ_e}。
%   各矩阵列和为零（M_x 列和为 1），故 1ᵀx 守恒。
%   场景库：训练年份每日的气象状态、日序与日电量，供按“当前气象状态 + 季节窗口”条件抽样。
%   opts 字段（可选）：S、horizonFactor、ironValueMult、terminalNet（覆盖 p.mpc，验证集调参用）。
%   输出 mpc：S、Hm、Hf、T4、gamma、solver、bank、M（Mx、Mb、Mr、Mf）、lay（变量布局）。

p = ctx.p;
if nargin < 4
    opts = struct();
end
mpc.S = getf(opts, 'S', p.mpc.S);
hf = getf(opts, 'horizonFactor', p.mpc.horizonFactor);
mpc.Hm = max(ceil(hf * ctx.Tl.mean - 1e-9), ceil(ctx.Tl.mean) + 1);
mpc.Hf = min(p.mpc.Hf, mpc.Hm - 1);
mpc.T4 = p.mpc.periods;
if mod(24, mpc.T4) ~= 0
    error('mpcSetup:periods', '每日时段数须整除 24。');
end
mpc.gamma = p.mpc.gamma;
mpc.terminalMode = getf(p.mpc, 'terminalMode', 'shortfall');
mpc.ironValueMult = getf(opts, 'ironValueMult', getf(p.mpc, 'ironValueMult', 1));
mpc.oxValueFrac = getf(p.mpc, 'oxValueFrac', 0.5);
mpc.terminalNet = logical(getf(opts, 'terminalNet', getf(p.mpc, 'terminalNet', false)));
mpc.solver = p.mpc.solver;

% 场景库
bank.year = [];
bank.day = [];
bank.reg = [];
bank.doy = [];
bank.Y = cell(1, numel(trainYears));
for m = 1:numel(trainYears)
    Wy = W(trainYears(m));
    bank.Y{m} = struct('reg', Wy.reg, 'doy', Wy.doy, 'EW', Wy.EW, 'ES', Wy.ES, 'EL', Wy.EL, 'N', Wy.N);
    dd = validWeatherStarts(Wy,p,mpc.Hm,trainYears);
    bank.year = [bank.year, m * ones(1, numel(dd))];
    bank.day = [bank.day, dd];
    bank.reg = [bank.reg, Wy.reg(dd)];
    bank.doy = [bank.doy, Wy.doy(dd)];
end
mpc.bank = bank;
if isempty(bank.day)
    error('mpcSetup:emptyBank','No training-only weather windows are long enough for the MPC horizon.');
end

% 日物料线性映射
idx = ctx.idx;
topo = ctx.topo;
n = idx.n;
nP = topo.nP;
nR = topo.nR;
nE = topo.nE;
Mx = speye(n);
for e = 1:nE
    q = idx.q{e};
    Mx(q, q) = 0; %#ok<SPRIX>
    Mx(idx.lineTgt(e), q(1)) = 1; %#ok<SPRIX>
    for d = 1:numel(q) - 1
        Mx(q(d), q(d + 1)) = 1; %#ok<SPRIX>
    end
end
Mb = sparse(n, nP);
for i = 1:nP
    li = p.plant.loss(i);
    Mb(idx.IFe(i), i) = -1; %#ok<SPRIX>
    Mb(idx.IOx(i), i) = 1 - li; %#ok<SPRIX>
    Mb(idx.SFe, i) = Mb(idx.SFe, i) + li * ctx.shareR; %#ok<SPRIX>
end
Mr = sparse(n, nR);
for j = 1:nR
    Mr(idx.SOx(j), j) = -1; %#ok<SPRIX>
    Mr(idx.SFe(j), j) = 1; %#ok<SPRIX>
end
Mf = sparse(n, nE);
for e = 1:nE
    Mf(idx.lineSrc(e), e) = -1; %#ok<SPRIX>
    Mf(idx.qLast(e), e) = 1; %#ok<SPRIX>
end
chk = max(abs([sum(Mx, 1) - 1, sum(Mb, 1), sum(Mr, 1), sum(Mf, 1)]));
if chk > 1e-12
    error('mpcSetup:conservation', '日物料映射不守恒（列和偏差 %.2e）。', chk);
end
mpc.M = struct('Mx', Mx, 'Mb', Mb, 'Mr', Mr, 'Mf', Mf);
% 终端储量价值的位置修正（terminalNet）：各分量扣除其送达使用点的最低物流成本——铁送达任一电厂、锈送达任一还原站，
% 在途分量从所在线路终点起算（本线路运费已在发运时计入）。使时域末端的发运不因“只付运费、不增价值”而被压缩。
mpc.termDeduct = zeros(n, 1);
if mpc.terminalNet
    dist = zeros(topo.nNodes, 2);
    for mat = 1:2
        dmat = inf(topo.nNodes, 1);
        if mat == 1
            dmat(topo.P) = 0;
        else
            dmat(topo.R) = 0;
        end
        for it = 1:topo.nNodes
            for e = find(topo.mat(:)' == mat)
                dmat(topo.from(e)) = min(dmat(topo.from(e)), ctx.lineCostPerT(e) + dmat(topo.to(e)));
            end
        end
        dmat(~isfinite(dmat)) = 0;
        dist(:, mat) = dmat;
    end
    for g = 1:topo.nNodes
        for mat = 1:2
            k = idx.nodeInv(g, mat);
            if k > 0
                mpc.termDeduct(k) = dist(g, mat);
            end
        end
    end
    for e = 1:nE
        mpc.termDeduct(idx.q{e}) = dist(topo.to(e), topo.mat(e));
    end
end

% 变量布局（单日块）
T4 = mpc.T4;
lay.iB = (1:nP)';
lay.iR = nP + (1:nR)';
lay.iF = nP + nR + (1:nE)';
lay.iN = nP + nR + nE + (1:nP)';
o = nP + nR + nE + nP;
lay.iP = o + reshape(1:nP * T4, nP, T4);
o = o + nP * T4;
lay.iRd = o + reshape(1:nR * T4, nR, T4);
o = o + nR * T4;
lay.iBk = o + (1:T4);
o = o + T4;
lay.iCu = o + (1:T4);
o = o + T4;
lay.iSh = o + (1:T4);
o = o + T4;
lay.iOg = o + (1:T4);
o = o + T4;
lay.iX = o + (1:n)';
o = o + n;
lay.iOv = o + (1:idx.nInv)';
lay.nb = o + idx.nInv;
lay.nEqB = n + nP + nR + T4;
mpc.lay = lay;
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = d;
end
end
