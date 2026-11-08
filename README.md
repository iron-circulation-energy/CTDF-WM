# CTDF-WM: cross-regional iron circulation for coal-plant retrofits and renewable storage

MATLAB code for the manuscript *Cross-regional iron circulation bridges the low-carbon transition of coal power and the growth of renewables*.

Authors: Yuqian Liu, Guojian Sun, Peng Sun, Mao Yang and Zhe Chen.

**Status: initial research-code publication.** This source snapshot is not yet a verified reproduction release: `config/design_point.mat` and the supporting design-selection records are absent. Paper-protocol checks require this artifact, including tests reached by the smoke entry point. Geographic assets are also excluded pending provenance confirmation, so map-based figures require separate inputs. Read [REPRODUCING.md](REPRODUCING.md) before running. An article DOI and a project Zenodo archive are not yet available.

Maintained by the [Iron Circulation Energy organization](https://github.com/iron-circulation-energy).

```sh
git clone https://github.com/iron-circulation-energy/CTDF-WM.git
cd CTDF-WM
```

The code implements

- the daily multi-plant iron–rust loop model with timed rail and waterway transit (`env`, `topo`);
- the critical circulating mass, event-risk tail and design point (`capacity`, `designScan.m`, `designSelect.m`);
- the conservation-constrained temporal difference flow world model CTDF-WM and its decision rule (`ctdf`, `policies`);
- the benchmarks: fixed joint policy, stochastic model predictive control, stepwise world model and unconstrained flow (`baselines`);
- the Haoji railway–Yangtze River corridor experiments E1–E7 and model checks (`eval`);
- the 31-province route assessment and storage mix (`national`);
- main Figures 2–6 and supplementary Figures 1–14, 16–17 (`plots`); Figure 1 and Supplementary Figure 15 are separate schematics.

## Requirements

- MATLAB R2023b or later
- Deep Learning Toolbox and Optimization Toolbox
- Gurobi with its MATLAB interface is recommended for hourly dispatch and stochastic MPC; `linprog` is used otherwise
- Internet access on first run to download ERA5 data through the Open-Meteo historical weather API (no key required)

A GPU is used automatically when available (`p.ctdf.useGPU = 'auto'`).

## Setup and tests

Open MATLAB in the repository root. To run the existing test manifest with explicit failure reporting:

```matlab
setupPaths;
listed = strtrim(splitlines(fileread('tests/TEST_MANIFEST.txt')));
listed = listed(~cellfun(@isempty, listed));
testResults = runtests(fullfile('tests', strcat(listed, '.m')));
disp(table(testResults));
assert(all([testResults.Passed]), 'Tests failed or were incomplete.');
```

The manifest contains 39 test classes. Missing research artifacts can cause failures; see [REPRODUCING.md](REPRODUCING.md).

## Pipeline entry points

After the design-selection prerequisite and required input data are available:

```matlab
main(struct('case', 'smoke', 'debug', true)) % synthetic diagnostic; still runs the shared test suite
main(struct('debug', true))                  % paper pipeline; resumes completed stages
```

`main` runs the stages `download`, `import`, `tests`, `train`, `proposed`, `comparison`, `national` and `figures`, and records progress after each stage. Single stages can be run with

```matlab
main(struct('stages', {{'figures'}}))   % redraw main figures 2–6 and collect supplementary figures and tables
Fig6Panels                               % draw the four panels of Fig. 6 as separate files
SFig12                                   % redraw Supplementary Fig. 12
```

Outputs are written to `results/` (experiment results, tables and figures) and `data_real/` (downloaded and processed weather data). Main figures and supplementary figures and tables are collected in `results/paper/<run stamp>/`.

`debug=true` propagates stage errors to batch callers. Without it, `main` records failed stages and continues independent work; a zero process exit code does not establish a successful run. Smoke timings and full-paper timings have not been established for this snapshot.

## Reproducibility

- All experiments use fixed random-number streams; test years, seeds and scenarios are set in `config/params_paper.m` and `config/params_default.m`.
- Comparisons between methods are paired on identical test years and random-number streams.
- `tests/` contains the unit tests run by the `tests` stage, listed in `tests/TEST_MANIFEST.txt`.
- `reproduceRun.m` re-evaluates a stored run from its saved configuration.
- Weather downloads, trained checkpoints, the selected design artifact and complete paper results are not included in this source snapshot.
- Generated supplementary tables are Tables 2, 3, 4, 6 and 8; remaining tables and the two schematics require separate manuscript materials.

## Data sources

- ERA5 hourly reanalysis (Hersbach et al., 2020) through Open-Meteo.
- Global Power Plant Database v1.3.0 (World Resources Institute).
- Provincial wind and solar statistics of the National Energy Administration of China, 2019.
- Province boundaries and their MAT plotting cache are excluded from this public repository pending source and redistribution confirmation. See [the geographic-input instructions](plots/geo/README.md) for affected functions and expected inputs.

See [DATA_SOURCES.md](DATA_SOURCES.md) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for file-level attribution and outstanding source records. Optional regeneration of the national CSV inputs uses Python with NumPy and Matplotlib; Python is not needed to read the supplied CSVs in MATLAB.

## Collaboration

Use issues for reproducibility reports and pull requests for changes. See [CONTRIBUTING.md](CONTRIBUTING.md) and [GOVERNANCE.md](GOVERNANCE.md) for the shared maintenance workflow.

## Citation

See [CITATION.cff](CITATION.cff) for software attribution. Cite the article once its publication metadata is available. Until a release is archived, record the commit identifier used in an analysis.

## License

Original software and documentation use the MIT License, see [LICENSE](LICENSE). Third-party data retain their own terms; the MIT license does not override them.
