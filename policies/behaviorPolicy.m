function [a, perturbed, bs] = behaviorPolicy(obs, bs, lib, ctx, rs)
%BEHAVIORPOLICY 数据采集用行为策略。
%   每隔 U(switchDays) 天重新抽取联合策略：以概率 alignedProb 取“全体同原型”，否则各智能体独立均匀抽取；
%   以概率 epsExplore 对当日动作施加有界扰动（燃铁上限、计划还原、发运量乘性对数正态扰动，
%   开机与掺氨状态以 flipProb 翻转，发运量以 addProb 附加随机请求），以保证状态覆盖。
%   被扰动当日的转移不满足 a = π_w(s)，在世界模型训练中只作为后续状态的来源，不作为 (s, w, s′) 样本。
%   bs（行为状态）字段：id（当前联合策略编号）、daysLeft；首次调用传入空结构体即可。
%   每回合首日或 daysLeft 用尽时更新 bs。

p = ctx.p;
if ~isfield(bs, 'daysLeft') || bs.daysLeft <= 0
    if rand(rs) < p.policy.alignedProb
        m = randi(rs, size(lib.alignedIds, 2));
        bs.id = lib.alignedIds(:, m);
    else
        bs.id = randi(rs, lib.nOpt, lib.nAgents, 1);
    end
    bs.daysLeft = randi(rs, p.policy.switchDays);
end
bs.daysLeft = bs.daysLeft - 1;
w = jointPolicy(lib, bs.id);
a = policyAct(obs, w, ctx);
perturbed = false;
if rand(rs) < p.policy.epsExplore
    perturbed = true;
    sg = p.policy.perturbSigma;
    a.bcap = a.bcap .* exp(sg * randn(rs, size(a.bcap)));
    a.rho = a.rho .* exp(sg * randn(rs, size(a.rho)));
    a.f = a.f .* exp(sg * randn(rs, size(a.f)));
    flipO = rand(rs, size(a.o)) < p.policy.flipProb;
    a.o(flipO) = ~a.o(flipO);
    turnOn = flipO & a.o & a.bcap <= 0;
    a.bcap(turnOn) = obs.x(ctx.idx.IFe(turnOn));          % 翻转开机时允许使用全部库存，由环境做可行化
    flipB = rand(rs, size(a.beta)) < p.policy.flipProb;
    a.beta(flipB) = p.plant.betaMax(flipB) - a.beta(flipB);
    addMask = rand(rs, size(a.f)) < p.policy.addProb;
    a.f(addMask) = a.f(addMask) + p.policy.addFrac * obs.Fcap(addMask) .* rand(rs, nnz(addMask), 1);
end
end
