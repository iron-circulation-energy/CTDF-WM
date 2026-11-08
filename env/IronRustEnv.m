classdef IronRustEnv < handle
    %IRONRUSTENV 铁粉—铁锈燃储一体化多厂闭环环境。
    %   单日推进严格按以下顺序（step 方法）：
    %     1 日初到达：a_{e,k} = q_{e,1,k} 计入目标节点库存；
    %     2 动作可行化：库存、转换、产锈仓容与补铁仓容限额，β 截断，开机可行性检查；
    %     3 内层调度（—(11)）；
    %     4 由 反算 b_{i,k}、ρ_{j,k}，更新电厂与还原站库存，损耗 ℓ_i·b_{i,k} 计入虚拟储备；
    %     5 补铁：从 V 向还原站补回当日损耗（u_{j,k} ≤ V）；
    %     6 发运：按线路行序受运力、源库存和目的仓容预留约束，进入 q_{e,τ_e}，管道格前移；
    %     7 单日成本 C_k与 z_{k+1}；
    %     8 不变量检查：守恒、非负、节点库存+全部入站在途预留≤仓容；
    %     9 新状态的铁裕度、锈裕度、荷电状态与事件。
    %   dispatchMode = 'direct' 时跳过内层调度，动作直接给出实际燃铁量与还原量（理论验证与质量守恒检验用）。

    properties
        ctx              % 静态上下文（buildContext）
        seg              % 气象片段（含预测 F）
        capSched         % 时变容量：Fcap（nE×N）、rhoAvail（nR×N）
        k = 1            % 片段内当前日
        x                % 物料状态 n×1（t）
        gInv             % 库存分量载体品质 nInv×1
        gLine            % 线路在途载体品质 nE×1
        pLast            % 上一日末小时出力 nP×1（MW）
        z                % 上一日物理成本驱动量（stateLayout.z，MWh及t铁当量）
        c = 0            % 循环铁总质量（t）
        dispatchMode = 'lp'
    end

    methods
        function env = IronRustEnv(ctx)
            env.ctx = ctx;
        end

        function reset(env, seed, c, initSOC, scenario)
            %RESET 初始化回合。scenario 字段：seg（含 F）、capSched（可选）、initMode（'deterministic'
            %   或 'random'，默认确定性）、dispatchMode（默认 'lp'）、k0（默认 1）、x0/gInv0/gLine0（可选，直接给定物料）。
            ctx = env.ctx;
            if nargin < 5 || isempty(scenario)
                error('IronRustEnv:reset', '必须提供 scenario.seg。');
            end
            env.seg = scenario.seg;
            if isfield(scenario, 'capSched') && ~isempty(scenario.capSched)
                env.capSched = scenario.capSched;
            else
                N = numel(env.seg.EW);
                env.capSched.Fcap = repmat(ctx.topo.Fcap(:), 1, N);
                env.capSched.rhoAvail = ones(ctx.topo.nR, N);
            end
            mode = 'deterministic';
            if isfield(scenario, 'initMode') && ~isempty(scenario.initMode)
                mode = scenario.initMode;
            end
            env.dispatchMode = 'lp';
            if isfield(scenario, 'dispatchMode') && ~isempty(scenario.dispatchMode)
                env.dispatchMode = scenario.dispatchMode;
            end
            env.k = 1;
            if isfield(scenario, 'k0') && ~isempty(scenario.k0)
                env.k = scenario.k0;
            end
            rs = RandStream('twister', 'Seed', seed);
            if isfield(scenario, 'x0') && ~isempty(scenario.x0)
                env.x = scenario.x0(:);
                env.gInv = scenario.gInv0(:);
                env.gLine = scenario.gLine0(:);
                env.c = sum(env.x);
            else
                [env.x, env.gInv, env.gLine] = initMaterial(c, initSOC, ctx, mode, rs);
                env.c = c;
            end
            IronRustEnv.checkInvariants(env.x,env.c);
            checkStorageCapacity(env.x,ctx);
            env.pLast = zeros(ctx.topo.nP, 1);
            env.z = zeros(ctx.L.nZ, 1);
        end

        function eta = etaEff(env)
            %ETAEFF 计及载体老化的汽轮机循环效率：η_eff = η·(1 − aEta·(1 − g))。
            p = env.ctx.p;
            eta = p.plant.etaSt(:);
            if p.aging.enable
                g = env.gInv(env.ctx.idx.IFe);
                eta = eta .* (1 - p.aging.aEta * (1 - g));
            end
        end

        function e = eRedEff(env)
            %EREDEFF 计及载体老化的单位还原电耗（MWh/t）：κ_eff = κ·(1 + aKappa·(1 − g))。
            p = env.ctx.p;
            kap = p.station.kappa(:);
            if p.aging.enable
                g = env.gInv(env.ctx.idx.SOx);
                kap = kap .* (1 + p.aging.aKappa * (1 - g));
            end
            e = p.iron.hFe * kap ./ p.station.etaEl(:) + p.station.epsAux(:);
        end

        function xi = exoFeatures(env, k)
            %EXOFEATURES 第 k 日外生状态 ξ，含当前能力，不包含未来故障安排。
            if nargin < 2
                k = env.k;
            end
            p = env.ctx.p;
            sg = env.seg;
            F = sg.F;
            H = env.ctx.H;
            w3 = p.forecast.window3;
            regOH = zeros(3, 1);
            regOH(sg.reg(k)) = 1;
            ang = 2 * pi * sg.doy(k) / 365;
            xi = [sg.EW(k) / (p.re.capW * 24); sg.ES(k) / (p.re.capS * 24); sg.EL(k) / (p.load.mean * 24); ...
                regOH; sg.eW(k); sg.eS(k); sg.eL(k); sin(ang); cos(ang); sg.carbon; sg.h2; ...
                F.must(k, 1); F.may(k, 1); F.absorb(k, 1); F.peakMust(k, 1); F.peakMay(k, 1); ...
                sum(F.must(k, 1:w3)); sum(F.must(k, 1:H)); sum(F.absorb(k, 1:w3)); sum(F.absorb(k, 1:H)); ...
                env.capSched.Fcap(:,k)./max(env.ctx.topo.Fcap(:),eps); env.capSched.rhoAvail(:,k)];
        end

        function s = stateVector(env)
            %STATEVECTOR 原始状态向量 s = [x; ξ; gInv; gLine; pLast; z]。
            s = [env.x; env.exoFeatures(env.k); env.gInv; env.gLine; env.pLast; env.z];
        end

        function [muFe, muOx] = margins(env)
            [muFe, muOx] = computeMargins(env.stateVector(), env.ctx);
        end

        function v = soc(env)
            %SOC 全网荷电状态：铁（含在途铁）占循环铁总质量的比例。
            v = sum(env.x(env.ctx.ironMask)) / env.c;
        end

        function obs = getObs(env)
            %GETOBS 策略与 MPC 使用的观测（只含当日决策时刻可得信息）。
            k = env.k;
            F = env.seg.F;
            obs.k = k;
            obs.c = env.c;
            obs.x = env.x;
            obs.gInv = env.gInv;
            obs.gLine = env.gLine;
            obs.pLast = env.pLast;
            obs.z = env.z;
            obs.xi = env.exoFeatures(k);
            obs.s = [env.x; obs.xi; env.gInv; env.gLine; env.pLast; env.z];
            obs.etaEff = env.etaEff();
            obs.eRedEff = env.eRedEff();
            obs.Fcap = env.capSched.Fcap(:, k);
            obs.rhoAvail = env.capSched.rhoAvail(:, k);
            obs.d0 = struct('must', F.must(k, 1), 'may', F.may(k, 1), 'absorb', F.absorb(k, 1), ...
                'peakMust', F.peakMust(k, 1), 'peakMay', F.peakMay(k, 1));
            obs.fc = struct('EW', F.EW(k, :), 'ES', F.ES(k, :), 'EL', F.EL(k, :), 'must', F.must(k, :), ...
                'absorb', F.absorb(k, :), 'may', F.may(k, :));
            obs.hidden = struct('reg', env.seg.reg(k), 'eW', env.seg.eW(k), 'eS', env.seg.eS(k), ...
                'eL', env.seg.eL(k), 'doy', env.seg.doy(k), 'carbon', env.seg.carbon, 'h2', env.seg.h2);
            obs.remainingDays = numel(env.seg.EW) - k + 1;
        end

        function snap = snapshot(env)
            snap = struct('x', env.x, 'gInv', env.gInv, 'gLine', env.gLine, 'pLast', env.pLast, ...
                'z', env.z, 'c', env.c, 'k', env.k, 'seg', env.seg, 'capSched', env.capSched, ...
                'dispatchMode', env.dispatchMode);
        end

        function restore(env, snap)
            env.x = snap.x;
            env.gInv = snap.gInv;
            env.gLine = snap.gLine;
            env.pLast = snap.pLast;
            env.z = snap.z;
            env.c = snap.c;
            env.k = snap.k;
            env.seg = snap.seg;
            env.capSched = snap.capSched;
            env.dispatchMode = snap.dispatchMode;
        end

        function info = step(env, a)
            %STEP 单日推进（顺序见类说明）。a 字段：o、bcap、beta、rho、f；direct 模式另需 burn、red。
            ctx = env.ctx;
            p = ctx.p;
            topo = ctx.topo;
            idx = ctx.idx;
            nP = topo.nP;
            nR = topo.nR;
            k = env.k;
            if k > numel(env.seg.EW)
                error('IronRustEnv:step', '已超出气象片段长度。');
            end
            x = env.x;
            c0 = sum(x);
            gInvL = env.gInv;
            gLineL = env.gLine;
            Fcap = env.capSched.Fcap(:, k);
            rhoAvail = env.capSched.rhoAvail(:, k);
            trunc = struct('b', 0, 'rho', 0, 'beta', 0, 'o', 0, 'f', 0);

            % ---- 1 日初到达（：a_{e,k} = q_{e,1,k}）----
            for e = 1:topo.nE
                q1 = idx.qFirst(e);
                amt = x(q1);
                if amt > 0
                    tg = idx.lineTgt(e);
                    gInvL(tg) = IronRustEnv.mixQuality(x(tg), gInvL(tg), amt, gLineL(e));
                    x(tg) = x(tg) + amt;
                    x(q1) = 0;
                end
            end

            % ---- 2 动作可行化 ----
            eta = env.etaEffFrom(gInvL);
            eRed = env.eRedEffFrom(gInvL);
            IFe = x(idx.IFe);
            SOx = x(idx.SOx);
            rhoCapAvail = p.station.rhoMax(:) .* rhoAvail;
            room = max(ctx.capInv-ctx.capacityMap*x,0);
            roomFe = room(idx.SFe);
            capture = 1-p.plant.loss(:);
            burnStoreCap = room(idx.IOx)./max(capture,eps);
            burnStoreCap(capture==0) = inf;
            activeR = ctx.shareR>0;
            makeupCap = min(roomFe(activeR)./ctx.shareR(activeR));
            reqRho = max(a.rho(:), 0);
            rustLimited = SOx < min(reqRho, rhoCapAvail) - 1e-9;
            if strcmp(env.dispatchMode, 'lp')
                bcap = min([max(a.bcap(:), 0), IFe, burnStoreCap],[],2);
                requestedMakeup = sum(p.plant.loss(:).*bcap);
                if requestedMakeup>makeupCap && requestedMakeup>0
                    bcap = bcap*(makeupCap/requestedMakeup);
                end
                trunc.b = sum(max(a.bcap(:) - bcap, 0));
                rhoPlan = min([reqRho, SOx, rhoCapAvail, roomFe], [], 2);
                trunc.rho = sum(max(reqRho - rhoPlan, 0));
                beta = min(max(a.beta(:), 0), p.plant.betaMax(:));
                trunc.beta = sum(abs(beta - a.beta(:)));
                o = logical(a.o(:));
                Emin = plantMinEnergy(p, env.pLast);
                for i = 1:nP
                    if o(i) && (1 - beta(i)) * Emin(i) > eta(i) * p.iron.hFe * bcap(i) + 1e-9
                        o(i) = false;
                        trunc.o = trunc.o + 1;
                    end
                end
                % ---- 3 内层调度 ----
                [RE, D] = hourlyProfiles(env.seg.EW(k), env.seg.ES(k), env.seg.EL(k), env.seg.doy(k), p.weather);
                day = struct('RE', RE, 'D', D, 'o', o, 'bcap', bcap, 'beta', beta, 'Ech', rhoPlan .* eRed, ...
                    'redAvail', rhoAvail, 'pLast', env.pLast, 'etaEff', eta, 'carbon', env.seg.carbon, 'h2', env.seg.h2);
                day.roomSFe = roomFe;
                day.eRedEff = eRed;
                day.shareR = ctx.shareR;
                lp = innerDispatchLP(ctx.lpT, day, p);
                % ---- 4：反算燃铁量与还原量 ----
                b = max(0, (sum(lp.p, 2) - lp.eNH3) ./ (eta * p.iron.hFe));
                rho = max(0, sum(lp.red, 2) ./ eRed);
                REsum = sum(RE);
            else
                o = false(nP, 1);
                b = max(a.burn(:), 0);
                rho = min(max(a.red(:), 0), rhoCapAvail);
                lp = struct('p', zeros(nP, 24), 'red', zeros(nR, 24), 'eNH3', zeros(nP, 1), 'bk', zeros(1, 24), ...
                    'cur', zeros(1, 24), 'shed', zeros(1, 24), 'ovg', zeros(1, 24), 'Jop', 0, 'balRes', 0, 'time', 0);
                REsum = 0;
            end
            shortFe = max(b - IFe, 0);                      % direct 模式下的缺铁量（理论验证用）
            shortOx = max(rho - SOx, 0);
            b = min(b, IFe);
            rho = min(rho, SOx);
            % Direct-mode actions obey the same conversion and makeup capacity
            % envelope. LP-mode values already satisfy it (up to solver tolerance).
            beforeB = b;
            beforeRho = rho;
            b = min(b,burnStoreCap);
            requestedMakeup = sum(p.plant.loss(:).*b);
            if requestedMakeup>makeupCap && requestedMakeup>0
                b = b*(makeupCap/requestedMakeup);
            end
            rho = min(rho,max(roomFe-ctx.shareR*sum(p.plant.loss(:).*b),0));
            trunc.capacityB = sum(beforeB-b);
            trunc.capacityRho = sum(beforeRho-rho);
            gFe = gInvL(idx.IFe);
            x(idx.IFe) = x(idx.IFe) - b;
            rustProd = (1 - p.plant.loss(:)) .* b;
            for i = 1:nP
                ci = idx.IOx(i);
                gInvL(ci) = IronRustEnv.mixQuality(x(ci), gInvL(ci), rustProd(i), gFe(i));
                x(ci) = x(ci) + rustProd(i);
            end
            lossT = sum(p.plant.loss(:) .* b);
            x(idx.V) = x(idx.V) + lossT;
            gOx = gInvL(idx.SOx);
            x(idx.SOx) = x(idx.SOx) - rho;
            if p.aging.enable
                qNew = max(p.aging.floor, gOx - p.aging.decayPerCycle);
            else
                qNew = ones(nR, 1);
            end
            for j = 1:nR
                cj = idx.SFe(j);
                gInvL(cj) = IronRustEnv.mixQuality(x(cj), gInvL(cj), rho(j), qNew(j));
                x(cj) = x(cj) + rho(j);
            end

            % ---- 5 补铁：从虚拟储备补回当日损耗（u ≤ 补铁时刻的 V，即计入当日损耗之后；V 初值为 0 时 V ≡ 0）----
            u = min(max(x(idx.V), 0), lossT) * ctx.shareR;
            x(idx.V) = x(idx.V) - sum(u);
            for j = 1:nR
                cj = idx.SFe(j);
                gInvL(cj) = IronRustEnv.mixQuality(x(cj), gInvL(cj), u(j), 1);
                x(cj) = x(cj) + u(j);
            end

            % ---- 6 发运----
            fReq = max(a.f(:), 0);
            f = zeros(topo.nE,1);
            reserved = ctx.capacityMap*x;
            available = x(1:idx.nInv);
            % Public deterministic order: p.net.lines row order. Never borrow
            % capacity from a later outgoing request or from a future arrival.
            for e = 1:topo.nE
                src = idx.lineSrc(e);
                dst = idx.lineTgt(e);
                f(e) = min([fReq(e), Fcap(e), max(available(src),0), max(ctx.capInv(dst)-reserved(dst),0)]);
                available(src) = available(src)-f(e);
                reserved(src) = reserved(src)-f(e);
                reserved(dst) = reserved(dst)+f(e);
            end
            trunc.f = sum(fReq - f);
            for e = 1:topo.nE
                qq = idx.q{e};
                s = idx.lineSrc(e);
                amt = f(e);
                x(s) = x(s) - amt;
                pipeMass = sum(x(qq));
                gLineL(e) = IronRustEnv.mixQuality(pipeMass, gLineL(e), amt, gInvL(s));
                if numel(qq) > 1
                    x(qq(1:end - 1)) = x(qq(2:end));
                end
                x(qq(end)) = amt;
            end
            tol = 1e-9 * max(1, c0);
            x(x < 0 & x > -tol) = 0;

            % ---- 7 成本----
            overflowMass = sum(max(x(1:idx.nInv) - ctx.capInv, 0));
            quantityNew = [sum(lp.p, 2); sum(lp.bk); sum(lp.eNH3); f; sum(x); sum(u); ...
                sum(lp.cur); sum(lp.shed) + sum(lp.ovg); overflowMass];
            [costNew, zNew] = physicalQuantityCost(quantityNew, ctx, env.seg.carbon, env.seg.h2);

            % ---- 8 不变量 ----
            IronRustEnv.checkInvariants(x, c0);
            checkStorageCapacity(x,ctx);

            % ---- 指标与状态更新 ----
            % 锈阻塞弃电：弃电时段内，因锈不足（计划还原受锈库存限制）而闲置的还原功率所对应的弃电量；
            % 按各站闲置功率占比归属到站（局部锈阻塞统计用）
            headJ = zeros(nR, 24);
            extraRho = max(min([reqRho,rhoCapAvail,max(roomFe-u,0)],[],2)-rho,0);
            for j = 1:nR
                if rustLimited(j) && SOx(j)-rho(j)<=1e-6 && extraRho(j)>0
                    headJ(j, :) = min(lp.cur,max(p.station.pRedMax(j)*rhoAvail(j)-lp.red(j,:),0));
                    % A missing-rust attribution also needs space for its iron
                    % product after actual reduction and same-day loss makeup.
                    potential = sum(headJ(j,:));
                    if potential>0
                        headJ(j,:) = headJ(j,:)*min(1,extraRho(j)*eRed(j)/potential);
                    end
                end
            end
            head = sum(headJ, 1);
            blk = min(lp.cur, head);
            info.rustBlockMWh = sum(blk);
            info.rustBlockJ = sum(headJ .* (blk ./ max(head, 1e-12)), 2);
            info.Bevent = info.rustBlockMWh > 1e-6;
            info.shed = sum(lp.shed);                      % 失负荷（MWh），过发电松弛单独记录
            info.ovg = sum(lp.ovg);
            info.starve = info.shed > 1e-6;
            info.cur = sum(lp.cur);
            info.RE = REsum;
            info.bkMWh = sum(lp.bk);
            info.nh3MWh = sum(lp.eNH3);
            info.ironMWh = sum(sum(lp.p, 2) - lp.eNH3);
            info.b = b;
            info.availableFe = IFe;
            info.etaEff = eta;
            info.nh3ByPlant = lp.eNH3;
            info.rho = rho;
            info.f = f;
            info.u = u;
            info.o = o;
            info.z = zNew;
            info.quantity = quantityNew;
            info.cost = costNew;
            info.balRes = lp.balRes;
            info.lpTime = lp.time;
            info.trunc = trunc;
            info.overflowMass = overflowMass;
            info.shortFe = shortFe;
            info.shortOx = shortOx;
            info.k = k;

            env.x = x;
            env.gInv = gInvL;
            env.gLine = gLineL;
            env.z = quantityNew;
            env.pLast = lp.p(:, end) .* o;
            env.k = k + 1;
            info.soc = env.soc();
            if env.k <= numel(env.seg.EW)
                [info.muFe, info.muOx] = env.margins();
            else
                info.muFe = nan(nP, 1);
                info.muOx = nan(nR, 1);
            end
        end
    end

    methods (Access = private)
        function eta = etaEffFrom(env, gInvL)
            p = env.ctx.p;
            eta = p.plant.etaSt(:);
            if p.aging.enable
                eta = eta .* (1 - p.aging.aEta * (1 - gInvL(env.ctx.idx.IFe)));
            end
        end

        function e = eRedEffFrom(env, gInvL)
            p = env.ctx.p;
            kap = p.station.kappa(:);
            if p.aging.enable
                kap = kap .* (1 + p.aging.aKappa * (1 - gInvL(env.ctx.idx.SOx)));
            end
            e = p.iron.hFe * kap ./ p.station.etaEl(:) + p.station.epsAux(:);
        end
    end

    methods (Static)
        function q = mixQuality(m0, q0, m1, q1)
            %MIXQUALITY 按质量加权混合载体品质指数。
            tot = m0 + m1;
            if tot > 1e-12
                q = (q0 * max(m0, 0) + q1 * m1) / max(tot, 1e-12);
            else
                q = q0;
            end
        end

        function checkInvariants(x, c0)
            %CHECKINVARIANTS 守恒与非负性检查（违反时报错并给出出错分量）。
            err = abs(sum(x) - c0);
            if err > 1e-9 * max(1, c0)
                error('IronRustEnv:conservation', '守恒误差 %.3e t 超出容差。', err);
            end
            [mn, im] = min(x);
            if mn < -1e-9 * max(1, c0)
                error('IronRustEnv:negative', '物料分量 %d 为负（%.3e t）。', im, mn);
            end
        end
    end
end
