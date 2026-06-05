#!/usr/bin/env python
"""
WT-D20260528_003 Track 2 D REFINE — Step 1: Feature Pruning to Top 30

Strategy:
  - Reuse D ML panel (ml_panel_train.parquet, 162 features)
  - Read D ML feature_importance.parquet
  - Keep top 30 features by gain importance
  - Verify decile spearman maintained (Codex C3 measured 0.7455)
  - Save pruned panel + feature list for downstream

PIT C1 retain: panel pre-filtered to sig_date <= 2023-12-22 in original Step 1.
Lockbox: same (alpha-research scope).

Output:
  stage_artifacts/WT_D20260528_003_D_REFINE/
    - ml_panel_pruned.parquet (162 -> 30 features)
    - feature_cols_top30.txt
    - pruning_summary.json
"""

import sys
import json
import time
from pathlib import Path
from datetime import datetime

import numpy as np
import pandas as pd

PROJ = Path('/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot')
SRC_DIR = PROJ / 'stage_artifacts' / 'WT_D20260528_003_overnight_D_ML'
OUT_DIR = PROJ / 'stage_artifacts' / 'WT_D20260528_003_D_REFINE'
OUT_DIR.mkdir(parents=True, exist_ok=True)

# Force unbuffered output
sys.stdout = open(sys.stdout.fileno(), mode='w', buffering=1, encoding='utf-8', closefd=False)

t0 = time.time()
print(f"[{datetime.now().strftime('%H:%M:%S')}] D REFINE Step 1 — Feature Pruning", flush=True)

# Load source panel + feature importance
panel = pd.read_parquet(SRC_DIR / 'ml_panel_train.parquet')
panel['sig_date'] = pd.to_datetime(panel['sig_date'])
print(f"  Panel: {panel.shape[0]} rows × {panel.shape[1]} cols")

fi = pd.read_parquet(SRC_DIR / 'feature_importance.parquet')
print(f"  Feature importance: {fi.shape[0]} features")

# Top 30 features (with sec_ prefix handling: keep top 30 of NON-sector features then add sector dummies)
fi_sorted = fi.sort_values('importance', ascending=False).reset_index(drop=True)

# Read original feature_cols.txt to identify non-sector features
with open(SRC_DIR / 'feature_cols.txt') as f:
    all_features = [x.strip() for x in f.readlines() if x.strip()]

print(f"  All base features (from feature_cols.txt): {len(all_features)}")

# Take top 30 from feature_importance (which were the non-sector primary features for XGBoost)
top30 = fi_sorted.head(30)['feature'].tolist()
print(f"  Selected top 30 features (by XGBoost gain importance):")
for i, feat in enumerate(top30):
    imp = fi_sorted.loc[fi_sorted['feature']==feat, 'importance'].iloc[0]
    print(f"    {i+1:2d}. {feat:<35} {imp:.5f}")

# Build pruned panel
keep_cols = ['sig_date', 'Ticker', 'log_ret_1m_w', 'Sector_Lv2'] + [c for c in top30 if c in panel.columns]
missing_top30 = [c for c in top30 if c not in panel.columns]
if missing_top30:
    print(f"  WARN: {len(missing_top30)} top30 features not in panel: {missing_top30[:5]}")

panel_pruned = panel[keep_cols].copy()
print(f"  Pruned panel: {panel_pruned.shape[0]} rows × {panel_pruned.shape[1]} cols")

# Save
panel_pruned.to_parquet(OUT_DIR / 'ml_panel_pruned.parquet', index=False)

with open(OUT_DIR / 'feature_cols_top30.txt', 'w') as f:
    for c in top30:
        f.write(c + '\n')

with open(OUT_DIR / 'pruning_summary.json', 'w') as f:
    json.dump({
        'source': str(SRC_DIR / 'ml_panel_train.parquet'),
        'feature_importance_source': str(SRC_DIR / 'feature_importance.parquet'),
        'n_features_original': len(all_features),
        'n_features_pruned': len(top30),
        'top30_features': top30,
        'top30_importance_sum_fraction': float(fi_sorted.head(30)['importance'].sum() / fi_sorted['importance'].sum()),
        'panel_rows': int(panel_pruned.shape[0]),
        'elapsed_sec': float(time.time() - t0),
    }, f, indent=2)

print(f"\n  Saved: {OUT_DIR / 'ml_panel_pruned.parquet'}")
print(f"  Top 30 captures {fi_sorted.head(30)['importance'].sum() / fi_sorted['importance'].sum() * 100:.1f}% of total importance")
print(f"=== Step 1 COMPLETE — elapsed {(time.time()-t0):.1f} sec ===")
