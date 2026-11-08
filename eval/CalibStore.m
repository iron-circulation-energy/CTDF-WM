classdef CalibStore < handle
    %CALIBSTORE 价值校准偏移 b_w（按循环质量缓存）：b_w = Q^true_w − Q̄^mod_w。
    %   Q^true_w：候选 w 的固定策略在训练年上的实测日均成本折算的价值（TruthStore，各模型共用）；
    %   Q̄^mod_w：沿参考策略 w0 在训练年上的轨迹（4 个年份、每 15 天一个状态），模型用公共随机数估计的 Q̃_w 的平均。
    %   决策取 argmax_w [Q̃_w(s) + b_w]：各候选的价值水平由训练年实测确定，世界模型只负责随状态变化的相对优劣。
    %   只用训练年份，不接触验证与测试年份。
    properties
        truth
        model
        w0
        K
        ropt
        map
        nStates
    end
    methods
        function obj = CalibStore(truth, model, w0, K, ropt)
            obj.truth = truth;
            obj.model = model;
            obj.w0 = w0;
            obj.K = K;
            obj.ropt = ropt;
            obj.map = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.nStates = 0;
        end
        function b = offset(obj, c)
            key = sprintf('%.0f', c);
            if isKey(obj.map, key)
                b = obj.map(key);
                return;
            end
            tr = obj.truth;
            ctx = tr.ctx;
            p = ctx.p;
            lib = tr.lib;
            E0 = embeddingsFromIds(lib, lib.candidates);
            yrs = tr.years(round(linspace(1, numel(tr.years), min(4, numel(tr.years)))));
            rs = RandStream('twister', 'Seed', 9001);
            Qsum = zeros(size(E0, 2), 1);
            nS = 0;
            gam = 0.99;
            for y = yrs(:)'
                sp = makeEvalSpecs(p, y, tr.seed, {'normal'}, c);
                [seg, cap] = buildEvalSegment(ctx, tr.W, sp);
                env = IronRustEnv(ctx);
                env.reset(sp.seed, sp.c, sp.initSOC, struct('seg', seg, 'capSched', cap, 'initMode', 'deterministic'));
                for t = 1:sp.len
                    obs = env.getObs();
                    if t > sp.warmup && mod(t - sp.warmup, 15) == 1
                        rv = riskValueCRN(obj.model, obs.s, obs.c, E0, ctx, rs, obj.K, obj.ropt);
                        Qsum = Qsum + rv.Q(:);
                        gam = rv.gamma;
                        nS = nS + 1;
                    end
                    env.step(policyAct(obs, obj.w0, ctx));
                end
            end
            b = (tr.value(c, gam) - Qsum / max(nS, 1))';
            obj.nStates = nS;
            obj.map(key) = b;
        end
    end
end
