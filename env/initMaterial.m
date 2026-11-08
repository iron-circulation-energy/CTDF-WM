function [x, gInv, gLine] = initMaterial(c, soc, ctx, mode, rs)
%INITMATERIAL 按循环铁总质量 c 与初始荷电状态 soc 初始化物料分布与载体品质。
%   虚拟储备 V = reserveFrac·c（缺省 0）；铁 c_Fe = soc·(c − V)，锈 c_Ox = (1 − soc)·(c − V)。
%   mode = 'deterministic'：按 p.init.feSplit / oxSplit 在 电厂/还原站/枢纽/管道 间分配
%          （电厂按容量份额、还原站按还原功率份额、枢纽与管道格均分），品质指数为 1；
%   mode = 'random'：在全部铁分量（含在途铁）与全部锈分量上分别按 Dirichlet(1) 随机分配，
%          品质指数在 [floor, 1] 上均匀抽样（数据采集用，保证状态覆盖）。
%   对两种物料分别按目的库存+全部在途预留的仓容约束重分配；保留总量与SOC。
%   要求的Fe或Ox总量超过各自总仓容时明确报错，不裁掉物料。
%   输出满足 1ᵀx = c、x ≥ 0、capacityMap*x ≤ capInv。

p = ctx.p;
idx = ctx.idx;
topo = ctx.topo;
validateattributes(c, {'numeric'}, {'scalar','finite','nonnegative'});
validateattributes(soc, {'numeric'}, {'scalar','finite','>=',0,'<=',1});
validateattributes(p.makeup.reserveFrac, {'numeric'}, {'scalar','finite','>=',0,'<=',1});
x = zeros(idx.n, 1);
V = p.makeup.reserveFrac * c;
x(idx.V) = V;
cFe = soc * (c - V);
cOx = (1 - soc) * (c - V);
fePipe = [];
oxPipe = [];
for e = 1:topo.nE
    if topo.mat(e) == 1
        fePipe = [fePipe; idx.q{e}]; %#ok<AGROW>
    else
        oxPipe = [oxPipe; idx.q{e}]; %#ok<AGROW>
    end
end
switch lower(mode)
    case 'deterministic'
        sp = p.init.feSplit(:)';
        so = p.init.oxSplit(:)';
        if topo.nH == 0
            sp(2) = sp(2) + sp(3);
            sp(3) = 0;
            so(2) = so(2) + so(3);
            so(3) = 0;
        end
        x(idx.IFe) = x(idx.IFe) + sp(1) * cFe * ctx.shareP;
        x(idx.SFe) = x(idx.SFe) + sp(2) * cFe * ctx.shareR;
        if topo.nH > 0
            x(idx.HFe) = x(idx.HFe) + sp(3) * cFe / topo.nH;
            x(idx.HOx) = x(idx.HOx) + so(3) * cOx / topo.nH;
        end
        x(fePipe) = x(fePipe) + sp(4) * cFe / numel(fePipe);
        x(idx.IOx) = x(idx.IOx) + so(1) * cOx * ctx.shareP;
        x(idx.SOx) = x(idx.SOx) + so(2) * cOx * ctx.shareR;
        x(oxPipe) = x(oxPipe) + so(4) * cOx / numel(oxPipe);
        gInv = ones(idx.nInv, 1);
        gLine = ones(topo.nE, 1);
    case 'random'
        feComp = [idx.IFe; idx.SFe; idx.HFe; fePipe];
        oxComp = [idx.IOx; idx.SOx; idx.HOx; oxPipe];
        a = -log(rand(rs, numel(feComp), 1));
        x(feComp) = cFe * a / sum(a);
        a = -log(rand(rs, numel(oxComp), 1));
        x(oxComp) = cOx * a / sum(a);
        lo = p.aging.floor;
        gInv = lo + (1 - lo) * rand(rs, idx.nInv, 1);
        gLine = lo + (1 - lo) * rand(rs, topo.nE, 1);
    otherwise
        error('initMaterial:mode', '未知初始化方式 %s。', mode);
end
% Project each material's proposed allocation onto destination-group capacity.
% Preserve Fe/Ox totals and within-group proportions; do not discard excess.
for mat = 1:2
    groups = find(idx.matOf(1:idx.nInv)==mat);
    requested = ctx.capacityMap(groups,:)*x;
    mass = sum(requested);
    caps = ctx.capInv(groups);
    if mass > sum(caps) + 1e-9*max(1,c)
        error('initMaterial:capacity', ...
            'Requested material %d mass %.6g t exceeds reserved storage %.6g t.',mat,mass,sum(caps));
    end
    assigned = min(requested,caps);
    remainder = max(0,mass-sum(assigned));
    assigned = assigned + waterfill(remainder,max(caps-assigned,0),max(requested,1));
    for j = 1:numel(groups)
        components = find(ctx.capacityMap(groups(j),:));
        if requested(j)>0
            x(components) = x(components)*(assigned(j)/requested(j));
        else
            x(components) = 0;
            x(groups(j)) = assigned(j);
        end
    end
end
% 消除舍入误差，使 1ᵀx = c 精确成立（残差计入最大分量，保持 V 的设定值与非负性）
[~, im] = max(x);
x(im) = x(im) + (c - sum(x));
checkStorageCapacity(x,ctx);
if ~p.aging.enable
    gInv(:) = 1;
    gLine(:) = 1;
end
end
