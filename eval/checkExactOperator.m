function report = checkExactOperator(opts)
%CHECKEXACTOPERATOR 小规模有限状态链上精确分布算子的数值检查：后继核、固定点、收缩比与投影。
if nargin<1, opts=struct(); end
gammas=getf(opts,'gammas',[0,.8,.9,.95,.99]);
gammas=gammas(:)';
Z=[1,0;0,1];
chains={eye(2),[0,1;1,0],[.5,.5;0,1],[.7,.3;.2,.8]};
names={'identity','alternating','absorbing','mixing'};
rows={}; ratios=nan(size(gammas));
for g=1:numel(gammas)
    gamma=gammas(g);
    for k=1:numel(chains)
        P=chains{k};
        [S,c]=exactSuccessorKernel(P,gamma);
        add(sprintf('%s fixed point',names{k}),'fixed_point',gamma,c.fixedPointResidual,1e-10);
        M=[1,0;.3,.7]; N=[0,1;.9,.1];
        A=exactSuccessorUpdate(P,M,gamma); B=exactSuccessorUpdate(P,N,gamma);
        before=0; after=0;
        for i=1:2
            before=max(before,weightedW1(Z,M(i,:),Z,N(i,:)));
            after=max(after,weightedW1(Z,A(i,:),Z,B(i,:)));
        end
        add(sprintf('%s contraction',names{k}),'contraction',gamma,after,gamma*before);
        rspec=struct('G',[1,-1;-.3,.7],'b',[-.2;.1],'theta',.4);
        for i=1:2
            rb=affineRiskBound(Z,M(i,:),Z,S(i,:),rspec);
            add(sprintf('%s risk row %d',names{k},i),'affine_risk',gamma,rb.lhs,rb.rhs);
        end
        if k==2
            target=[gamma,1;1,gamma]/(1+gamma);
            add('next-state alternating law','next_state_timing',gamma,max(abs(S-target),[],'all'),1e-12);
        end
    end
    A=exactSuccessorUpdate(eye(2),[1,0;1,0],gamma);
    B=exactSuccessorUpdate(eye(2),[0,1;0,1],gamma);
    ratios(g)=weightedW1(Z,A(1,:),Z,B(1,:))/sqrt(2);
    add('tight contraction factor','tight_contraction',gamma,abs(ratios(g)-gamma),1e-10);
    % Off-simplex distributions, common one-step atom and weighted mixtures.
    U=[2,-1;-1,2]; PU=projectSimplex(U,1); z=[.5;.5];
    raw=weightedW1([z,U(:,1)],[1-gamma,gamma],[z,U(:,2)],[1-gamma,gamma]);
    projected=weightedW1([z,PU(:,1)],[1-gamma,gamma],[z,PU(:,2)],[1-gamma,gamma]);
    add('projected exact mixture contraction','projected_contraction',gamma,projected,gamma*norm(U(:,1)-U(:,2)));
    add('projection non-expansion','projection',gamma,projected,raw);
    supported=[.3,.8;.7,.2]; w=[.3,.7];
    draw=weightedW1(U,w,supported,[.6,.4]);
    dproj=weightedW1(PU,w,supported,[.6,.4]);
    add('projection to supported weighted reference','projection_reference',gamma,dproj,draw);
end
report.table=cell2table(rows,'VariableNames',{'Item','Property','gamma','LHS','RHS','Slack','Tolerance','Pass','CheckType'});
report.tightRatio=ratios;
report.gammas=gammas;
report.scope='finite fixed-policy kernels, common Euclidean metric and fixed active mass';
report.source='main P182-203; supplement P68-81';
report.pass=all(report.table.Pass);

    function add(label,property,g,lhs,rhs)
        tol=1e-10+1e-9*max(abs([lhs,rhs]));
        rows(end+1,:)={label,property,g,lhs,rhs,rhs-lhs,tol,lhs<=rhs+tol,'exact_finite_operator'};
    end
end

function v=getf(s,f,d)
if isfield(s,f)&&~isempty(s.(f)), v=s.(f); else, v=d; end
end
