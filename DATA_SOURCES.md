# Data sources and provenance

This document records what can be established from the supplied code and data. Original project code is covered by [LICENSE](LICENSE); third-party data have separate terms described in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Bundled national inputs

The files in `data/national/` are research inputs, with a mixture of source records, derived values, and study classifications.

| File | Contents | Recorded source and processing |
| --- | --- | --- |
| `coal_plants_cn.csv` | 874 plant records | The preprocessing script identifies WRI Global Power Plant Database (GPPD) v1.3.0 as its input. It selects Chinese coal plants whose GPPD source field is `GCPT`, assigns provinces using the supplied boundaries, and writes selected plant attributes. Off-polygon points within 50 km of a boundary vertex are assigned to the nearest province; more distant coal records are omitted. |
| `re_points_cn.csv` | 65 wind/solar representative points | Derived from GPPD plant locations and capacities, grouped using the supplied provincial boundaries. Capacity-weighted medoids represent the plants; sufficiently dispersed groups use two medoids. Fallbacks use a solar representative point or a polygon-derived label point. These are study sampling locations. |
| `provinces_cn.csv` | 34 provincial units, including 31 assessed units | Names and codes come from the supplied GeoJSON. Label coordinates are calculated from the largest polygon ring. The study sets the `assessed` flag according to availability of its 2019 statistics. |
| `prov_stats_2019.csv` | Statistics for 31 provinces | The project attributes wind/solar figures to 2019 National Energy Administration statistics. Renewable consumption and consumption shares are also used to infer total electricity consumption. The table therefore includes both reported statistics and derived quantities. The complete source bibliography and compilation record are absent. |
| `uhv_dc_cn.csv` | 30 endpoint records | Literature/news compilation of UHV DC capacity, distance, year, and operating/construction status. The source table describes 29 circuits, with one three-terminal circuit represented by two receiving endpoints. The complete source list is absent. |
| `salt_cn.csv` | 11 provincial salt-cavern classifications | Literature-based site descriptions and study-assigned suitability tiers. Individual rows retain `basis`, `ref`, and `status`; four tier-3 rows are explicitly marked `待核实` (unverified). These tiers are screening assumptions, not measured storage capacities. |

The GPPD source is the [official WRI repository](https://github.com/wri/global-power-plant-database), whose v1.3.0 database is distributed under CC BY 4.0. The local preprocessing description and implementation are in [make_national.py](data/national/prep/make_national.py). It regenerates only the coal, renewable-point, and provincial-unit tables; it does not regenerate the statistics, UHV, or salt-cavern compilations. The original GPPD input CSV and its checksum are not bundled.

`config/natSources.m` and several table entries refer to `[N1]`–`[N13]`. Their corresponding full bibliography was not supplied. These identifiers are preserved without inventing a mapping. Source titles, URLs, dates/versions, and compilation details should be recovered from the authors' original records.

## Weather and derived time series

Weather is downloaded at runtime through the Open-Meteo historical API with the `era5` model selected. ERA5 is reanalysis supplied through the Copernicus Climate Change Service (C3S), as identified in [Open-Meteo's data-source and licence notice](https://open-meteo.com/en/licence). Downloaded caches under `data_real/` are excluded from version control.

The regional configuration uses 1995–2024 weather, with 2025 reserved for the trailing forecast window. The declared split is 1995–2014 for weather-model fitting, 2015–2019 for validation, and 2020–2024 for evaluation. External 2019 provincial statistics provide structural calibration. The national configuration specifies 2014–2023. See `config/params_paper.m`, `config/params_default.m`, and `config/params_national.m` for the exact settings.

`data/prepareRealData.m` transforms hourly weather into wind and solar capacity factors, applies the configured calibration, and aggregates daily energy. Regional electricity demand is reconstructed from temperature responses and study assumptions; it is not a metered load series. National load and hydro treatment likewise include model assumptions. Enabling an external load CSV requires that file's provenance to be documented separately.

`data/writeWeatherProvenance.m` records request identity, processing-source hashes, raw-cache hashes, derived-file hashes, fitting years, and calibration metadata. Its cache schema does not retain the original pre-interpolation missing-data mask or retrieval time. These manifests describe the local processing chain; they do not turn scenario quantities into observations.

## Maps and geographic derivatives

`plots/geo/china_provinces.geojson` and `plots/geo/china_map.mat` were supplied with the original source package but are excluded from the public repository. Their metadata identify only a user-supplied provincial GeoJSON in EPSG:4490, including boundary lines. They do not identify the original provider or a redistribution licence. The manuscript's Figure 1 caption cites GS(2024)0650; the correspondence between that approved base map and these files has not been established. The MAT file is a plotting derivative; the national preprocessing also uses the GeoJSON for province assignment and label coordinates. See [geographic-input instructions](plots/geo/README.md).

**The authors must establish the source and redistribution terms before public publication of these map files.** Any applicable map identification should also be recovered. Neither inclusion in this package nor the project MIT licence establishes permission for these third-party assets. Geographic derivatives in the national tables should be included in that provenance review.

## Parameters and interpretation

`config/paramSources.m` and `config/natSources.m` distinguish literature values, derived values, scenario assumptions, and items awaiting verification. Some numbered manuscript references also lack a complete bibliography in this package. Synthetic smoke-case placeholders and explicitly disabled exploratory modules remain labelled in the source. These labels should be retained when reporting results; none of the values have been changed as part of repository packaging.
