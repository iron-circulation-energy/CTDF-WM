function [Mstar, cert] = exactSuccessorKernel(P, gamma)
%EXACTSUCCESSORKERNEL Solve the finite next-state successor fixed point.
%   The initial/current state is not included. Reducible chains are allowed.
exactSuccessorUpdate(P,eye(size(P,1)),gamma); % shared input contract
P=double(P);
A=eye(size(P))-gamma*P;
Mstar=(1-gamma)*(A\P);
cert.fixedPointResidual=max(abs(Mstar-exactSuccessorUpdate(P,Mstar,gamma)),[],'all');
cert.rowMassResidual=max(abs(sum(Mstar,2)-1));
cert.minProbability=min(Mstar(:));
cert.rcond=rcond(full(A));
cert.gamma=gamma;
cert.timing='next_state_T_ge_1';
cert.scope='finite_fixed_policy_kernel';
end
