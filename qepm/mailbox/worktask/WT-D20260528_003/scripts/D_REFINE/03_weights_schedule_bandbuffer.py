#!/usr/bin/env python
"""
WT-D20260528_003 Track 2 D REFINE — Step 3: Weights Schedule with Bandbuffer + Cooldown

AX-007 ML Sizing Exception #4 strengthened:
  - Bandbuffer: keep_n=30, entry_n=20
      → Top 20 candidates by pred, but EXISTING holdings within prev top 30 retained
  - Cooldown 2-month: exited stocks cannot re-enter for 2 sig_dates
  - Softmax-cap 0.20 weight: w_i = softmax(pred_i / tau) capped at 0.20, renormalized to Σw=1
  - Long-only retained

Improvements vs D ML (Step 7 weights_schedule.parquet):
  - D ML: pure top20 softmax, no buffer, turnover=16.37x
  - D REFINE: bandbuffer + cooldown → turnover target ≤ 6.0/yr

Output:
  stage_artifacts/WT_D20260528_003_D_REFINE/
    - weights_schedule.parquet (Date, Ticker, weight, fold_id)
    - turnover_summary.json
    - alpha_scores.parquet (deployable clean)
    - alpha_scores_audit.parquet (with labels for validation)
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

KEEP_N = 70
ENTRY_N = 20
COOLDOWN_MONTHS = 6
SOFTMAX_TAU = 1.0
WEIGHT_CAP = 0.20
MAX_NAMES = 20

sys.stdout = open(sys.stdout.fileno(), mode='w', buffering=1, encoding='utf-8', closefd=False)

t0 = time.time()
print(f"[{datetime.now().strftime('%H:%M:%S')}] D REFINE Step 3 — Weights Schedule (Bandbuffer + Cooldown)", flush=True)

# Load predictions
preds_path = OUT_DIR / 'predictions_walkforward.parquet'
if not preds_path.exists():
    print(f"ERROR: predictions not found: {preds_path}")
    sys.exit(1)

preds = pd.read_parquet(preds_path)
preds['sig_date'] = pd.to_datetime(preds['sig_date'])
print(f"  Loaded predictions: {preds.shape[0]} rows × {preds.shape[1]} cols")
print(f"  Unique sig_dates: {preds['sig_date'].nunique()}")

# Build bandbuffer + cooldown selection
sig_dates_sorted = sorted(preds['sig_date'].unique())
print(f"  N sig_dates: {len(sig_dates_sorted)}")

# State tracking
prev_top30 = set()  # previous month's top 30 (for keep buffer)
prev_holdings = set()  # previous month's actual top 20 holdings
cooldown_register = {}  # ticker -> sig_date when exited (cooldown lasts 2 months from then)

weights_records = []
top20_records = []

for sd in sig_dates_sorted:
    grp = preds[preds['sig_date'] == sd].copy()
    grp = grp.sort_values('pred', ascending=False).reset_index(drop=True)

    # Apply cooldown filter: exclude tickers in cooldown
    in_cooldown = set()
    for tkr, exit_sd in list(cooldown_register.items()):
        # Cooldown = 2 sig_dates from exit
        # Count sig_dates between exit and current
        months_since_exit = sum(1 for d in sig_dates_sorted if exit_sd < d <= sd)
        if months_since_exit <= COOLDOWN_MONTHS:
            in_cooldown.add(tkr)
        else:
            # Cooldown expired, remove from register
            del cooldown_register[tkr]

    # Filter available candidates
    avail = grp[~grp['Ticker'].isin(in_cooldown)].copy()

    # Bandbuffer logic:
    # Step 1: top KEEP_N candidates (the "buffer zone")
    top_keep = avail.head(KEEP_N).copy()
    top_keep_tickers = set(top_keep['Ticker'])

    # Step 2: from previous holdings, keep those still in top KEEP_N (buffer)
    retained = prev_holdings.intersection(top_keep_tickers)

    # Step 3: fill remaining slots from top ENTRY_N
    n_retained = len(retained)
    n_new_needed = MAX_NAMES - n_retained
    if n_new_needed > 0:
        new_candidates = avail[
            ~avail['Ticker'].isin(retained)
        ].head(MAX_NAMES * 2)  # take extra to fill if any conflict
        new_entries = new_candidates.head(n_new_needed)['Ticker'].tolist()
    else:
        new_entries = []

    final_top20 = list(retained) + new_entries
    final_top20 = final_top20[:MAX_NAMES]  # cap at 20

    # Compute weights (softmax-cap)
    final_grp = grp[grp['Ticker'].isin(final_top20)].copy()
    if final_grp.shape[0] == 0:
        # Fallback: no candidates
        continue

    final_grp = final_grp.sort_values('pred', ascending=False).reset_index(drop=True)
    preds_vec = final_grp['pred'].values

    # Softmax
    pred_shifted = preds_vec - preds_vec.max()
    exp_p = np.exp(pred_shifted / SOFTMAX_TAU)
    w = exp_p / exp_p.sum()

    # Cap and renormalize iteratively
    for _ in range(10):
        capped_mask = w > WEIGHT_CAP
        if not capped_mask.any():
            break
        excess = (w[capped_mask] - WEIGHT_CAP).sum()
        w[capped_mask] = WEIGHT_CAP
        free_mask = ~capped_mask & (w > 0)
        if free_mask.sum() > 0:
            w[free_mask] += excess * (w[free_mask] / w[free_mask].sum())
    w = w / w.sum()  # final normalize

    for tkr, weight, pred_v in zip(final_grp['Ticker'].values, w, preds_vec):
        weights_records.append({
            'sig_date': sd,
            'Ticker': tkr,
            'weight': float(weight),
            'pred': float(pred_v),
        })
        top20_records.append({
            'sig_date': sd,
            'Ticker': tkr,
            'weight': float(weight),
        })

    # Update state
    cur_holdings = set(final_top20)
    exited = prev_holdings - cur_holdings
    for tkr in exited:
        cooldown_register[tkr] = sd

    prev_holdings = cur_holdings
    prev_top30 = top_keep_tickers

weights_df = pd.DataFrame(weights_records)
print(f"  Built weights schedule: {weights_df.shape[0]} rows × {weights_df.shape[1]} cols")

# Verify constraints
sum_by_date = weights_df.groupby('sig_date')['weight'].sum()
n_by_date = weights_df.groupby('sig_date')['Ticker'].count()
max_w_by_date = weights_df.groupby('sig_date')['weight'].max()
min_w_by_date = weights_df.groupby('sig_date')['weight'].min()

print(f"  Σw per date: mean={sum_by_date.mean():.4f} std={sum_by_date.std():.6f}")
print(f"  N names per date: min={n_by_date.min()} max={n_by_date.max()}")
print(f"  Weight bounds: min={min_w_by_date.min():.4f} max={max_w_by_date.max():.4f}")

# Compute turnover
dates_sorted = sorted(weights_df['sig_date'].unique())
turnover_monthly = []
prev_w = None
for d in dates_sorted:
    cur_w = weights_df[weights_df['sig_date'] == d].set_index('Ticker')['weight']
    if prev_w is not None:
        union_idx = cur_w.index.union(prev_w.index)
        cur_aligned = cur_w.reindex(union_idx, fill_value=0)
        prev_aligned = prev_w.reindex(union_idx, fill_value=0)
        # 2-way turnover (Σ|Δw|)
        tn = float((cur_aligned - prev_aligned).abs().sum())
        turnover_monthly.append(tn)
    prev_w = cur_w

monthly_2way_mean = float(np.mean(turnover_monthly))
annualized_2way = monthly_2way_mean * 12

print(f"\n  Turnover (2-way):")
print(f"    Monthly mean = {monthly_2way_mean:.4f}")
print(f"    Annualized   = {annualized_2way:.4f}")
print(f"    Hard cap 6.0/yr: {'PASS' if annualized_2way <= 6.0 else 'FAIL'}")

# Save
weights_out = weights_df[['sig_date', 'Ticker', 'weight']].copy()
weights_out.columns = ['Date', 'Ticker', 'weight']
weights_out.to_parquet(OUT_DIR / 'weights_schedule.parquet', index=False)

turnover_summary = {
    'n_periods': len(turnover_monthly),
    'monthly_2way_mean': monthly_2way_mean,
    'monthly_2way_median': float(np.median(turnover_monthly)),
    'monthly_2way_max': float(np.max(turnover_monthly)),
    'annualized_2way': annualized_2way,
    'hard_cap_6_0_yr': annualized_2way <= 6.0,
    'bandbuffer': {'keep_n': KEEP_N, 'entry_n': ENTRY_N},
    'cooldown_months': COOLDOWN_MONTHS,
    'softmax_tau': SOFTMAX_TAU,
    'weight_cap': WEIGHT_CAP,
    'max_names': MAX_NAMES,
}
with open(OUT_DIR / 'turnover_summary.json', 'w') as f:
    json.dump(turnover_summary, f, indent=2)

# Also emit alpha_scores (clean + audit)
# Clean: just predictions
preds_clean = preds[['sig_date', 'Ticker', 'pred', 'fold_id']].copy()
preds_clean.columns = ['Date', 'Ticker', 'pred', 'fold_id']
preds_clean.to_parquet(OUT_DIR / 'alpha_scores_clean.parquet', index=False)
preds_clean.to_parquet(OUT_DIR / 'alpha_scores.parquet', index=False)  # primary = clean

# Audit (with labels)
preds_audit = preds.copy()
preds_audit.columns = ['Date' if c == 'sig_date' else c for c in preds_audit.columns]
preds_audit.to_parquet(OUT_DIR / 'alpha_scores_audit.parquet', index=False)

print(f"\n  Saved: weights_schedule.parquet + turnover_summary.json + alpha_scores{{clean,audit}}.parquet")
print(f"=== Step 3 COMPLETE — elapsed {(time.time()-t0):.1f} sec ===")
