function s = natRouteService(ref, eta, available)
%NATROUTESERVICE Size a route against fixed discharge and charging availability.
% All series use mean-load-days (multiply by 24 for MWh per MW mean load).
% eta changes charging need, never the common discharge trajectory. Charging
% beyond the cyclic inventory's available space is curtailed. Insufficient
% annual input is infeasible, even with unlimited storage capacity.
if nargin < 3
    if isfield(ref, 'chAvailable')
        available = ref.chAvailable;
    else
        available = ref.ch;
    end
end
validateattributes(eta, {'numeric'}, {'scalar','finite','>',0,'<=',1});
validateattributes(available, {'numeric'}, {'nonnegative','finite','size',size(ref.de)});
s = ref;
s.eta = eta;
s.chAvailable = available;
de = reshape(ref.de', [], 1);
ch = reshape(available', [], 1);
tol = 1e-9 * max(1, sum(de));
s.energyShortfall = max(0, sum(de) - eta * sum(ch));
s.feasible = s.energyShortfall <= tol;
s.cycleResidual = inf;
s.Pin = max(ch);
s.reason = "insufficient charging energy";
s.Eout = sum(de) / size(ref.de,1);
s.Ein = s.Eout / eta;
s.peakDis = max(de);
s.hOut = 24*s.Eout / max(s.peakDis,eps);
s.hIn = 24*s.Ein / max(s.Pin,eps);
if ~s.feasible
    s.S = inf; s.D = inf;
    s.z = inf(size(ref.de)); s.ch = zeros(size(ref.de));
    return;
end
z = zeros(size(de));
zt = 0;
net = cumsum(de-eta*ch);
floorNet = cummin([0; net]);
for pass = 1:100
    z0 = zt;
    % Reflected cumulative sum equals the day-by-day sequent-peak recursion.
    z = net - min(floorNet(2:end),-z0);
    zt = z(end);
    s.cycleResidual = abs(zt-z0);
    if s.cycleResidual <= tol
        break;
    end
end
s.feasible = s.cycleResidual <= tol;
if ~s.feasible
    s.reason = "cyclic inventory did not converge";
    s.S = inf; s.D = inf;
    s.z = inf(size(ref.de)); s.ch = zeros(size(ref.de));
    return;
end
used = max(0, ([z0;z(1:end-1)] + de - z)/eta);
s.reason = "feasible";
s.S = max([z0;z]);
s.D = s.S/max(s.peakDis,eps);
s.z = reshape(z,size(ref.de,2),[])';
s.ch = reshape(used,size(ref.de,2),[])';
s.Ein = sum(used)/size(ref.de,1);
s.hIn = 24*s.Ein/max(s.Pin,eps);
end
