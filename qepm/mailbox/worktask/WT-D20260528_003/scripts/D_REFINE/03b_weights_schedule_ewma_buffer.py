#!/usr/bin/env python
"""
WT-D20260528_003 Track 2 D REFINE — Step 3b: Weights Schedule with EWMA + Bandbuffer + Cooldown

Stronger sizing strategy:
  1. EWMA smoothing on predictions (α=0.5 → blend 50% prev pred)
     → ML signal fast-decay 완화 (Gu-Kelly-Xiu 2020 known issue)
  2. Bandbuffer: keep_n=50, entry_n=20
  3. Cooldown 3-month
  4. Softmax-cap 0.20 weight

Goal: turnover ≤ 6.0/yr while retaining IC ≥ 0.04.
"""

import sys
import json
import time
from pathlib import Path
from datetime import datetime

import numpy as np
import pandas as pd

PROJ = Path('/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot')
OUT_DIR = PROJ / 'stage_artifacts' / 'WT_D20260528_003_D_REFINE'

# Parameters
EWMA_ALPHA = 0.5  # 0=no smoothing, 1=full lag (prev only)
KEEP_N = 50
ENTRY_N = 20
COOLDOWN_MONTHS = 3
SOFTMAX_TAU = 1.0
WEIGHT_CAP = 0.20
MAX_NAMES = 20

sys.stdout = open(sys.stdout.fileno(), mode='w', buffering=1, encoding='utf-8', closefd=False)

t0 = time.time()
print(f"[{datetime.now().strftime('%H:%M:%S')}] D REFINE Step 3b — Weights (EWMA + Bandbuffer + Cooldown)", flush=True)
print(f"  Params: EWMA_α={EWMA_ALPHA} KEEP_N={KEEP_N} COOLDOWN={COOLDOWN_MONTHS}m", flush=True)

# Load predictions
preds = pd.read_parquet(OUT_DIR / 'predictions_walkforward.parquet')
preds['sig_date'] = pd.to_datetime(preds['sig_date'])

# Step 1: EWMA smoothing per ticker
preds = preds.sort_values(['Ticker', 'sig_date']).reset_index(drop=True)

# Per ticker EWMA: pred_smooth[t] = α * pred_smooth[t-1] + (1-α) * pred[t]
# Implementation: groupby + transform with ewm
preds['pred_smooth'] = preds.groupby('Ticker')['pred'].transform(lambda x: x.ewm(alpha=1-EWMA_ALPHA, adjust=False).mean())

print(f"  EWMA smoothing applied (α={EWMA_ALPHA} on pred → pred_smooth)")
print(f"  Pred raw  std: {preds['pred'].std():.4f}")
print(f"  Pred smth std: {preds['pred_smooth'].std():.4f}")

# Verify IC retention on EWMA predictions
from scipy.stats import spearmanr
ic_raw = []
ic_smth = []
for sd, grp in preds.groupby('sig_date'):
    if grp.shape[0] >= 20:
        ic_r, _ = spearmanr(grp['pred'].values, grp['y_zxs'].values)
        ic_s, _ = spearmanr(grp['pred_smooth'].values, grp['y_zxs'].values)
        if not np.isnan(ic_r): ic_raw.append(ic_r)
        if not np.isnan(ic_s): ic_smth.append(ic_s)

print(f"  IC raw mean : {np.mean(ic_raw):.4f}  ICIR: {np.mean(ic_raw)/(np.std(ic_raw)+1e-8):.3f}")
print(f"  IC smth mean: {np.mean(ic_smth):.4f}  ICIR: {np.mean(ic_smth)/(np.std(ic_smth)+1e-8):.3f}")

# Use pred_smooth as ranking signal
preds['pred_final'] = preds['pred_smooth']

# Build selection state machine
sig_dates_sorted = sorted(preds['sig_date'].unique())
prev_holdings = set()
cooldown_register = {}
weights_records = []

for sd in sig_dates_sorted:
    grp = preds[preds['sig_date'] == sd].copy()
    grp = grp.sort_values('pred_final', ascending=False).reset_index(drop=True)

    # Cooldown filter
    in_cooldown = set()
    for tkr, exit_sd in list(cooldown_register.items()):
        months_since = sum(1 for d in sig_dates_sorted if exit_sd < d <= sd)
        if months_since <= COOLDOWN_MONTHS:
            in_cooldown.add(tkr)
        else:
            del cooldown_register[tkr]

    avail = grp[~grp['Ticker'].isin(in_cooldown)].copy()
    top_keep = avail.head(KEEP_N).copy()
    top_keep_tickers = set(top_keep['Ticker'])

    # Bandbuffer
    retained = prev_holdings.intersection(top_keep_tickers)
    n_retained = len(retained)
    n_new_needed = MAX_NAMES - n_retained

    if n_new_needed > 0:
        new_candidates = avail[~avail['Ticker'].isin(retained)].head(MAX_NAMES * 2)
        new_entries = new_candidates.head(n_new_needed)['Ticker'].tolist()
    else:
        new_entries = []

    final_top20 = list(retained) + new_entries
    final_top20 = final_top20[:MAX_NAMES]

    final_grp = grp[grp['Ticker'].isin(final_top20)].copy()
    if final_grp.shape[0] == 0:
        continue

    final_grp = final_grp.sort_values('pred_final', ascending=False).reset_index(drop=True)
    preds_vec = final_grp['pred_final'].values

    # Softmax + cap
    pred_shifted = preds_vec - preds_vec.max()
    exp_p = np.exp(pred_shifted / SOFTMAX_TAU)
    w = exp_p / exp_p.sum()
    for _ in range(10):
        capped_mask = w > WEIGHT_CAP
        if not capped_mask.any():
            break
        excess = (w[capped_mask] - WEIGHT_CAP).sum()
        w[capped_mask] = WEIGHT_CAP
        free_mask = ~capped_mask & (w > 0)
        if free_mask.sum() > 0:
            w[free_mask] += excess * (w[free_mask] / w[free_mask].sum())
    w = w / w.sum()

    for tkr, weight, pred_v in zip(final_grp['Ticker'].values, w, preds_vec):
        weights_records.append({
            'sig_date': sd, 'Ticker': tkr, 'weight': float(weight), 'pred': float(pred_v),
        })

    cur_holdings = set(final_top20)
    exited = prev_holdings - cur_holdings
    for tkr in exited:
        cooldown_register[tkr] = sd
    prev_holdings = cur_holdings

weights_df = pd.DataFrame(weights_records)
print(f"\n  Built weights schedule: {weights_df.shape[0]} rows")

# Validate
sum_by_date = weights_df.groupby('sig_date')['weight'].sum()
n_by_date = weights_df.groupby('sig_date')['Ticker'].count()
max_w_by_date = weights_df.groupby('sig_date')['weight'].max()

print(f"  Σw per date: mean={sum_by_date.mean():.4f}")
print(f"  N names: min={n_by_date.min()} max={n_by_date.max()}")
print(f"  Weight: min={weights_df['weight'].min():.4f} max={max_w_by_date.max():.4f}")

# Turnover
dates_sorted = sorted(weights_df['sig_date'].unique())
turnover_monthly = []
prev_w = None
for d in dates_sorted:
    cur_w = weights_df[weights_df['sig_date'] == d].set_index('Ticker')['weight']
    if prev_w is not None:
        union_idx = cur_w.index.union(prev_w.index)
        cur_aligned = cur_w.reindex(union_idx, fill_value=0)
        prev_aligned = prev_w.reindex(union_idx, fill_value=0)
        tn = float((cur_aligned - prev_aligned).abs().sum())
        turnover_monthly.append(tn)
    prev_w = cur_w

monthly_2way_mean = float(np.mean(turnover_monthly))
annualized_2way = monthly_2way_mean * 12

print(f"\n  Turnover (2-way):")
print(f"    Monthly = {monthly_2way_mean:.4f}")
print(f"    Annualized = {annualized_2way:.4f}")
print(f"    6.0/yr cap: {'PASS' if annualized_2way <= 6.0 else 'FAIL'}")

# Save
weights_out = weights_df[['sig_date', 'Ticker', 'weight']].copy()
weights_out.columns = ['Date', 'Ticker', 'weight']
weights_out.to_parquet(OUT_DIR / 'weights_schedule.parquet', index=False)

turnover_summary = {
    'method': 'EWMA + Bandbuffer + Cooldown',
    'ewma_alpha': EWMA_ALPHA,
    'keep_n': KEEP_N, 'entry_n': ENTRY_N, 'cooldown_months': COOLDOWN_MONTHS,
    'softmax_tau': SOFTMAX_TAU, 'weight_cap': WEIGHT_CAP, 'max_names': MAX_NAMES,
    'n_periods': len(turnover_monthly),
    'monthly_2way_mean': monthly_2way_mean,
    'monthly_2way_median': float(np.median(turnover_monthly)),
    'monthly_2way_max': float(np.max(turnover_monthly)),
    'annualized_2way': annualized_2way,
    'hard_cap_6_0_yr_pass': bool(annualized_2way <= 6.0),
    'ic_raw_mean': float(np.mean(ic_raw)),
    'ic_smth_mean': float(np.mean(ic_smth)),
    'ic_raw_icir': float(np.mean(ic_raw)/(np.std(ic_raw)+1e-8)),
    'ic_smth_icir': float(np.mean(ic_smth)/(np.std(ic_smth)+1e-8)),
}
with open(OUT_DIR / 'turnover_summary.json', 'w') as f:
    json.dump(turnover_summary, f, indent=2)

print(f"\n=== Step 3b COMPLETE — elapsed {(time.time()-t0):.1f} sec ===")
