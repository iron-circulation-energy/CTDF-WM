function r = realizedIronShortfall(obs, info, ctx)
%REALIZEDIRONSHORTFALL 当日电厂铁短缺量，与未来预测无关。
% 必要放电量（扣除风光与可用备用电源）按容量份额分摊至各电厂，扣除实际掺氨电量后，
% 与当日到货后的可用铁比较；安全库存可用于放电。
requiredMWh = max(ctx.shareP(:) * max(obs.fc.must(1), 0) - info.nh3ByPlant(:), 0);
r.requiredT = requiredMWh ./ (info.etaEff(:) * ctx.p.iron.hFe);
r.shortfallT = max(r.requiredT - max(info.availableFe(:), 0), 0);
r.safetyShortfallT = max(r.requiredT - max(info.availableFe(:) - ctx.p.plant.safetyFe(:), 0), 0);
r.shortfallMWh = r.shortfallT .* info.etaEff(:) * ctx.p.iron.hFe;
r.definition = 'Plant iron shortfall against the capacity share of required discharge, after arrivals and actual NH3; safety stock usable.';
end
