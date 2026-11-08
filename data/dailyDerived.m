function dv = dailyDerived(RE, D, p)
%DAILYDERIVED 由小时风光与负荷计算日尺度派生量（供预测、状态特征、策略与统计使用）。
%   输入：RE、D 为 24×N（MW）。输出结构体字段均为 1×N：
%     must     电厂必须承担的电量（备用之外的缺口，按电厂总容量截断），MWh   —— 承诺放能 b̂ 的能量口径
%     may      电厂可承担的电量（完全替代备用），MWh
%     absorb   还原站可吸收的富余电量（按还原总功率截断），MWh             —— ρ̂ 的能量口径
%     peakMust 备用之外的最大小时缺口，MW（机组组合用）
%     peakMay  最大小时缺口，MW
%     capShed  容量不足导致的失负荷下界，MWh（校准检查用）

r = D - RE;
Pp = sum(p.plant.pmax);
Pr = sum(p.station.pRedMax);
Pb = p.backup.pmax;
dv.must = sum(min(Pp, max(0, r - Pb)), 1);
dv.may = sum(min(Pp, max(0, r)), 1);
dv.absorb = sum(min(Pr, max(0, -r)), 1);
dv.peakMust = max(max(0, r - Pb), [], 1);
dv.peakMay = max(max(0, r), [], 1);
dv.capShed = sum(max(0, r - Pb - Pp), 1);
end
