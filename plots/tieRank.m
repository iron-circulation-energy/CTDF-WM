function [rk, tied] = tieRank(mu, tol)
%TIERANK 并列名次：均值相差不超过相对容差 tol（缺省 0.1%）的方法取相同名次（越低越好）。
%   rk(i) = 1 + 明显低于 mu(i) 的方法个数；tied(i) 为真表示存在与之并列的方法。
if nargin < 2
    tol = 1e-3;
end
n = numel(mu);
rk = nan(1, n);
tied = false(1, n);
for i = 1:n
    if ~isfinite(mu(i)), continue; end
    d = (mu(i) - mu) ./ max(abs(mu(i)), eps);
    rk(i) = 1 + nnz(d > tol & isfinite(mu));
    tied(i) = nnz(abs(d) <= tol & isfinite(mu)) > 1;
end
end
