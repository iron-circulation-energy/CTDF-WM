function res = preparedBufferSim(c, spec, seq, opts)
%PREPAREDBUFFERSIM Fixed-reserve reduced buffer model.
% D converts up to deltaD of free iron to free rust; U reverses that conversion.
% Reserve and safety mass never enter either free stock. N transfers material
% toward BOTH buffer targets only when opts.recoveryRateT is explicitly positive.
% opts.initialFree=[Fe Ox] declares one allocation; otherwise split='prop' or
% 'rustFirst' allocates c-baseMass. Independent calls start from that same state.
% The result records unprepared event starts rather than assuming restoration.

if nargin < 4, opts = struct(); end
validateattributes(c,{'numeric'},{'scalar','real','finite','nonnegative'});
if isstring(seq) && isscalar(seq), seq = char(seq); end
if ~ischar(seq) || (~isempty(seq) && ~isrow(seq)) || any(~ismember(seq,'DUN'))
    error('preparedBufferSim:sequence','Sequence must contain only D, U and N.');
end
rate = getf(opts,'recoveryRateT',0);
validateattributes(rate,{'numeric'},{'scalar','real','finite','nonnegative'});
targets = [spec.freeFeTarget,spec.freeOxTarget];
base = spec.M_occ + spec.safetyT;
tol = 64*eps(max([1,c,base,sum(targets)]));
nK = numel(seq);
free = c-base;
res = struct('model',spec.model,'bufferSpec',spec,'c',c,'Mcrit',spec.M_crit, ...
    'allocationFeasible',free>=-tol,'baseShortfallT',max(-free,0),'violBase',double(free < -tol), ...
    'violFe',0,'violOx',0,'first',[NaN,NaN],'consErr',NaN,'recoveryRateT',rate, ...
    'restored',false,'networkExact',false);
res.shortFe = zeros(nK,1);
res.shortOx = zeros(nK,1);
res.recoveryTransfer = zeros(nK,1); % positive converts rust to iron
res.traceFree = nan(nK+1,2);
res.traceReserve = repmat(spec.M_occ,nK+1,1);
res.traceSafety = repmat(spec.safetyT,nK+1,1);
res.preparedBefore = false(nK,1);
res.preparedAfter = false(nK,1);
starts = (seq~='N') & [true,seq(2:end)~=seq(1:end-1)];
if isempty(seq), starts = false(1,0); end
res.eventStartDays = find(starts(:));
res.eventPrepared = false(numel(res.eventStartDays),1);
res.initialFree = [NaN,NaN];
if ~res.allocationFeasible
    res.first = [0,0];
    return;
end
free = max(free,0);
if isfield(opts,'initialFree')
    initial = reshape(opts.initialFree,1,[]);
    validateattributes(initial,{'numeric'},{'real','finite','nonnegative','numel',2});
    if abs(sum(initial)-free)>tol
        error('preparedBufferSim:allocationMass','Free allocations must sum to mass minus disjoint reserve and safety.');
    end
else
    switch getf(opts,'split','prop')
        case 'prop'
            if sum(targets)>0
                initial = min(1,free/sum(targets))*targets;
            else
                initial = [0,0];
            end
            initial(1) = initial(1)+max(0,free-sum(initial));
        case 'rustFirst'
            initial = [free-min(free,targets(2)),min(free,targets(2))];
        otherwise
            error('preparedBufferSim:split','Unknown free-buffer allocation.');
    end
end
res.initialFree = initial;
res.traceFree(1,:) = initial;
stock = initial;
for k = 1:nK
    res.preparedBefore(k) = all(stock >= targets-tol);
    if seq(k)=='D'
        draw = min(spec.deltaD,stock(1));
        res.shortFe(k) = max(0,spec.deltaD-draw);
        stock = stock+[-draw,draw];
    elseif seq(k)=='U'
        draw = min(spec.deltaU,stock(2));
        res.shortOx(k) = max(0,spec.deltaU-draw);
        stock = stock+[draw,-draw];
    elseif stock(1)<targets(1)-tol
        v = min([rate,targets(1)-stock(1),max(stock(2)-targets(2),0)]);
        stock = stock+[v,-v];
        res.recoveryTransfer(k) = v;
    elseif stock(2)<targets(2)-tol
        v = min([rate,targets(2)-stock(2),max(stock(1)-targets(1),0)]);
        stock = stock+[-v,v];
        res.recoveryTransfer(k) = -v;
    end
    res.traceFree(k+1,:) = stock;
    res.preparedAfter(k) = all(stock >= targets-tol);
end
res.violFe = nnz(res.shortFe>tol);
res.violOx = nnz(res.shortOx>tol);
first = find(res.shortFe>tol | res.shortOx>tol,1);
if ~isempty(first), res.first = [first,1+(res.shortOx(first)>tol)]; end
res.eventPrepared = res.preparedBefore(res.eventStartDays);
res.restored = all(stock>=targets-tol);
res.consErr = max(abs(sum(res.traceFree,2)+res.traceReserve+res.traceSafety-c));
end

function v = getf(s,f,d)
if isfield(s,f) && ~isempty(s.(f)), v=s.(f); else, v=d; end
end
