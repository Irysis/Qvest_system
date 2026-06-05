#!/usr/bin/env python3
"""311_turbulence_index_daily.py — Plan Phase 2.1 Turbulence Index

학술 anchor: Kritzman-Li 2010 (FAJ) — "Skulls, Financial Turbulence, and Risk Management"
  TI_t = (r_t - μ)^T Σ^(-1) (r_t - μ)
  Multi-asset Mahalanobis distance from rolling mean (5y window).
  Chi-squared distributed (df = n_assets).

Multi-asset (6 assets):
  1. KOSPI200 return (own, BM_Close pct_change)
  2. Nikkei225 return
  3. SP500 overnight return
  4. USDKRW 5d change
  5. WTI 5d change
  6. VIX 5d change

Rolling 5y window (1260 days) for μ, Σ — PIT expanding only past data.
Features:
  - turbulence_index: scalar at t
  - turbulence_z_5y: rolling z-score (extreme percentile)
  - turbulence_rm21: 21d rolling mean (smoothed regime indicator)

PIT: 모두 lag1.

Output: outputs/01_data/turbulence_daily.parquet
"""
from pathlib import Path
import pandas as pd
import numpy as np
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
BM = PROJECT_ROOT / ".cache/benchmark.parquet"
CM = WS / "outputs/01_data/cross_market_daily.parquet"
OUT = WS / "outputs/01_data/turbulence_daily.parquet"

# Load
bm = pd.read_parquet(BM)
bm['Date'] = pd.to_datetime(bm['Date'])
bm = bm.sort_values('Date').reset_index(drop=True)
bm['kospi200_ret'] = bm['BM_Close'].pct_change()
bm = bm[['Date', 'kospi200_ret']]

cm = pd.read_parquet(CM)
cm['Date'] = pd.to_datetime(cm['Date'])
print(f"[Load] bm: {bm.shape}, cross_market: {cm.shape}")

# Merge — note cross_market is already lag1 so we need to align carefully.
# Strategy: use returns at day t directly. Since cm cols are lag1 (= t-1 value),
# we shift them back by -1 to align with day t returns.
cm_unlag = cm.copy()
unlag_cols = ['nikkei225_return', 'sp500_overnight_return', 'usdkrw_change_5d', 'wti_change_5d', 'vix_change_5d']
for c in unlag_cols:
    if f'{c}_lag1' in cm_unlag.columns:
        cm_unlag[c] = cm_unlag[f'{c}_lag1'].shift(-1)  # undo lag1

d = bm.merge(cm_unlag[['Date'] + unlag_cols], on='Date', how='left')

# Asset return matrix
asset_cols = ['kospi200_ret'] + unlag_cols
print(f"  Assets (n={len(asset_cols)}): {asset_cols}")

# Drop rows where ALL assets are NaN
d_clean = d.dropna(subset=asset_cols, how='all').reset_index(drop=True)
print(f"  Cleaned: {len(d_clean)} rows")

# Compute Turbulence Index expanding rolling 5y window
WINDOW = 1260  # ~5y of trading days
n = len(d_clean)
TI = np.full(n, np.nan)
print(f"\n[Compute] Mahalanobis Turbulence Index, expanding rolling {WINDOW}d window")
for i in range(n):
    if i % 500 == 0:
        print(f"  [{i}/{n}]", flush=True)
    if i < WINDOW: continue
    hist = d_clean.iloc[i - WINDOW:i][asset_cols].dropna(how='any')
    if len(hist) < 252: continue  # need at least 1y history
    cur = d_clean.iloc[i][asset_cols]
    if cur.isna().any(): continue
    mu = hist.mean().values
    cov = hist.cov().values
    try:
        cov_inv = np.linalg.pinv(cov)
    except Exception:
        continue
    diff = cur.values - mu
    TI[i] = float(diff @ cov_inv @ diff)

d_clean['turbulence_index'] = TI

# Rolling z-score 5y expanding (PIT)
def expanding_z(x, min_obs=252):
    n = len(x); z = np.full(n, np.nan)
    for i in range(min_obs, n):
        hist = x[:i]
        valid = hist[~np.isnan(hist)]
        if len(valid) < min_obs: continue
        mu = valid.mean(); s = valid.std()
        if s < 1e-9 or np.isnan(x[i]): continue
        z[i] = (x[i] - mu) / s
    return z

d_clean['turbulence_z_5y'] = expanding_z(d_clean['turbulence_index'].values)
# 21d rolling mean (smoothed regime indicator)
d_clean['turbulence_rm21'] = pd.Series(d_clean['turbulence_index'].values).rolling(21, min_periods=5).mean().values

# lag1 (PIT)
for c in ['turbulence_index', 'turbulence_z_5y', 'turbulence_rm21']:
    d_clean[f'{c}_lag1'] = d_clean[c].shift(1)

# Stats
print(f"\n[Built] {len(d_clean)} rows × {len(d_clean.columns)} cols")
for c in ['turbulence_index_lag1', 'turbulence_z_5y_lag1', 'turbulence_rm21_lag1']:
    v = d_clean[c].dropna()
    if len(v) > 0:
        print(f"  {c:<30s} n={len(v)} mean={v.mean():.3f} std={v.std():.3f} range=[{v.min():.3f}, {v.max():.3f}]")

# Save (Date + lag1 only)
out = d_clean[['Date', 'turbulence_index_lag1', 'turbulence_z_5y_lag1', 'turbulence_rm21_lag1']]
OUT.parent.mkdir(parents=True, exist_ok=True)
out.to_parquet(OUT, index=False)
print(f"\n[SAVED] {OUT} — {len(out)} rows × {len(out.columns)} cols")
