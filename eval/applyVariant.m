function [pv, over] = applyVariant(p, name, kind, level)
%APPLYVARIANT E6 敏感性分析的单因素变体。修改基本参数后调用 deriveParams 重算派生量。
%   name：'roundtrip'（实际往返效率乘 level：放能端 η^st 与充能端单位铁耗电 h_Fe·κ/η^el + ε 的倒数各乘 √level，
%         即 η^el 按 h_Fe·κ/η^el' + ε = (h_Fe·κ/η^el + ε)/√level 反解；η^el' 超过 0.99 时报错）、'kappa'（κ 取 level）、'mode'（全部线路改为 level 方式，
%         时延不变，只改变运价）、'distance'（线路长度与时延同乘 level，时延取整且不小于 1 d）、
%         'retrofit'（改造投资比例乘 level）、'carbon'、'h2'（碳价、氢价取 level，经回合说明覆盖）、
%         'transport'（铁路与水运运价同乘 level，热图用）。
%   输出 pv（变体参数）与 over（回合说明覆盖字段，例如 carbon、h2）。

pv = p;
over = struct();
switch lower(name)
    case 'roundtrip'
        % 往返效率 η = η^st·h_Fe/(h_Fe·κ/η^el + ε)：两端各承担 √level，使每一电厂—还原站组合的实际往返效率恰为基准的 level 倍
        g = sqrt(level);
        pv.plant.etaSt = p.plant.etaSt * g;
        hk = p.iron.hFe * p.station.kappa(:);
        eRed = hk ./ p.station.etaEl(:) + p.station.epsAux(:);       % MWh/t，基准单位铁充能电耗
        den = eRed / g - p.station.epsAux(:);
        etaEl = hk ./ den;
        if any(den <= 0) || any(etaEl > 0.99) || any(pv.plant.etaSt(:) >= 1)
            error('applyVariant:roundtrip', '往返效率倍数 %.3g 超出两端效率的物理上限。', level);
        end
        pv.station.etaEl = reshape(etaEl, size(p.station.etaEl));
    case 'kappa'
        pv.station.kappa(:) = level;
    case 'mode'
        pv.net.lines(:, 4) = {level};
    case 'distance'
        for e = 1:size(p.net.lines, 1)
            pv.net.lines{e, 6} = p.net.lines{e, 6} * level;
            pv.net.lines{e, 5} = max(1, round(p.net.lines{e, 5} * level));
        end
    case 'retrofit'
        pv.plant.retrofitFrac = p.plant.retrofitFrac * level;
    case 'carbon'
        over.carbon = level;
    case 'h2'
        over.h2 = level;
    case 'transport'
        pv.transport.railCost = p.transport.railCost * level;
        pv.transport.waterCost = p.transport.waterCost * level;
    otherwise
        error('applyVariant:name', '未知敏感性因素 %s。', name);
end
if ~strcmpi(kind, 'value') && ~strcmpi(kind, 'scale') && ~strcmpi(kind, 'mode')
    error('applyVariant:kind', '未知取值方式 %s。', kind);
end
pv = deriveParams(pv);
end
