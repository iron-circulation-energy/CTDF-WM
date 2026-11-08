classdef TruthStore < handle
    %TRUTHSTORE 各候选固定策略在训练年上的实测日均成本（按循环质量缓存），供价值校准使用（见 CalibStore）。
    %   每个质量 c 只计算一次：候选 × 训练年 × 常规工况的固定策略回合（逐回合缓存于 epDir，并行执行）。
    properties
        ctx
        W
        lib
        years
        seed
        epDir
        map
    end
    methods
        function obj = TruthStore(ctx, W, lib, years, seed, epDir)
            obj.ctx = ctx;
            obj.W = W;
            obj.lib = lib;
            obj.years = years;
            obj.seed = seed;
            obj.epDir = epDir;
            obj.map = containers.Map('KeyType', 'char', 'ValueType', 'any');
        end
        function cost = dailyCost(obj, c)
            key = sprintf('%.0f', c);
            if isKey(obj.map, key)
                cost = obj.map(key);
                return;
            end
            p = obj.ctx.p;
            cands = obj.lib.candidates;
            specs = makeEvalSpecs(p, obj.years, obj.seed, {'normal'}, c);
            cost = zeros(size(cands, 2), 1);
            for m = 1:size(cands, 2)
                ctrl = makeController('fixed', sprintf('cal%02d', m), jointPolicy(obj.lib, cands(:, m)));
                [~, T] = evalEpisodes(obj.ctx, obj.W, specs, ctrl, [], obj.epDir);
                cost(m) = mean(T.cost) / p.exp.evalDays;
            end
            obj.map(key) = cost;
        end
        function q = value(obj, c, gamma)
            q = -(obj.dailyCost(c) / obj.ctx.Cref) / (1 - gamma);
        end
    end
end
