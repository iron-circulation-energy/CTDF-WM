classdef TestRunProvenanceCollision < matlab.unittest.TestCase
    methods(Test)
        function existingRunCannotBeRelabelledAsNew(tc)
            tmp=tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            d=fullfile(tmp.Folder,'common','same'); mkdir(d);
            f=fullfile(d,'config.mat'); original='prior config'; save(f,'original');
            before=fileSHA256(f);
            tc.verifyError(@()assertFreshRunDirectory(tmp.Folder,'same'),'runExperiments:existingRun');
            tc.verifyEqual(fileSHA256(f),before);
            assertFreshRunDirectory(tmp.Folder,'fresh');
        end
    end
end
