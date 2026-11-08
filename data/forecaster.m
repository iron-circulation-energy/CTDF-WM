function F = forecaster(seg, p)
%FORECASTER 共用预测器：为片段中每一天 k 给出前瞻 d = 0..Hmax 的日电量预测及派生量。
%   所有方法（M0—M4）使用同一预测器输出，保证信息公平。第 0 列为当日实际值（日前预测视为准确）。
%   预测模式 p.forecast.mode：
%     'conditional'  马尔可夫条件点预测：状态分布 e_reg·P^d，AR 残差 φ^d·e，季节项按目标日计算。
%                    预测只依赖当日隐状态，使状态向量满足马尔可夫性，与后继测度真值一致（默认）。
%     'noisyTruth'   乘性误差：真值 × (1 + σ_d·u_{k,d})，σ_d = σ0 + growth·(d − 1)，
%                    u_{k,d} 在发布日 k 上服从 AR(1)（系数 rho）；超出片段末尾时退回条件预测。
%     'oracle'       完全预见（只用于诊断）。
%
%   输入 seg：reg、eW、eS、eL、doy、EW、ES、EL（1×N）、carbon、h2，可选 year、d0。
%   输出 F：EW、ES、EL、must、may、absorb、peakMust、peakMay，均为 N×(Hmax+1)。

w = p.weather;
Hm = p.forecast.Hmax;
N = numel(seg.EW);
EWf = zeros(N, Hm + 1);
ESf = zeros(N, Hm + 1);
ELf = zeros(N, Hm + 1);
EWf(:, 1) = seg.EW(:);
ESf(:, 1) = seg.ES(:);
ELf(:, 1) = seg.EL(:);
reg = seg.reg(:);
eW = seg.eW(:);
eS = seg.eS(:);
eL = seg.eL(:);
doy = seg.doy(:);

% 条件点预测
Pd = eye(3);
for d = 1:Hm
    Pd = Pd * w.P;
    mWbar = Pd * w.mW(:);
    mSbar = Pd * w.mS(:);
    doyT = mod(doy - 1 + d, 365) + 1;
    cfW = w.cfW0 + w.cfWamp * cos(2 * pi * (doyT - w.cfWpeak) / 365);
    cfS = w.cfS0 + w.cfSamp * cos(2 * pi * (doyT - w.cfSpeak) / 365);
    lf = 1 + w.lAmp1 * cos(2 * pi * (doyT - w.lPeak1) / 365) + w.lAmp2 * cos(4 * pi * (doyT - w.lPeak2) / 365);
    EWf(:, d + 1) = p.re.capW * 24 * min(w.cfWmax, cfW .* mWbar(reg) .* max(0, 1 + w.phiW ^ d * eW));
    ESf(:, d + 1) = p.re.capS * 24 * min(w.cfSmax, cfS .* mSbar(reg) .* max(0, 1 + w.phiS ^ d * eS));
    ELf(:, d + 1) = p.load.mean * 24 * lf .* (1 + w.phiL ^ d * eL);
end

mode = lower(p.forecast.mode);
if ~strcmp(mode, 'conditional')
    if isfield(seg, 'year') && isfield(seg, 'd0')
        rs = RandStream('twister', 'Seed', 7919 * seg.year + seg.d0);
    else
        rs = RandStream('twister', 'Seed', 7919);
    end
    uW = zeros(1, Hm);
    uS = zeros(1, Hm);
    uL = zeros(1, Hm);
    rho = p.forecast.rho;
    for k = 1:N
        if strcmp(mode, 'noisytruth')
            uW = rho * uW + sqrt(1 - rho ^ 2) * randn(rs, 1, Hm);
            uS = rho * uS + sqrt(1 - rho ^ 2) * randn(rs, 1, Hm);
            uL = rho * uL + sqrt(1 - rho ^ 2) * randn(rs, 1, Hm);
        end
        for d = 1:Hm
            if k + d <= N
                switch mode
                    case 'noisytruth'
                        sd = p.forecast.sigma0 + p.forecast.growth * (d - 1);
                        EWf(k, d + 1) = seg.EW(k + d) * max(0, 1 + sd * uW(d));
                        ESf(k, d + 1) = seg.ES(k + d) * max(0, 1 + sd * uS(d));
                        ELf(k, d + 1) = seg.EL(k + d) * max(0, 1 + 0.3 * sd * uL(d));
                    case 'oracle'
                        EWf(k, d + 1) = seg.EW(k + d);
                        ESf(k, d + 1) = seg.ES(k + d);
                        ELf(k, d + 1) = seg.EL(k + d);
                    otherwise
                        error('forecaster:mode', '未知预测模式 %s。', p.forecast.mode);
                end
            end
        end
    end
end

% 派生量（展平后批量计算小时曲线）
doyAll = mod(doy - 1 + (0:Hm), 365) + 1;                 % N×(Hm+1)
[RE, D] = hourlyProfiles(EWf(:)', ESf(:)', ELf(:)', doyAll(:)', w);
dv = dailyDerived(RE, D, p);
F.EW = EWf;
F.ES = ESf;
F.EL = ELf;
F.must = reshape(dv.must, N, Hm + 1);
F.may = reshape(dv.may, N, Hm + 1);
F.absorb = reshape(dv.absorb, N, Hm + 1);
F.peakMust = reshape(dv.peakMust, N, Hm + 1);
F.peakMay = reshape(dv.peakMay, N, Hm + 1);
end
