function T = buildInnerLPTemplate(p, grid)
%BUILDINNERLPTEMPLATE 内层 24 小时线性规划的稀疏矩阵模板（—(11)），只构造一次。
%   决策变量（按顺序）：
%     p_{i,t}（nP×24，MW）、p^red_{j,t}（nR×24）、E^NH3_i（nP，MWh）、
%     p^bk_{z,t}、P^cur_{z,t}、P^shed_{z,t}、P^ovg_{z,t}（各 Z×24）。
%   等式：每小时系统功率平衡（P^ovg 为过发电松弛，与失负荷同价惩罚，保证可行）。
%   不等式（行顺序固定，右端项每日更新）：
%     爬坡 2·23·nP 行；首小时上下爬坡 2·nP 行（与前一日末小时衔接）；
%     燃铁能量上限 Σ_t p_{i,t} − E^NH3_i ≤ η_i·h_Fe·b̄_i（nP 行）；E^NH3_i − β_i·Σ_t p_{i,t} ≤ 0（系数逐日更新）；
%     还原能量上限 Σ_t p^red_{j,t} ≤ E^ch_j（nR 行）；区域线路潮流上下限（启用直流潮流时）。

nP = numel(p.plant.pmax);
nR = numel(p.station.pRedMax);
Z = grid.Z;
H = 24;
T.nP = nP;
T.nR = nR;
T.Z = Z;
T.H = H;
T.iP = reshape(1:nP * H, H, nP)';                      % nP×24
off = nP * H;
T.iR = reshape(off + (1:nR * H), H, nR)';              % nR×24
off = off + nR * H;
T.iN = off + (1:nP)';
off = off + nP;
T.iB = reshape(off + (1:Z * H), H, Z)';                % Z×24
off = off + Z * H;
T.iC = reshape(off + (1:Z * H), H, Z)';
off = off + Z * H;
T.iS = reshape(off + (1:Z * H), H, Z)';
off = off + Z * H;
T.iO = reshape(off + (1:Z * H), H, Z)';
off = off + Z * H;
T.nv = off;

% 等式：系统平衡
rows = [];
cols = [];
vals = [];
for t = 1:H
    rows = [rows, t * ones(1, nP), t * ones(1, nR), t * ones(1, 4 * Z)]; %#ok<AGROW>
    cols = [cols, T.iP(:, t)', T.iR(:, t)', T.iB(:, t)', T.iC(:, t)', T.iS(:, t)', T.iO(:, t)']; %#ok<AGROW>
    vals = [vals, ones(1, nP), -ones(1, nR), ones(1, Z), -ones(1, Z), ones(1, Z), -ones(1, Z)]; %#ok<AGROW>
end
T.Aeq = sparse(rows, cols, vals, H, T.nv);

% 不等式
rows = [];
cols = [];
vals = [];
b = [];
r = 0;
T.rowRamp = [];
for i = 1:nP
    for t = 2:H
        r = r + 1;
        rows = [rows, r, r]; cols = [cols, T.iP(i, t), T.iP(i, t - 1)]; vals = [vals, 1, -1]; %#ok<AGROW>
        b = [b; p.plant.ramp(i)]; %#ok<AGROW>
        r = r + 1;
        rows = [rows, r, r]; cols = [cols, T.iP(i, t - 1), T.iP(i, t)]; vals = [vals, 1, -1]; %#ok<AGROW>
        b = [b; p.plant.ramp(i)]; %#ok<AGROW>
    end
end
T.rowT1Up = zeros(nP, 1);
T.rowT1Dn = zeros(nP, 1);
for i = 1:nP
    r = r + 1;
    rows = [rows, r]; cols = [cols, T.iP(i, 1)]; vals = [vals, 1]; b = [b; 0]; %#ok<AGROW>
    T.rowT1Up(i) = r;
    r = r + 1;
    rows = [rows, r]; cols = [cols, T.iP(i, 1)]; vals = [vals, -1]; b = [b; 0]; %#ok<AGROW>
    T.rowT1Dn(i) = r;
end
T.rowCap = zeros(nP, 1);
T.rowNH3 = zeros(nP, 1);
for i = 1:nP
    r = r + 1;
    rows = [rows, r * ones(1, H), r]; cols = [cols, T.iP(i, :), T.iN(i)]; vals = [vals, ones(1, H), -1]; %#ok<AGROW>
    b = [b; 0]; %#ok<AGROW>
    T.rowCap(i) = r;
    r = r + 1;
    rows = [rows, r * ones(1, H), r]; cols = [cols, T.iP(i, :), T.iN(i)]; vals = [vals, -ones(1, H), 1]; %#ok<AGROW>
    b = [b; 0]; %#ok<AGROW>
    T.rowNH3(i) = r;
end
T.rowRed = zeros(nR, 1);
for j = 1:nR
    r = r + 1;
    rows = [rows, r * ones(1, H)]; cols = [cols, T.iR(j, :)]; vals = [vals, ones(1, H)]; %#ok<AGROW>
    b = [b; 0]; %#ok<AGROW>
    T.rowRed(j) = r;
end
% 区域线路潮流（Z > 1 且存在线路时）
Lz = size(grid.PTDF, 1);
T.rowFlowUp = zeros(Lz, H);
T.rowFlowDn = zeros(Lz, H);
if Z > 1 && Lz > 0
    for l = 1:Lz
        for t = 1:H
            coefP = grid.PTDF(l, grid.plantZone)';           % nP×1
            coefR = -grid.PTDF(l, grid.stationZone)';        % nR×1
            coefZ = grid.PTDF(l, :)';                        % Z×1
            cc = [T.iP(:, t); T.iR(:, t); T.iB(:, t); T.iC(:, t); T.iS(:, t); T.iO(:, t)];
            vv = [coefP; coefR; coefZ; -coefZ; coefZ; -coefZ];
            r = r + 1;
            rows = [rows, r * ones(1, numel(cc))]; cols = [cols, cc']; vals = [vals, vv']; %#ok<AGROW>
            b = [b; 0]; %#ok<AGROW>
            T.rowFlowUp(l, t) = r;
            r = r + 1;
            rows = [rows, r * ones(1, numel(cc))]; cols = [cols, cc']; vals = [vals, -vv']; %#ok<AGROW>
            b = [b; 0]; %#ok<AGROW>
            T.rowFlowDn(l, t) = r;
        end
    end
end
T.Aineq = sparse(rows, cols, vals, r, T.nv);
T.bBase = b;
T.grid = grid;
T.bigM = p.inner.bigM;
end
