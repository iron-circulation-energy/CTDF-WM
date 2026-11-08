function spec = checkedBufferSpec(ctx, stats, cm)
%CHECKEDBUFFERSPEC 核对缓冲配置与当前统计量和参数一致。
if ~isfield(cm,'bufferSpec')
    error('bufferSpec:missing','Recompute criticalMass to obtain the shared buffer specification.');
end
spec = cm.bufferSpec;
expected = makeBufferSpec(stats,ctx.Tl,ctx.p);
if ~isequaln(spec,expected)
    error('bufferSpec:stale','Formula and verification must use the same parameter and reserve specification.');
end
fields = {'M_LL','M_occ','M_0','M_crit'};
for k=1:numel(fields)
    f=fields{k};
    if ~isfield(cm,f) || ~isequaln(cm.(f),spec.(f))
        error('bufferSpec:massMismatch','Formula field %s differs from its shared specification.',f);
    end
end
end
