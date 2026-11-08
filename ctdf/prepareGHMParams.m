function [params, useGPU] = prepareGHMParams(model, params)
%PREPAREGHMPARAMS Honour the current device setting, including cached CPU models.
flag = model.cfg.useGPU;
if ischar(flag) || isstring(flag)
    useGPU = strcmpi(flag, 'auto') && canUseGPU();
else
    useGPU = logical(flag) && canUseGPU();
end
fn = fieldnames(params);
for k = 1:numel(fn)
    v = params.(fn{k});
    if isa(v, 'dlarray'), v = extractdata(v); end
    if useGPU
        v = gpuArray(cast(v, model.cfg.precision));
    elseif isa(v, 'gpuArray')
        v = gather(v);
    end
    params.(fn{k}) = v;
end
end
