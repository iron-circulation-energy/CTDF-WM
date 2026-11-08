function C = buildCase(p, W, seedStats)
%BUILDCASE 由参数构造算例：拓扑、状态索引、闭环周转时间、气象年、训练年统计量、上下文与临界质量。
%   W 为空时调用 genWeatherYears(p, p.seed)。统计量只用训练年份（p.weather.train）。
%   名义循环铁总质量 cNominal：p.stats.cNominalMode = 'eps' 取 M_crit(ε)，'crit' 取 M_crit，'fixed' 取 p.stats.cNominalFixed（设计点）。
%   输出 C：p、topo、idx、Tl、W、stats、ctx、cm、cNominal。

if nargin < 2 || isempty(W)
    W = genWeatherYears(p, p.seed);
end
if nargin >= 3 && ~isempty(seedStats)
    p.seed = seedStats;
end
topo = buildTopology(p);
idx = buildStateIndex(topo);
Tl = computeTloop(topo, p);
stats = estimateStats(W, p.weather.train, p, Tl);
ctx = buildContext(p, topo, idx, Tl, stats);
cm = criticalMass(stats, Tl, p);
C.p = p;
C.topo = topo;
C.idx = idx;
C.Tl = Tl;
C.W = W;
C.stats = stats;
C.ctx = ctx;
C.cm = cm;
switch lower(p.stats.cNominalMode)
    case 'eps'
        if ~isfinite(cm.M_eps)
            error('buildCase:unidentifiedTail', ['No finite risk-calibrated mass is identified: low-renewable transitions or exits are missing. ' ...
                'Provide more independent training weather; do not clip q below one to manufacture a finite bound.']);
        end
        C.cNominal = cm.M_eps;
    case 'crit'
        C.cNominal = cm.M_crit;
    case 'fixed'
        C.cNominal = p.stats.cNominalFixed;
    otherwise
        error('buildCase:cNominal', '未知 cNominalMode %s。', p.stats.cNominalMode);
end
end
