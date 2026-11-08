# Geographic inputs

The original source package included `china_map.mat` and `china_provinces.geojson`. They are excluded from this public repository pending confirmation of their provider, source version and redistribution terms. The original files remain with the authors; no replacement geometry or implied licence is supplied here.

Map-based figures call `plots/loadChinaMap.m` and require a compatible, permitted `china_map.mat` in this directory. The loader expects `provNameCode`, `provRings`, `provLabel`, `bndLines`, `bndIsNanhai` and `sourceCode`; name and source fields use UTF-16 code units. A raw GeoJSON file alone does not satisfy this loader.

Affected outputs include the corridor map and national storage, iron-mass, route and sustainability maps. `main` can save national numerical results before failing in national figure generation. Some figure exporters catch individual panel errors and write a "Panel pending" placeholder, so an exported figure file is not evidence that every panel is complete. Inspect the run summary and figure contents.

Regenerating the national input tables with `data/national/prep/make_national.py` requires a permitted provincial GeoJSON with the documented `name`/`gb` properties and MultiPolygon geometry. The numeric CSVs already in `data/national/` can be read without regenerating them.

Before adding geographic assets to a release, record their provider, source URL/version, applicable terms, transformations and correspondence to any map approval number. The manuscript cites GS(2024)0650, but that citation has not been linked to these source files. Local geographic files are ignored by Git to prevent accidental publication until the provenance review is complete.
