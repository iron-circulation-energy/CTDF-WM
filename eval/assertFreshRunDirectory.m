function assertFreshRunDirectory(resultsRoot, stamp)
%ASSERTFRESHRUNDIRECTORY 新运行不覆盖已有运行目录。
d=fullfile(resultsRoot,'common',stamp);
if isfolder(d) || isfile(d)
    error('runExperiments:existingRun', ...
        'Run %s already exists. Use resume=true for the same inputs, or a new stamp for a new run.',stamp);
end
end
