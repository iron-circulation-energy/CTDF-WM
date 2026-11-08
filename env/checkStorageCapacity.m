function reserved = checkStorageCapacity(x,ctx)
%CHECKSTORAGECAPACITY Enforce conservative destination reservation without disposal.
validateattributes(x,{'numeric'},{'vector','finite','real','numel',ctx.idx.n});
reserved = ctx.capacityMap*x;
tol = 1e-9*max(1,sum(x));
[excess,i] = max(reserved-ctx.capInv);
if excess > tol
    error('IronRustEnv:storageCapacity', ...
        'Inventory %d and inbound pipeline reserve exceed capacity by %.6g t.',i,excess);
end
end
