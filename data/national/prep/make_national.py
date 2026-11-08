"""全国评估输入数据整理（一次性预处理，结果已随代码提供在 data/national/，MATLAB 端只读取 CSV）。

用法：python3 make_national.py <GPPD csv> <省级 GeoJSON> <输出目录>
  GPPD：WRI Global Power Plant Database v1.3.0（CC BY 4.0），
        https://github.com/wri/global-power-plant-database（output_database/global_power_plant_database.csv）
  GeoJSON：用户提供的标准中国省级行政区底图（plots/geo/china_provinces.geojson，EPSG:4490）

输出：
  coal_plants_cn.csv  中国燃煤电厂（GPPD primary_fuel = Coal 且 source = GCPT），按点在多边形判断所在省份；
                      落在所有多边形之外（海岸线简化误差）的电厂归入距离最近的省（距离 ≤ 50 km，写入 distKm）。
  re_points_cn.csv    各省风电、光伏代表点：GPPD 中该省风电（或光伏）电厂按装机加权的“中心点”（medoid，
                      即到其余电厂加权大圆距离之和最小的实际厂址）；加权均方根距离 > 350 km 且电厂数 ≥ 10 时
                      用两个代表点（加权 k-medoids，k = 2），权重为各簇装机占比；该省 GPPD 中没有风电厂时取光伏
                      中心点（method = pvMedoid），仍没有则取省级多边形最大环的顶点均值（method = label）。
  provinces_cn.csv    省级单元名称、国标码、简称、标注点、是否参与评估（港澳台无 2019 年统计数据，不参与评估）。
"""
import csv
import json
import math
import sys

import numpy as np
from matplotlib.path import Path

R_EARTH = 6371.0


def hav(lon1, lat1, lon2, lat2):
    lon1, lat1, lon2, lat2 = map(np.radians, (lon1, lat1, lon2, lat2))
    a = np.sin((lat2 - lat1) / 2) ** 2 + np.cos(lat1) * np.cos(lat2) * np.sin((lon2 - lon1) / 2) ** 2
    return 2 * R_EARTH * np.arcsin(np.sqrt(np.minimum(1.0, a)))


def load_prov(geo):
    g = json.load(open(geo, encoding='utf-8'))
    prov = []
    for f in g['features']:
        if f['geometry']['type'] != 'MultiPolygon':
            continue
        name = f['properties']['name']
        gb = f['properties'].get('gb', '')
        polys = []
        for poly in f['geometry']['coordinates']:
            outer = np.asarray(poly[0], float)
            holes = [np.asarray(h, float) for h in poly[1:]]
            polys.append((Path(outer[:, :2]), [Path(h[:, :2]) for h in holes], outer[:, :2]))
        big = max(polys, key=lambda t: len(t[2]))[2]
        prov.append(dict(name=name, gb=gb, polys=polys, label=big.mean(axis=0)))
    prov.sort(key=lambda d: d['gb'])
    return prov


def locate(prov, lon, lat):
    pt = (lon, lat)
    for i, p in enumerate(prov):
        for outer, holes, _ in p['polys']:
            if outer.contains_point(pt) and not any(h.contains_point(pt) for h in holes):
                return i, 0.0
    # 最近省份（到边界顶点的最小距离）
    best, bd = -1, 1e9
    for i, p in enumerate(prov):
        for _, _, ring in p['polys']:
            d = hav(lon, lat, ring[:, 0], ring[:, 1]).min()
            if d < bd:
                best, bd = i, d
    return best, bd


def wmedoid(lon, lat, w, idx):
    D = hav(lon[idx][:, None], lat[idx][:, None], lon[idx][None, :], lat[idx][None, :])
    c = (D * w[idx][None, :]).sum(axis=1)
    k = idx[int(np.argmin(c))]
    rms = math.sqrt((w[idx] * hav(lon[k], lat[k], lon[idx], lat[idx]) ** 2).sum() / w[idx].sum())
    return k, rms


def kmedoids2(lon, lat, w, idx, iters=50):
    # 初值：加权中心点与离它加权距离最远的电厂
    k1, _ = wmedoid(lon, lat, w, idx)
    d = hav(lon[k1], lat[k1], lon[idx], lat[idx]) * np.sqrt(w[idx])
    k2 = idx[int(np.argmax(d))]
    med = [k1, k2]
    for _ in range(iters):
        D = np.stack([hav(lon[m], lat[m], lon[idx], lat[idx]) for m in med])
        lab = D.argmin(axis=0)
        new = []
        for c in range(2):
            sub = idx[lab == c]
            if len(sub) == 0:
                new.append(med[c])
                continue
            new.append(wmedoid(lon, lat, w, sub)[0])
        if new == med:
            break
        med = new
    D = np.stack([hav(lon[m], lat[m], lon[idx], lat[idx]) for m in med])
    lab = D.argmin(axis=0)
    wt = [w[idx][lab == c].sum() for c in range(2)]
    return med, wt


def main(gppd, geo, out):
    prov = load_prov(geo)
    rows = list(csv.DictReader(open(gppd, encoding='utf-8')))
    chn = [r for r in rows if r['country'] == 'CHN']
    # 1 燃煤电厂
    # 只取 GCPT 来源的记录：GPPD 中其余 72 条中国燃煤记录（Industry About 等）多与 GCPT 记录重复或燃料标注不一致
    coal = [r for r in chn if r['primary_fuel'] == 'Coal' and r['source'] == 'GCPT']
    with open(f'{out}/coal_plants_cn.csv', 'w', newline='', encoding='utf-8') as fh:
        wtr = csv.writer(fh)
        wtr.writerow(['gppd_id', 'name', 'prov', 'lon', 'lat', 'mw', 'year', 'owner', 'source', 'distKm'])
        nout = 0
        for r in coal:
            lon, lat = float(r['longitude']), float(r['latitude'])
            i, d = locate(prov, lon, lat)
            if d > 50:
                print('远离陆地，跳过：', r['name'], lon, lat, round(d, 1))
                nout += 1
                continue
            yr = r['commissioning_year']
            yr = '' if yr == '' else str(int(round(float(yr))))
            wtr.writerow([r['gppd_idnr'], r['name'], prov[i]['name'], f'{lon:.4f}', f'{lat:.4f}',
                          f"{float(r['capacity_mw']):.1f}", yr, r['owner'], r['source'], f'{d:.1f}'])
    # 2 风光代表点
    with open(f'{out}/re_points_cn.csv', 'w', newline='', encoding='utf-8') as fh:
        wtr = csv.writer(fh)
        wtr.writerow(['prov', 'kind', 'k', 'lon', 'lat', 'weight', 'nPlants', 'mwGPPD', 'rmsKm', 'method', 'siteName'])
        med1 = {}
        for kind, fuel in (('pv', 'Solar'), ('wind', 'Wind')):
            sel = [r for r in chn if r['primary_fuel'] == fuel]
            lon = np.array([float(r['longitude']) for r in sel])
            lat = np.array([float(r['latitude']) for r in sel])
            w = np.array([float(r['capacity_mw']) for r in sel])
            pid = np.array([locate(prov, a, b)[0] for a, b in zip(lon, lat)])
            for i, p in enumerate(prov):
                if p['name'] in ('香港特别行政区', '澳门特别行政区', '台湾省'):
                    continue
                idx = np.where(pid == i)[0]
                mw = w[idx].sum()
                if len(idx) == 0:
                    if kind == 'wind' and p['name'] in med1:
                        a, b, nm = med1[p['name']]
                        wtr.writerow([p['name'], kind, 1, f'{a:.4f}', f'{b:.4f}', '1', 0, '0', '', 'pvMedoid', nm])
                    else:
                        L = p['label']
                        wtr.writerow([p['name'], kind, 1, f'{L[0]:.4f}', f'{L[1]:.4f}', '1', 0, '0', '', 'label', ''])
                    continue
                k, rms = wmedoid(lon, lat, w, idx)
                if kind == 'pv':
                    med1[p['name']] = (lon[k], lat[k], sel[k]['name'])
                if rms > 350 and len(idx) >= 10:
                    med, wt = kmedoids2(lon, lat, w, idx)
                    for c in range(2):
                        m = med[c]
                        wtr.writerow([p['name'], kind, c + 1, f'{lon[m]:.4f}', f'{lat[m]:.4f}', f'{wt[c] / mw:.3f}',
                                      len(idx), f'{mw:.0f}', f'{rms:.0f}', 'kmedoids2', sel[m]['name']])
                else:
                    wtr.writerow([p['name'], kind, 1, f'{lon[k]:.4f}', f'{lat[k]:.4f}', '1', len(idx), f'{mw:.0f}',
                                  f'{rms:.0f}', 'medoid', sel[k]['name']])
    # 3 省份列表（名称、国标码、标注点）
    with open(f'{out}/provinces_cn.csv', 'w', newline='', encoding='utf-8') as fh:
        wtr = csv.writer(fh)
        wtr.writerow(['prov', 'gb', 'short', 'labelLon', 'labelLat', 'assessed'])
        for p in prov:
            short = p['name']
            for suf in ('维吾尔自治区', '壮族自治区', '回族自治区', '特别行政区', '自治区', '省', '市'):
                if short.endswith(suf):
                    short = short[: -len(suf)]
                    break
            ass = 0 if p['name'] in ('香港特别行政区', '澳门特别行政区', '台湾省') else 1
            wtr.writerow([p['name'], p['gb'], short, f"{p['label'][0]:.4f}", f"{p['label'][1]:.4f}", ass])


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3])
