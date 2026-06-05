#!/usr/bin/env python3
"""224_naver_sector_rotation_features.py — Cycle 58S preparation

10 sector ETFs (네이버 fetched) → market-wide sector rotation features.

Defensive vs Cyclical 분류:
  Defensive: 은행 (091170), 바이오 (244580), 헬스케어 (143860)
  Cyclical:  반도체 (091160), IT (139260), 자동차 (091180),
             에너지화학 (117460), 미디어 (266360)
  Benchmark: 200 (069500)

Features (all PIT lag1):
  1. defensive_minus_cyclical_21d (relative 21-day return diff)
  2. defensive_minus_cyclical_63d (3-month rotation)
  3. sector_dispersion_z (cross-sectional return std, regime indicator)
  4. health_it_ratio (헬스케어/IT 비율 = defensive/cyclical 대표)
  5. health_minus_semiconductor_21d (most opposite sectors)
  6. defensive_pct_outperform (% defensive ETFs > benchmark)
"""
import pandas as pd
import numpy as np
from pathlib import Path

WS = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/04_Research/decision_framework/bearish_forecast_v2_alt_data")
IN_PATH = WS / "outputs/01_data/naver_sector_etf_raw.parquet"
OUT_PATH = WS / "outputs/01_data/sector_rotation_features.parquet"

# Categorization
DEFENSIVE = ['KODEX_은행', 'KODEX_바이오', 'TIGER_헬스케어']
CYCLICAL = ['KODEX_반도체', 'TIGER_200_IT', 'KODEX_자동차',
            'KODEX_에너지화학', 'KODEX_미디어']
BENCHMARK = 'KODEX_200'

# Load
d = pd.read_parquet(IN_PATH)
d['Date'] = pd.to_datetime(d['Date'])
print(f"Loaded: {len(d)} rows, {d['etf'].nunique()} ETFs")
# Drop duplicates (네이버 paging 중복)
n_before = len(d)
d = d.drop_duplicates(subset=['Date', 'etf'], keep='first')
print(f"  After dedup: {len(d)} rows (dropped {n_before - len(d)})")

# Pivot to wide (Date × etf)
close = d.pivot(index='Date', columns='etf', values='Close').sort_index()
print(f"Date range: {close.index.min()} ~ {close.index.max()}")

# Daily returns
ret = close.pct_change()

# Rolling returns (21-day cumulative)
def rolling_cum_ret(series, w):
    return (1 + series).rolling(w).apply(np.prod, raw=True) - 1

ret_21 = pd.DataFrame({c: rolling_cum_ret(ret[c], 21) for c in ret.columns})
ret_63 = pd.DataFrame({c: rolling_cum_ret(ret[c], 63) for c in ret.columns})

# Defensive vs Cyclical aggregation (only when both groups have data)
def_cols = [c for c in DEFENSIVE if c in ret_21.columns]
cyc_cols = [c for c in CYCLICAL if c in ret_21.columns]

def_mean_21 = ret_21[def_cols].mean(axis=1, skipna=True)
cyc_mean_21 = ret_21[cyc_cols].mean(axis=1, skipna=True)
def_mean_63 = ret_63[def_cols].mean(axis=1, skipna=True)
cyc_mean_63 = ret_63[cyc_cols].mean(axis=1, skipna=True)

features = pd.DataFrame(index=close.index)
features['sector_def_minus_cyc_21d'] = def_mean_21 - cyc_mean_21
features['sector_def_minus_cyc_63d'] = def_mean_63 - cyc_mean_63

# Dispersion (cross-section std, regime indicator)
features['sector_dispersion_21d'] = ret_21.std(axis=1, skipna=True)

# Health/IT specific (most opposite sectors)
if 'TIGER_헬스케어' in ret_21.columns and 'TIGER_200_IT' in ret_21.columns:
    features['sector_health_minus_it_21d'] = (
        ret_21['TIGER_헬스케어'] - ret_21['TIGER_200_IT']
    )
if 'KODEX_바이오' in ret_21.columns and 'KODEX_반도체' in ret_21.columns:
    features['sector_bio_minus_semi_21d'] = (
        ret_21['KODEX_바이오'] - ret_21['KODEX_반도체']
    )

# % defensive outperforming benchmark
if BENCHMARK in ret_21.columns:
    bm_21 = ret_21[BENCHMARK]
    def_outperf = pd.DataFrame({
        c: (ret_21[c] > bm_21).astype(float) for c in def_cols
    })
    features['sector_def_pct_outperf_21d'] = def_outperf.mean(axis=1, skipna=True)

# Lag1 (PIT)
features_lag = pd.DataFrame(index=features.index)
for c in features.columns:
    features_lag[f'{c}_lag1'] = features[c].shift(1)

# Reset
features_lag = features_lag.reset_index()
print(f"\n=== Sector rotation features ({len(features_lag.columns)-1} features) ===")
for c in features_lag.columns[1:]:
    v = features_lag[c].dropna()
    if len(v) > 0:
        print(f"  {c:42s} n={len(v)} range=[{v.min():+.4f}, {v.max():+.4f}] mean={v.mean():+.4f}")

# Save
features_lag.to_parquet(OUT_PATH, index=False)
print(f"\n[SAVED] {OUT_PATH}: {len(features_lag)} rows × {len(features_lag.columns)} cols")
