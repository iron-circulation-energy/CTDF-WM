classdef TestPaperExports < matlab.unittest.TestCase
    methods(Test)
        function sourcesSeparateDerivedRenewablesAndScenarioLoad(tc)
            T=paramSources(params_default('haoji'));
            k=strcmp(T.Name,'区域日负荷'); tc.assertEqual(nnz(k),1);
            tc.verifyEqual(T.Status{k},'情景重建');
            k=strcmp(T.Name,'风光逐日出力'); tc.assertEqual(nnz(k),1);
            tc.verifyEqual(T.Status{k},'再分析转换');
        end

        function indicatorTableKeepsStarvationAndUnservedLoad(tc)
            [res,p]=fixture(); d=tempname; mkdir(d); c=onCleanup(@() rmdir(d,'s')); %#ok<NASGU>
            exportTables(res,p,d);
            T=readtable(fullfile(d,'supp_table2_indicators.csv'),'VariableNamingRule','preserve');
            tc.verifyTrue(ismember('断供概率',T.Properties.VariableNames));
            tc.verifyTrue(ismember('事件失负荷比例',T.Properties.VariableNames));
            tc.verifyTrue(ismember('气象年数',T.Properties.VariableNames));
            tc.assertTrue(isfile(fullfile(d,'supp_table2_events.csv')));
            W=readtable(fullfile(d,'supp_table2_events.csv'),'VariableNamingRule','preserve');
            tc.verifyTrue(ismember('injectedShedMWh_mean',W.Properties.VariableNames));
            tc.verifyEqual(W.nYears,2);
        end

        function elementTableKeepsDistanceKindAndAnnualSummary(tc)
            [res,p]=fixture(); d=tempname; mkdir(d); c=onCleanup(@() rmdir(d,'s')); %#ok<NASGU>
            exportTables(res,p,d);
            T=readtable(fullfile(d,'supp_table3_elements.csv'),'VariableNamingRule','preserve');
            tc.verifyTrue(ismember('距离计算',T.Properties.VariableNames));
            tc.verifyTrue(ismember('断供风险',T.Properties.VariableNames));
            tc.verifyTrue(isfile(fullfile(d,'supp_table3_annual.csv')));
            tc.verifyTrue(isfile(fullfile(d,'supp_table6_parameters.csv')));
            tc.verifyTrue(isfile(fullfile(d,'supp_table8_notation.csv')));
        end

        function unavailableDistanceIsNotPlottedAsRelativeChange(tc)
            [res,p]=fixture(); d=tempname; mkdir(d); c=onCleanup(@() rmdir(d,'s')); %#ok<NASGU>
            E=res.e5;
            E.predictionRaw=table({'full';'noNull';'full';'noNull'},0.99*ones(4,1),[1;1;2;2],nan(4,1),[1;2;1.1;2.3], ...
                'VariableNames',{'Method','gamma','state','W1','ValueErr'});
            F11_elementGain(E,plotStyle(p),fullfile(d,'elements'));
            f=openfig(fullfile(d,'elements.fig'),'invisible');
            cf=onCleanup(@() close(f)); %#ok<NASGU>
            t=findall(f,'Type','text'); labels=string(get(t,'String'));
            tc.verifyFalse(any(contains(labels,"W_1")));   % 不可用的距离不画成相对变化
        end
    end
end

function [res,p]=fixture()
p=params_default('smoke');
year=[2020;2021]; method={'M1';'M1'}; scenario={'drought';'drought'}; seed=[1;1];
v=[1;2];
E=table(year,method,scenario,seed,.1*v,.2*v,.3*v,10*v,.05*v,3*v,1e4*v,.01*v, ...
    2*v,.5*v,3*v,4*v,.5*v,2*v, ...
    'VariableNames',{'year','method','scenario','seed','pF','eventF','eventShed','shedMWh','curRate', ...
    'rustBlockMWh','cost','decTime','injectedShedMWh','injectedAnyShed','injectedSafeDays', ...
    'followupShedMWh','followupAnyShed','injectedWarningLeadDays'});
E.pShed=.2*v;
metrics=setdiff(E.Properties.VariableNames,{'year','method','scenario','seed'},'stable');
res.e3.summary=statsUtils('summaryTable',E,{'method','scenario'},metrics);
res.e3.episodes=E; res.e3.paired=table({'M1'}, {'M0'},'VariableNames',{'MethodA','MethodB'});
res.e5.table=table({'full'},{'CTDF-WM'},1e-6,1e-7,0,.2,.1,1, ...
    {'sliced_scaled'},'VariableNames',{'Name','Label','ConsErrT','RawConsRel','NegPct','W1','pF','nSeeds','DistanceMethod'});
res.e5.annualSummary=res.e3.summary;
end
