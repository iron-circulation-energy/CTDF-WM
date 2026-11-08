function A = buildCapacityMap(idx)
%BUILDCAPACITYMAP Inventory plus all inbound material reserved at its destination.
% Every active material component belongs to exactly one storage reservation;
% virtual reserve V has no physical silo. Arrival and pipeline shifting keep
% these reservations unchanged.
rows = (1:idx.nInv)';
cols = rows;
for e = 1:numel(idx.q)
    rows = [rows; repmat(idx.lineTgt(e),numel(idx.q{e}),1)]; %#ok<AGROW>
    cols = [cols; idx.q{e}(:)]; %#ok<AGROW>
end
A = sparse(rows,cols,ones(size(rows)),idx.nInv,idx.n);
end
