classdef TestExperimentSelection < matlab.unittest.TestCase
    methods(Test)
        function unknownOrRepeatedExperimentsFailBeforePreparingData(tc)
            p=params_default('smoke');
            tc.verifyError(@()runExperiments(p,struct('only',{{'E44'}},'skipTests',true)), ...
                'runExperiments:only');
            tc.verifyError(@()runExperiments(p,struct('only',{{'E4','e4'}},'skipTests',true)), ...
                'runExperiments:only');
        end
    end
end
