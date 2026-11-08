function res = fluidLoopSim(c, fl, seq, opts)
%FLUIDLOOPSIM 临界循环质量的流体闭环模型（流体、有界扰动、无容量约束、事件间可恢复）。
%   结构：各电厂 i 有铁运输传送带（τ^Fe_i 格）、厂内停留传送带（t^P 格）、可燃铁库存 B_i、
%         回运传送带（τ^Ox_i 格）；全部还原站聚合为一个等效还原站：锈停留传送带（t^R 格）、
%         锈库存 S^Ox、还原传送带（t^red 格）、待发铁库存 S^Fe。稳态在途量 = Φ̄·T_loop（Little 定律）。
%   事件分解（与临界循环质量一致）：常规日燃铁 = 还原 = Φ̄；低风光日燃铁 Φ̄ + δ^D；富余日还原 Φ̄ + δ^U。
%   策略（基准库存）：电厂自由铁目标 F*_i = δ^D·D_max·份额_i，还原站自由锈目标 O* = δ^U·U_max；
%     常规日依据日末锈位置偏差恢复荷电状态：锈不足时额外燃铁、锈过多时额外还原（各不超过 dR）；
%     电厂按“目标 + 在途与停留需求”补货（order-up-to），回运锈全部当日发出。
%   违约计数：电厂可燃铁低于安全库存（缺铁断供）、还原站锈低于安全库存而无法完成必需还原（锈阻塞）、
%     还原能力不足以完成必需还原（A3 不成立）、料仓超限（A3 不成立）。
%
%   fl 字段：Phi、deltaD、deltaU、Dmax、Umax、dR、share、tauFe、tauOx（nP×1）、tP、tR、tRed、
%            safeFe（nP×1）、safeOx（标量）。
%   opts 字段：split（'prop' 按比例分配不足、'rustFirst' 先满足锈目标，事件风险用）、
%              capSilo（nP×1）、lineCap（日总发运上限）、redCap（日还原上限）。
%   输出 res：violFe、violOx、violCap、violSilo、first（[日, 类型码]）、consErr、Mcrit、W、traceB、traceSox。

if nargin < 4
    opts = struct();
end
split = getf(opts, 'split', 'prop');
capSilo = getf(opts, 'capSilo', []);
lineCap = getf(opts, 'lineCap', []);
redCap = getf(opts, 'redCap', []);
tol = 1e-6;
share = fl.share(:);
nP = numel(share);
tauFe = round(fl.tauFe(:));
tauOx = round(fl.tauOx(:));
safeFe = fl.safeFe(:);
Phi = fl.Phi;
W = Phi * (share' * (tauFe + fl.tP + tauOx) + fl.tR + fl.tRed);
Mcrit = W + fl.deltaD * fl.Dmax + fl.deltaU * fl.Umax + sum(safeFe) + fl.safeOx;
Fstar = fl.deltaD * fl.Dmax * share;
Ostar = fl.deltaU * fl.Umax;
free = c - W - sum(safeFe) - fl.safeOx;
res.Mcrit = Mcrit;
res.W = W;
res.violFe = 0;
res.violOx = 0;
res.violCap = 0;
res.violSilo = 0;
res.first = [NaN, NaN];
res.consErr = 0;
if free < 0
    res.violFe = Inf;
    res.first = [0, 0];
    return;
end
switch split
    case 'prop'
        fac = min(1, free / (sum(Fstar) + Ostar));
        fF = Fstar * fac;
        fO = Ostar * fac;
        extra = max(free - sum(Fstar) - Ostar, 0);
    case 'rustFirst'
        fO = min(Ostar, free);
        fF = (free - fO) * share;
        extra = 0;
    otherwise
        error('fluidLoopSim:split', '未知分配方式 %s。', split);
end
CF = cell(nP, 1);
DW = cell(nP, 1);
CO = cell(nP, 1);
for i = 1:nP
    CF{i} = Phi * share(i) * ones(1, tauFe(i));
    DW{i} = Phi * share(i) * ones(1, fl.tP);
    CO{i} = Phi * share(i) * ones(1, tauOx(i));
end
RW = Phi * ones(1, fl.tR);
RC = Phi * ones(1, fl.tRed);
B = safeFe + fF + extra * share;
Sox = fl.safeOx + fO;
Sfe = 0;
tgtB = B;
tgtO = Sox;
total0 = totalMass();
nK = numel(seq);
res.traceB = zeros(nP, nK);
res.traceSox = zeros(1, nK);
for k = 1:nK
    ev = seq(k);
    burnReq = Phi + fl.deltaD * (ev == 'D');
    redReq = Phi + fl.deltaU * (ev == 'U');
    % 1 到达
    for i = 1:nP
        a = 0;
        if tauFe(i) > 0
            a = CF{i}(1);
            CF{i} = [CF{i}(2:end), 0];
        end
        if fl.tP > 0
            b0 = DW{i}(1);
            DW{i} = [DW{i}(2:end), a];
            B(i) = B(i) + b0;
        else
            B(i) = B(i) + a;
        end
    end
    ar = 0;
    for i = 1:nP
        if tauOx(i) > 0
            ar = ar + CO{i}(1);
            CO{i} = [CO{i}(2:end), 0];
        end
    end
    if fl.tR > 0
        r0 = RW(1);
        RW = [RW(2:end), ar];
        Sox = Sox + r0;
    else
        Sox = Sox + ar;
    end
    if fl.tRed > 0
        Sfe = Sfe + RC(1);
        RC = [RC(2:end), 0];
    end
    % 2 燃铁（含荷电状态恢复）
    burn = burnReq * share;
    gapO = tgtO - (Sox - redReq);
    if ev == 'N' && gapO > 1e-9
        burn = burn + min(fl.dR, gapO) * share;
    end
    for i = 1:nP
        if B(i) - burn(i) < safeFe(i) - tol
            res.violFe = res.violFe + 1;
            recordFirst(k, 1);
            burn(i) = min(burn(i), max(B(i), 0));
        end
        B(i) = B(i) - burn(i);
        if tauOx(i) > 0
            CO{i}(end) = CO{i}(end) + burn(i);
        else
            ar = ar + burn(i); %#ok<NASGU>
            Sox = Sox + burn(i);
        end
    end
    % 3 还原
    red = redReq;
    if ev == 'N' && gapO < -1e-9
        red = red + min(fl.dR, -gapO);
    end
    if ~isempty(redCap) && red > redCap
        if redReq > redCap + tol
            res.violCap = res.violCap + 1;
            recordFirst(k, 3);
        end
        red = redCap;
        redReqEff = min(redReq, redCap);
    else
        redReqEff = redReq;
    end
    if Sox - red < fl.safeOx - tol
        if Sox - redReqEff < fl.safeOx - tol
            res.violOx = res.violOx + 1;
            recordFirst(k, 2);
            red = min(red, max(Sox, 0));
        else
            red = min(red, max(Sox - fl.safeOx, 0));
        end
    end
    Sox = Sox - red;
    if fl.tRed > 0
        RC(end) = RC(end) + red;
    else
        Sfe = Sfe + red;
    end
    % 4 补货
    IP = zeros(nP, 1);
    for i = 1:nP
        IP(i) = B(i) + sum(DW{i}) + sum(CF{i});
    end
    S = tgtB + Phi * share .* (tauFe + fl.tP);
    want = max(S - IP, 0);
    if sum(want) > Sfe && sum(want) > 0
        want = want * (Sfe / sum(want));
    end
    if ~isempty(lineCap)
        want = min(want, lineCap * share);
    end
    for i = 1:nP
        if tauFe(i) > 0
            CF{i}(end) = CF{i}(end) + want(i);
        else
            B(i) = B(i) + want(i);
        end
    end
    Sfe = Sfe - sum(want);
    if ~isempty(capSilo) && any(B > capSilo(:) + tol)
        res.violSilo = res.violSilo + 1;
        recordFirst(k, 4);
    end
    res.traceB(:, k) = B;
    res.traceSox(k) = Sox;
end
res.consErr = abs(totalMass() - total0);

    function m = totalMass()
        m = sum(B) + Sox + Sfe + sum(RW) + sum(RC);
        for ii = 1:nP
            m = m + sum(CF{ii}) + sum(DW{ii}) + sum(CO{ii});
        end
    end

    function recordFirst(day, code)
        if isnan(res.first(1))
            res.first = [day, code];
        end
    end
end

function v = getf(s, f, d)
if isfield(s, f) && ~isempty(s.(f))
    v = s.(f);
else
    v = d;
end
end
