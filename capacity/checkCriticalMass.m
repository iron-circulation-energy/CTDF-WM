function out = checkCriticalMass(ctx, stats, cm)
%CHECKCRITICALMASS 固定工序预留下事件缓冲构造的有限检查。
%   低风光事件 D 与富余事件 U 分别从同一自由铁、自由锈配置出发。c = M_crit 时二者恰好用尽各自缓冲，
%   c < M_crit 时至少一个孤立事件在该配置下失效。重复事件单独报告，事件间不计恢复能力。

if nargin < 3 || isempty(cm), cm = criticalMass(stats,ctx.Tl,ctx.p); end
spec = checkedBufferSpec(ctx,stats,cm);
Mc = spec.M_crit;
seqs = {repmat('D',1,spec.Dmax),repmat('U',1,spec.Umax)};
families = {'D1','U1'};
eta = ctx.p.exp.bufferEta(:)';
validateattributes(eta,{'numeric'},{'real','finite','>',0,'<',1});
cases = {'(a) c = M_crit',1};
for v=eta
    cases(end+1,:) = {sprintf('(b) eta = %.4g',v),1-v}; %#ok<AGROW>
end
rows = {};
for k=1:size(cases,1)
    for j=1:2
        sim = preparedBufferSim(cases{k,2}*Mc,spec,seqs{j});
        rows(end+1,:) = record(cases{k,1},cases{k,2},families{j},sim); %#ok<AGROW>
    end
end
T = cell2table(rows,'VariableNames',{'Case','cOverMcrit','Family','ViolFe','ViolOx','ViolBase', ...
    'FirstDay','FirstType','ConsErr','InitialFreeFe','InitialFreeOx','UnpreparedEvents','Restored'});
out.table = T;
out.Mcrit = Mc;
out.bufferSpec = spec;
out.model = spec.model;
out.referenceOnly = spec.referenceOnly;
out.designExact = false;
out.scope = spec.scope;
out.necessityScope = 'Below M_crit, at least one attainable bound-draw event fails from the common allocation.';
isA = startsWith(T.Case,'(a)');
isB = startsWith(T.Case,'(b)');
out.summary.aPass = all(T.ViolFe(isA)==0 & T.ViolOx(isA)==0 & T.ViolBase(isA)==0);
bCases = unique(T.Case(isB));
out.summary.bPass = true;
for k=1:numel(bCases)
    sel = strcmp(T.Case,bCases{k});
    out.summary.bPass = out.summary.bPass && any(T.ViolFe(sel)+T.ViolOx(sel)+T.ViolBase(sel)>0);
end
% With zero total mass there is no smaller nonnegative design to test.
out.summary.bApplicable = Mc>0 && ~isempty(bCases);
if ~out.summary.bApplicable, out.summary.bPass = NaN; end
out.summary.maxConsErr = max(T.ConsErr,[],'omitnan');
out.summary.networkExact = false;
out.summary.empiricalBoundsExact = false;

% A repeated-event diagnostic must expose lack of restoration. It does not
% silently enlarge the recovery gap or manufacture a rate from average flux.
gap = 1;
if isfield(ctx.p.exp,'networkEventGap'), gap = ctx.p.exp.networkEventGap; end
validateattributes(gap,{'numeric'},{'scalar','real','finite','nonnegative','integer'});
normal = repmat('N',1,gap);
repeated = {[seqs{1},normal,seqs{1}],[seqs{2},normal,seqs{2}]};
recoveryRows = {};
for j=1:2
    sim = preparedBufferSim(Mc,spec,repeated{j});
    recoveryRows(end+1,:) = record('Repeated events; no recovery assumed',1,[families{j}(1),families{j}(1)],sim); %#ok<AGROW>
end
out.recovery = cell2table(recoveryRows,'VariableNames',T.Properties.VariableNames);
out.recoveryRateT = 0;
out.recoveryNote = 'N days have zero recovery unless a rate is explicitly supplied to preparedBufferSim; unprepared starts are retained.';
end

function row = record(name,ratio,family,r)
row = {name,ratio,family,r.violFe,r.violOx,r.violBase,r.first(1),r.first(2),r.consErr, ...
    r.initialFree(1),r.initialFree(2),nnz(~r.eventPrepared),r.restored};
end
