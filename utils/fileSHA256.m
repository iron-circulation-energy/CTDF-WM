function hash = fileSHA256(path)
%FILESHA256 Stream a file; no external executable or entire-file RAM copy.
fid=fopen(path,'rb');
if fid<0, error('fileSHA256:read','Cannot read %s',path); end
clean=onCleanup(@() fclose(fid)); %#ok<NASGU>
md=java.security.MessageDigest.getInstance('SHA-256');
while ~feof(fid)
    b=fread(fid,1024*1024,'*uint8'); md.update(b);
end
hash=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2)',1,[]));
end
