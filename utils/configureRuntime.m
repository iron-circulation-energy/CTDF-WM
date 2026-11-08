function info = configureRuntime(p)
%CONFIGURERUNTIME Bound process replication on a 24 GB cloud instance.
info=struct('requestedWorkers',0,'workers',1,'parallelAvailable',false);
if ~isfield(p,'runtime'), return; end
info.requestedWorkers=p.runtime.cpuWorkers;
info.parallelAvailable=~isempty(ver('parallel')) && license('test','Distrib_Computing_Toolbox');
if p.data.useParfor && info.parallelAvailable
    try
        pool=gcp('nocreate');
        if isempty(pool)
            pool=parpool('local',p.runtime.cpuWorkers);
        elseif pool.NumWorkers>p.runtime.cpuWorkers
            warning('configureRuntime:memory','Existing pool exceeds requested 24GB memory budget; using bounded parfor.');
        end
        info.workers=min(pool.NumWorkers,p.runtime.cpuWorkers);
    catch err
        warning('configureRuntime:serial','Parallel pool unavailable (%s); running serially.',err.message);
        info.parallelAvailable=false;
    end
end
end
