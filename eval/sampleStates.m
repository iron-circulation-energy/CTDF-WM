function st = sampleStates(ctx, W, lib, years, nStates, w0, c, seed)
%SAMPLESTATES 抽取后继测度真值与模型检验用的测试状态。
%   第 m 个状态：在年份 years(1 + mod(m − 1, numel(years))) 中随机起始日 d0，按参考策略 π_{w0} 运行
%   warmup + U{0..30} 天后取当前状态（物料按确定性方式初始化，循环铁总质量 c）。
%   每个状态分配一个候选联合策略 ids(:, m) = lib.candidates(:, 1 + mod(m − 1, nCand))，用于检验以 w 为条件的模型。
%   输出 st：S0（D×m）、c0（1×m）、ids、emb0（dimW×m）、snap（物料 x、品质 gInv/gLine、pLast、z）、
%            hs（当日隐状态与实际日电量：reg、eW、eS、eL、doy、EW、ES、EL、carbon、h2）、year、day。

p = ctx.p;
rs = RandStream('twister', 'Seed', seed);
D = ctx.L.D;
nC = size(lib.candidates, 2);
st.S0 = zeros(D, nStates);
st.c0 = c * ones(1, nStates);
st.ids = zeros(lib.nAgents, nStates);
st.snap = cell(1, nStates);
st.hs = cell(1, nStates);
st.year = zeros(1, nStates);
st.day = zeros(1, nStates);
for m = 1:nStates
    y = years(1 + mod(m - 1, numel(years)));
    T = p.exp.warmup + randi(rs, [0, 30]);
    valid = validWeatherStarts(W(y), p, T + 1, years);
    if isempty(valid)
        error('sampleStates:split', 'No state window remains inside the requested weather split.');
    end
    d0 = valid(randi(rs, numel(valid)));
    seg = buildSegment(W(y), d0, T + 1, p);
    env = IronRustEnv(ctx);
    env.reset(seed + m, c, p.exp.initSOC, struct('seg', seg));
    for t = 1:T
        env.step(policyAct(env.getObs(), w0, ctx));
    end
    k = env.k;
    st.S0(:, m) = env.stateVector();
    st.snap{m} = struct('x', env.x, 'gInv', env.gInv, 'gLine', env.gLine, 'pLast', env.pLast, 'z', env.z);
    st.hs{m} = struct('reg', seg.reg(k), 'eW', seg.eW(k), 'eS', seg.eS(k), 'eL', seg.eL(k), 'doy', seg.doy(k), ...
        'EW', seg.EW(k), 'ES', seg.ES(k), 'EL', seg.EL(k), 'carbon', seg.carbon, 'h2', seg.h2);
    st.ids(:, m) = lib.candidates(:, 1 + mod(m - 1, nC));
    st.year(m) = y;
    absoluteDay=d0+k-1;
    if isfield(W(y),'sourceYearIndex') && numel(W(y).sourceYearIndex)==W(y).N
        st.year(m)=W(y).sourceYearIndex(absoluteDay);
    end
    % A state warmed up across New Year belongs to its actual source-year
    % cluster, not the year in which the warm-up segment began.
    st.day(m) = seg.doy(k);
end
st.emb0 = embeddingsFromIds(lib, st.ids);
end
