# Reproducing the research

This source snapshot accompanies the manuscript **Cross-regional iron circulation bridges the low-carbon transition of coal power and the growth of renewables**. It has not been validated as a complete reproduction of the manuscript's numerical results.

## Required environment

- MATLAB R2023b or later, Deep Learning Toolbox and Optimization Toolbox.
- Optional Gurobi MATLAB interface for dispatch/MPC performance. The built-in fallback is `linprog`.
- Optional GPU support requires a compatible MATLAB GPU environment. CPU execution is supported.
- Network access for historical weather acquisition; API availability and quotas affect downloads.

## Missing design-selection artifact

`config/params_paper.m` reads `config/design_point.mat`. Without it, `p.design.ready` is false and the paper preflight rejects the configuration. The source ZIP does not include this file or the scan/selection records supporting it. The shared tests include paper-protocol checks, so the synthetic smoke entry point is also affected.

The supplied manuscript describes 3,825 MW charging power and 1.75 million tonnes of circulating mass. The unspecialized configuration defaults to 2.0 million tonnes. These are not interchangeable reproduction settings.

To complete the paper release, restore the author-generated `design_point.mat`, together with the scan tables, validation-year episode records, selection rule and source revision that produced it. Alternatively, reproduce the original validation-only scan and selection procedure from its complete candidate grid and prepared weather inputs. Do not create an artifact simply by copying reported final numbers.

`designScan(pMults, cMasses, merge)` evaluates candidates and writes an initial minimum-cost selection. `designSelect(stamps, 1)` then applies the paired one-standard-error rule and selects the lowest unserved load among statistically tied designs. Its input stamps refer to scan directories under `results/designScan/`. The default `designScan()` grid omits the reported 1.75 Mt candidate and is not documented as the full manuscript scan grid. The original grid and any boundary expansions must be recovered before claiming paper reproduction.

`main` does not automatically run either design-selection function. Its `import` stage runs the paper preflight. Weather preparation and design selection therefore require explicit setup before the full pipeline; the supplied ZIP does not establish a verified clean-checkout bootstrap procedure.

## Data boundaries

The corridor protocol uses 1995–2014 training, 2015–2019 validation and 2020–2024 test years. Required tail coverage is checked by the data preparation/preflight code. Load is a temperature-responsive reconstruction, not metered plant demand. The national assessment describes 2014–2023 weather with a 2019 system structure.

Preserve downloaded inputs, query metadata, SHA256 records, processed inputs and configuration alongside each run. Partial national calculations can be produced from fewer available years; check complete coverage and final stage status before comparing them with the manuscript's ten-year results. See `data/writeWeatherProvenance.m`, `eval/paperProtocolPreflight.m` and [DATA_SOURCES.md](DATA_SOURCES.md).

## Run and inspect

Map-based figures additionally require separately provided, permitted geographic assets. The original `plots/geo/china_map.mat` and `china_provinces.geojson` files are excluded pending provenance confirmation. This also affects regeneration of the national tables from raw GPPD data. The supplied numeric CSVs remain available for model input. See [geographic inputs](plots/geo/README.md).

Once the prerequisites are restored, use the test command in [README.md](README.md), followed by `main(struct('debug', true))`. Inspect the returned summary and saved progress, not just the shell exit code. Single-stage calls still obey dependencies and may report that a prerequisite is pending.

The default pipeline may train several models and run substantial optimization workloads. No runtime guarantee is made. Full numerical reproduction has not been run as part of repository packaging.

## Expected outputs

- Experiment blocks E1–E7, capacity checks and model checks under `results/`.
- Main Figures 2–6; supplementary Figures 1–14 and 16–17.
- Generated supplementary Tables 2, 3, 4, 6 and 8.
- Figure 1, Supplementary Figure 15 and the remaining tables are separate manuscript materials.

Preserve the exact code commit, MATLAB/toolbox versions, solver version, seeds, selected design, input hashes and evaluation outputs for a release archive. No project Zenodo DOI or article DOI is claimed by this snapshot.
