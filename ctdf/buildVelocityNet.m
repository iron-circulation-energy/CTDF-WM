function [net, meta] = buildVelocityNet(dimX, dimW, cfg, seed)
%BUILDVELOCITYNET 速度场网络参数：残差 MLP + FiLM 条件化，参数以扁平结构体保存（dlarray）。
%   结构（函数式模型，与 dlnetwork 等价，便于对结构体参数求导与 AdamW 更新）：
%     条件编码 c = W_c2·mish(W_c1·[cond; w] + b_c1) + b_c2         （cond = [X_s; log(c/cRef)]，dCond 维）
%     时间编码 τ = W_t2·mish(W_t1·sinusoid(t) + b_t1) + b_t2         （dT 维正弦嵌入 → dCond 维）
%     e = [c; τ]（2·dCond 维）
%     主干 h = W_in·X_t + b_in；第 b 个残差块：
%         ĥ = LN(h)·(1 + W_g·e + b_g) + (W_β·e + b_β)，h ← h + W_2·mish(W_1·ĥ + b_1) + b_2
%     输出 v = W_out·LN(h) + b_out（D 维）
%   初始化：Glorot 均匀；各残差块末层 W_2 置零（初始为恒等映射），W_out 乘 0.01。
%   meta：维数与配置（dimX = D，dimCond = D + 1，dimW 为策略嵌入维数）。

rs = RandStream('twister', 'Seed', seed);
W = cfg.width;
dC = cfg.dCond;
dT = cfg.dT;
dimCond = dimX + 1;
prec = cfg.precision;
net = struct();
net.Wc1 = glorot(dC, dimCond + dimW, rs);  net.bc1 = zeros(dC, 1);
net.Wc2 = glorot(dC, dC, rs);              net.bc2 = zeros(dC, 1);
net.Wt1 = glorot(dC, dT, rs);              net.bt1 = zeros(dC, 1);
net.Wt2 = glorot(dC, dC, rs);              net.bt2 = zeros(dC, 1);
net.Win = glorot(W, dimX, rs);             net.bin = zeros(W, 1);
for b = 1:cfg.nBlocks
    net.(sprintf('Wg%d', b)) = glorot(W, 2 * dC, rs) * 0.1;  net.(sprintf('bg%d', b)) = zeros(W, 1);
    net.(sprintf('Wb%d', b)) = glorot(W, 2 * dC, rs) * 0.1;  net.(sprintf('bb%d', b)) = zeros(W, 1);
    net.(sprintf('W1%d', b)) = glorot(W, W, rs);             net.(sprintf('b1%d', b)) = zeros(W, 1);
    net.(sprintf('W2%d', b)) = zeros(W, W);                  net.(sprintf('b2%d', b)) = zeros(W, 1);
end
net.Wout = glorot(dimX, W, rs) * 0.01;     net.bout = zeros(dimX, 1);
fn = fieldnames(net);
for m = 1:numel(fn)
    net.(fn{m}) = dlarray(cast(net.(fn{m}), prec));
end
meta.dimX = dimX;
meta.dimCond = dimCond;
meta.dimW = dimW;
meta.width = W;
meta.dCond = dC;
meta.dT = dT;
meta.nBlocks = cfg.nBlocks;
meta.precision = prec;
meta.weightFields = fn(startsWith(fn, 'W'));
end

function A = glorot(nOut, nIn, rs)
lim = sqrt(6 / (nIn + nOut));
A = (2 * rand(rs, nOut, nIn) - 1) * lim;
end
