function cf = windCF(U, cfg)
%WINDCF 通用风电机组归一化功率曲线（标准空气密度 1.225 kg/m³）。
%   cf = windCF(U, cfg)：U 为等效风速（m/s，已做密度修正与偏差校正），
%     U < v_in 或 U ≥ v_out：0；v_in ≤ U < v_r：(U³ − v_in³)/(v_r³ − v_in³)；v_r ≤ U < v_out：1；
%   再乘 (1 − cfg.windLoss)（尾流、可用率与场内电气损失）。
%   参数 cfg.windVin、windVr、windVout、windLoss 见 params_default（haoji 算例，[待核实]，取多兆瓦级陆上机组典型值）。
%   说明：三次方近似是能源系统研究中常用的通用功率曲线；年发电量由 prepareRealData 的偏差校正对齐官方利用小时数，
%   功率曲线形状只影响日间分布，不影响校正年份的年电量。

cf = zeros(size(U));
m = U >= cfg.windVin & U < cfg.windVr;
cf(m) = (U(m) .^ 3 - cfg.windVin ^ 3) / (cfg.windVr ^ 3 - cfg.windVin ^ 3);
cf(U >= cfg.windVr & U < cfg.windVout) = 1;
cf = cf * (1 - cfg.windLoss);
end
