# Third-party notices

The [MIT licence](LICENSE) covers the authors' original project code and documentation. It does not relicense third-party data, maps, or separately installed software. The following notices distinguish confirmed source terms from information that remains unresolved.

## WRI Global Power Plant Database

Source: World Resources Institute and the Global Power Plant Database contributors, **Global Power Plant Database v1.3.0**. The [official WRI repository](https://github.com/wri/global-power-plant-database) identifies the database licence as [Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/).

Affected bundled files include `data/national/coal_plants_cn.csv` and `data/national/re_points_cn.csv`. The project modifies the source data by selecting records/fields, assigning provinces, formatting coordinates and attributes, and deriving representative renewable locations. See [DATA_SOURCES.md](DATA_SOURCES.md) and `data/national/prep/make_national.py` for the processing details. Preserve source attribution, the licence link, and this indication of changes when redistributing these data or adaptations. Geographic inputs used in the transformations have a separate unresolved provenance issue below.

## Open-Meteo and ERA5 weather

The project downloads weather from Open-Meteo at runtime. [Open-Meteo's licence page](https://open-meteo.com/en/licence) offers API data under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) and identifies C3S as its reanalysis source. Credit Open-Meteo and ERA5/C3S, link the applicable notices, and identify transformations when distributing derived data or figures. Open-Meteo also requires a source link beside displayed data.

A suitable project-specific description is: "Weather data: [Open-Meteo](https://open-meteo.com/), using ERA5 reanalysis from C3S. CTDF-WM applies capacity-factor conversion, calibration, and daily aggregation; its load series is a temperature-based scenario reconstruction."

The code cites Hersbach et al. (2020), *Quarterly Journal of the Royal Meteorological Society*, 146:1999–2049, for ERA5. API access conditions and quotas are separate from the data licence; consult the provider when downloading. This repository does not bundle the downloaded weather caches.

## Provincial boundaries: provenance unresolved

The following files were present in the supplied source package and are excluded from the public Git history pending provenance confirmation:

- `plots/geo/china_provinces.geojson`
- `plots/geo/china_map.mat`

Their recorded provenance is only "user-provided". The manuscript's Figure 1 caption names base-map approval number GS(2024)0650, but the supplied files do not establish that these geographic assets correspond to that approved map, identify their original provider, or document redistribution terms. The MIT licence does not cover these files. Establish and record their source and redistribution terms before adding them. See [geographic inputs](plots/geo/README.md) for the expected local inputs. The numeric national tables retain derived labels and spatial assignments; the missing source records remain a documented provenance limitation.

## Other national compilations

`data/national/prov_stats_2019.csv`, `data/national/uhv_dc_cn.csv`, and `data/national/salt_cn.csv` contain compiled statistics, literature-derived entries, and study classifications. Available source descriptions are summarized in [DATA_SOURCES.md](DATA_SOURCES.md). The original numbered bibliography and source notices are not fully documented. These research tables are included with their original source labels and unresolved references; the project's MIT licence does not override any underlying source terms. Completing those records remains required for a verified reproduction release.

## External software

MATLAB and its toolboxes, the optional Gurobi MATLAB interface, and Python preprocessing packages are installed separately and retain their own licences. Their presence in the requirements does not convey those licences through this repository. No third-party program binaries are bundled here.
