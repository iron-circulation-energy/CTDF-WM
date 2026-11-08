function Mnext = exactSuccessorUpdate(P, M, gamma)
%EXACTSUCCESSORUPDATE Next-state policy evaluation on a finite state space.
%   Row i is a conditional probability law on the same finite states.
%   T(M)=(1-gamma)P+gamma*P*M. No neural optimisation or sampling is involved.
if ~isnumeric(gamma)||~isreal(gamma)||~isscalar(gamma)||~isfinite(gamma)||gamma<0||gamma>=1
    error('exactSuccessorUpdate:gamma','Discount must satisfy 0 <= gamma < 1.');
end
tol=1e-10;
if ~isnumeric(P)||~isreal(P)||isempty(P)||size(P,1)~=size(P,2)|| ...
        any(~isfinite(P(:)))||any(P(:)<0)||any(abs(sum(P,2)-1)>tol)
    error('exactSuccessorUpdate:transition','P must be a finite row stochastic square matrix.');
end
if ~isnumeric(M)||~isreal(M)||~isequal(size(M),size(P))|| ...
        any(~isfinite(M(:)))||any(M(:)<-tol)||any(abs(sum(M,2)-1)>tol)
    error('exactSuccessorUpdate:kernel','M must be a finite probability kernel on the same states.');
end
Mnext=(1-gamma)*double(P)+gamma*double(P)*double(M);
end
