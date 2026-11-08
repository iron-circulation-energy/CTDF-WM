# Validation record

Date: 2026-11-08.

The supplied test manifest was run locally on macOS ARM64 with MATLAB R2023b Update 1, Deep Learning Toolbox and Optimization Toolbox. Gurobi was not available; dispatch used the `linprog` fallback. The suite was rerun against the public source tree with the two geographic assets excluded; the counts and failing test names were unchanged.

- Test classes: 39.
- Test cases: 177.
- Passed: 174.
- Failed: 3.
- Incomplete: 0.

The failing cases are:

1. `TestPaperProtocol/staticCheckCountsActualPlannedModelsAndEpisodes`
2. `TestPaperProtocol/absentDataIsMissingWithoutFilesystemOrNetworkSideEffects`
3. `TestPaperProtocol/paperPredictionBudgetCannotBeOverridden`

All three check paper-protocol conformance. The clean source snapshot lacks `config/design_point.mat`, leaving `design.ready` false. The static preflight rejects an unselected design. No test assertions, model code, numerical parameters or numeric CSV inputs were altered during packaging. `plots/geo/china_map.mat` and `china_provinces.geojson` are excluded from the public history pending provenance confirmation; the tests do not validate map-based figure generation without these inputs.

Run the manifest command in the README to obtain fresh results in your environment. Restore the verified design artifact and its provenance before considering this a reproduction release. Full-paper training, weather acquisition and numerical reproduction were not run during packaging. Passing unit tests alone would not establish reproduction of manuscript results.
