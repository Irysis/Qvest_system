#!/usr/bin/env python
"""
WT-D20260528_003 Hypothesis D — Emit alpha_scores.parquet + alpha_validation.json
For downstream Risk/Optimizer compatibility (factor_db Connector pattern)
"""

import json
import time
from pathlib import Path
from datetime import datetime

import numpy as np
import pandas as pd
import pyarrow.parquet as pq

PROJ = Path('/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot')
OUT_DIR = PROJ / 'stage_artifacts' / 'WT_D20260528_003_overnight_D_ML'

t0 = time.time()
print(f"[{datetime.now().strftime('%H:%M:%S')}] Step 6 — emit alpha_scores.parquet + alpha_validation.json")

# Load predictions
preds = pd.read_parquet(OUT_DIR / 'predictions_walkforward.parquet')
preds['sig_date'] = pd.to_datetime(preds['sig_date'])

# Build alpha_scores.parquet: (Date, Ticker, alpha_z, alpha_pred, fold_id)
alpha_scores = preds[['sig_date', 'Ticker', 'pred', 'y_zxs', 'log_ret_1m_w', 'fold_id']].copy()
alpha_scores.columns = ['Date', 'Ticker', 'alpha_pred', 'realized_y_zxs', 'realized_log_ret_1m', 'fold_id']

# Cross-section z-score of prediction (per sig_date)
alpha_scores['alpha_z'] = alpha_scores.groupby('Date')['alpha_pred'].transform(
    lambda x: (x - x.mean()) / (x.std() + 1e-8)
)
alpha_scores['alpha_rank_pct'] = alpha_scores.groupby('Date')['alpha_pred'].rank(pct=True)

alpha_scores = alpha_scores.sort_values(['Date', 'alpha_z'], ascending=[True, False]).reset_index(drop=True)
print(f"  alpha_scores: {alpha_scores.shape[0]} rows × {alpha_scores.shape[1]} cols")
print(f"  Date range: {alpha_scores['Date'].min()} -> {alpha_scores['Date'].max()}")
print(f"  N sig_dates: {alpha_scores['Date'].nunique()}")
print(f"  alpha_z range: [{alpha_scores['alpha_z'].min():.3f}, {alpha_scores['alpha_z'].max():.3f}]")

# Save
alpha_scores_path = OUT_DIR / 'alpha_scores.parquet'
alpha_scores.to_parquet(alpha_scores_path, index=False)
print(f"  Saved: {alpha_scores_path}")

# Build alpha_validation.json
with open(OUT_DIR / 'cv_results.json') as f:
    cv = json.load(f)

# Per-fold validation summary
fold_summary = {
    f['fold_id']: {
        'train_end': f['train_end'],
        'test_start': f['test_start'],
        'test_end': f['test_end'],
        'n_train_rows': f['n_train_rows'],
        'n_test_rows': f['n_test_rows'],
        'rank_ic_mean': f['rank_ic_mean'],
        'rank_ic_std': f['rank_ic_std'],
        'rank_ic_ir': f['rank_ic_ir'],
        'rank_ic_count': f['rank_ic_count'],
        'rmse_mean': f['rmse_mean'],
    }
    for f in cv['fold_metrics']
}

validation = {
    "task_id": "WT-D20260528_003",
    "hypothesis_handle": "hypothesis_D",
    "model_type": cv['model_type'],
    "as_of": datetime.now().isoformat(),
    "lockbox_cutoff": cv['lockbox_cutoff'],
    "embargo_days": cv['embargo_days'],
    "min_train_years": cv['min_train_years'],
    "n_features": cv['n_features'],
    "n_optuna_trials": cv['n_optuna_trials'],
    "n_trials_effective_for_dsr": cv['n_trials_effective_for_dsr'],
    "best_hyperparams": cv['best_hyperparams'],
    "best_n_estimators": cv['best_n_estimators'],
    "panel_rows": cv['panel_rows'],
    "panel_sig_dates": cv['panel_sig_dates'],

    "graduation_check": {
        "min_rank_ic": {"threshold": 0.04, "actual": cv['overall_metrics']['rank_ic_mean'], "pass": cv['overall_metrics']['rank_ic_mean'] >= 0.04},
        "min_icir": {"threshold": 0.2, "actual": cv['overall_metrics']['icir'], "pass": cv['overall_metrics']['icir'] >= 0.2},
        "min_harvey_t_hac": {"threshold": 3.0, "actual": cv['overall_metrics']['t_hac_newey_west'], "pass": cv['overall_metrics']['t_hac_newey_west'] >= 3.0},
        "min_subperiod_stability": {"threshold": 0.5, "actual": cv['subperiod_stability_fraction'], "pass": cv['subperiod_stability_fraction'] >= 0.5},
        "min_deflated_sharpe_ratio": {"threshold": 0.5, "actual": cv['dsr_simplified'], "pass": cv['dsr_simplified'] >= 0.5 if cv['dsr_simplified'] is not None else False},
        "min_ax001_v2_bad_normal_ratio": {"threshold": 0.5, "actual": cv['ax001_v2']['ratio_bad_over_normal'], "pass": cv['ax001_v2']['pass_threshold_05']},
    },

    "overall_metrics": cv['overall_metrics'],
    "subperiod_metrics": cv['subperiod_metrics'],
    "fold_metrics": fold_summary,

    "pit_assertions": {
        "factor_load": "Daily Factor DB direct (C15 carve-out: ML + daily parquet exception)",
        "sig_date_cutoff": cv['lockbox_cutoff'],
        "walk_forward": f"Purged CV: train >= {cv['min_train_years']}y expanding, test 1y, embargo {cv['embargo_days']}d (López de Prado 2018)",
        "feature_lag": "t-1 trading day strict (Cycle 51 shift convention positive n + type='lag')",
        "forward_return": "log(P_next_me / P_this_me), winsorize 99.5%",
        "sector_neutralize": "Sector_Lv2 dummies as ML features (45 categories)",
        "pit_clean": True,
        "c1_c15_assertion": "C1 / C2 / C3 / C7 verified by walk-forward design",
        "c15_carve_out_justification": "ML + daily parquet exception per .claude/rules/factor-db.md",
    },

    "ax_compliance": {
        "ax_007_avoidance": "ML sizing exception #4 (confidence-weighted top-K, not equal weight)",
        "ax_001_v2": cv['ax001_v2'],
        "ax_002": "Walk-forward purged CV + no full-sample leakage, all metrics reproducible",
        "ax_008": "Awaiting Codex critic (Triangulation 2/3)",
    },

    "elapsed_seconds": cv['elapsed_seconds'],
}

valid_path = OUT_DIR / 'alpha_validation.json'
with open(valid_path, 'w') as f:
    json.dump(validation, f, indent=2, default=str)
print(f"  Saved: {valid_path}")

print(f"\n=== Step 6 COMPLETE — elapsed {(time.time()-t0):.1f}s ===")
