function fp = sourceFingerprint(root,p)
%SOURCEFINGERPRINT Invalidate caches when model-relevant source or realised data change.
%   Only folders that determine data, dynamics, training and evaluation are hashed;
%   plotting, tests, the national assessment and top-level entry scripts are excluded,
%   so that editing them neither invalidates trained models nor blocks resuming a run.
files=dir(fullfile(root,'**','*.m'));
names={}; hashes={};
skip={'results','plots','tests','national','data_real'};
for k=1:numel(files)
    file=fullfile(files(k).folder,files(k).name);
    rel=erase(file,[root filesep]);
    top=strsplit(rel,filesep);
    if numel(top)==1 || any(strcmp(top{1},skip)), continue; end
    names{end+1,1}=rel; hashes{end+1,1}=fileSHA256(file); %#ok<AGROW>
end
[names,ix]=sort(names); hashes=hashes(ix);
fp=struct('schema',2,'sourceFiles',{names},'sourceHashes',{hashes});
if nargin>1 && strcmpi(p.weather.source,'csv') && isfile(p.weather.csvFile)
    fp.weatherSHA256=fileSHA256(p.weather.csvFile);
end
end
