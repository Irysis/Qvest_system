#!/usr/bin/env python3
"""308_monthly_aggregate_with_options.py — Phase 1.2 monthly aggregate + options

기존 monthly_features.parquet에 KOSPI200 옵션 deep features 8건 추가.
PIT: month start prediction → 직전 영업일 (cut = m_start - 1d) 옵션 features 사용.

학술 anchor:
  - Bates 2008 implied skew
  - Bollerslev-Todorov 2011 smile curvature
  - Yan 2011 / Faff-Liu 2014 IV skew crash prediction

Output: outputs/01_data/monthly_features_v2_options.parquet
"""
from pathlib import Path
import pandas as pd
import numpy as np

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
DATA_DIR = WS / "outputs/01_data"
IN_M = DATA_DIR / "monthly_features.parquet"
IN_OPT = DATA_DIR / "kospi200_options_deep_daily.parquet"
OUT = DATA_DIR / "monthly_features_v2_options.parquet"

# Load
m = pd.read_parquet(IN_M)
m['Date'] = pd.to_datetime(m['Date'])
opt = pd.read_parquet(IN_OPT)
opt['Date'] = pd.to_datetime(opt['Date'])
opt = opt.sort_values('Date').reset_index(drop=True)
print(f"[Load] monthly: {m.shape}, options daily: {opt.shape}")

# For each month-start row in m, find the latest opt row with Date <= m.Date - 1
opt_lag1_cols = [c for c in opt.columns if c.endswith('_lag1')]
print(f"  options lag1 cols ({len(opt_lag1_cols)}): {opt_lag1_cols}")

def fetch_opt_features(m_start):
    cut = m_start - pd.Timedelta(days=1)
    past = opt[opt['Date'] <= cut]
    if len(past) == 0:
        return {f'm_start_{c}': np.nan for c in opt_lag1_cols}
    last = past.iloc[-1]
    return {f'm_start_{c}': last[c] for c in opt_lag1_cols}

# Apply
print(f"\n[Merge] adding options features to {len(m)} monthly rows...")
opt_features_rows = []
for ms in m['Date']:
    opt_features_rows.append(fetch_opt_features(ms))
opt_features_df = pd.DataFrame(opt_features_rows)
m_v2 = pd.concat([m.reset_index(drop=True), opt_features_df], axis=1)

# Stats
new_cols = [c for c in m_v2.columns if c not in m.columns]
print(f"  Added {len(new_cols)} columns:")
for c in new_cols:
    v = m_v2[c].dropna()
    if len(v) > 0:
        print(f"    {c:<45s} n={len(v):>3d} mean={v.mean():.3f} std={v.std():.3f}")
    else:
        print(f"    {c:<45s} ALL NaN")

# Save
OUT.parent.mkdir(parents=True, exist_ok=True)
m_v2.to_parquet(OUT, index=False)
print(f"\n[SAVED] {OUT}")
print(f"  {len(m_v2)} rows × {len(m_v2.columns)} cols (was {len(m.columns)})")
print(f"  y_tail_q15 positive: {int(m_v2['y_tail_q15'].sum())} / {m_v2['y_tail_q15'].notna().sum()}")
