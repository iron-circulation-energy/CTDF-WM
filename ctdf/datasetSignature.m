function signature = datasetSignature(ds)
%DATASETSIGNATURE Exact content identity for standalone training checkpoints.
%   Hash numeric arrays in bounded chunks; equal counts do not imply equal data.
md = java.security.MessageDigest.getInstance('SHA-256');
fields = {'S', 'c', 'from', 'to', 'id', 'pert'};
for k = 1:numel(fields)
    v = ds.(fields{k});
    header = uint8(sprintf('%s:%s:%s;', fields{k}, class(v), mat2str(size(v))));
    md.update(typecast(header, 'int8'));
    for a = 1:1048576:numel(v)
        part = v(a:min(a + 1048575, numel(v)));
        if islogical(part), part = uint8(part); end
        md.update(typecast(part(:), 'int8'));
    end
end
signature = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
