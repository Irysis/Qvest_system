#!/usr/bin/env python3
"""223_mvp_monthly_expanding.py — Cycle 58R Monthly Expanding Sanity

진정 expanding window: 매월 retrain (1995 ~ month-1) + predict next month.
2018-01 ~ 2026-04 = 100 monthly retrainings × 1 seed (42) sanity.
Fixed avg_best_epoch from prior CV (avg ~9 for Mamba).

GOAL: monthly rolling PR-AUC time series 측정 → regime drift 대응 효과 정량.
"""
import os
os.environ["CUBLAS_WORKSPACE_CONFIG"] = ":4096:8"

import sys
import json
import time
import importlib.util
from pathlib import Path
import numpy as np
import pandas as pd
import torch

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
TEMPLATE = WS / "scripts/217_mamba_q15_v5p_etf_yield_15seed.py"
PANEL = WS / "outputs/01_data/feature_panel_v5p_etf_yield.parquet"
OUT = WS / "outputs/03_models/cycle58r_mvp_monthly_expanding"
OUT.mkdir(parents=True, exist_ok=True)

# Load template module
spec = importlib.util.spec_from_file_location("mvp_mod", TEMPLATE)
mod = importlib.util.module_from_spec(spec)
sys.modules["mvp_mod"] = mod
spec.loader.exec_module(mod)

# Override FULL_TRAIN_END / OOS dynamically per iteration
SEED = 42
FIXED_EPOCHS = 10  # avg from prior CV (Mamba typically converges ~7-10 epochs)

# Load data ONCE — function name is prepare_data_full, takes only target_col
# Panel path is hardcoded in 217 (v5p), so we use that template
X_full, y_full, dates, feature_cols = mod.prepare_data_full("y_tail_q15")
print(f"[Data] X.shape={X_full.shape} n_dates={len(dates)}")

# Monthly loop
month_ends = pd.date_range("2018-01-31", "2026-04-30", freq="M")
print(f"[Monthly Expanding] {len(month_ends)} months from 2018-01 to 2026-04")

# Configure CUDA fraction
try:
    if torch.cuda.is_available():
        torch.cuda.set_per_process_memory_fraction(0.4, device=0)
        print(f"[CUDA] fraction = 0.4")
except Exception as e:
    print(f"[CUDA] fraction set failed: {e}")

all_preds = []
all_metadata = []

for i, m_end in enumerate(month_ends, 1):
    t_start = time.time()
    train_end_str = (m_end - pd.offsets.MonthBegin()).strftime("%Y-%m-%d")
    # Train end = month start - 1 day
    train_end_actual = m_end.replace(day=1) - pd.Timedelta(days=1)
    pred_start = m_end.replace(day=1)
    pred_end = m_end

    print(f"\n  [{i}/{len(month_ends)}] Month {m_end.strftime('%Y-%m')} "
          f"Train: 1995-01 ~ {train_end_actual.date()}, "
          f"Predict: {pred_start.date()} ~ {pred_end.date()}")

    # Train with fixed epochs
    try:
        final_model, Xs_final, _, _, _ = mod.train_one_window(
            "y_tail_q15", X_full, y_full, dates,
            train_start="1995-01-01",
            train_end=str(train_end_actual.date()),
            valid_start=None, valid_end=None,
            fixed_epochs=FIXED_EPOCHS,
            fold_label=f"MONTH_{m_end.strftime('%Y%m')}",
            seed=SEED,
        )

        # Predict subset (this month)
        # mod.predict_oos uses OOS_START/OOS_END globals — patch them
        mod.OOS_START = pd.Timestamp(pred_start)
        mod.OOS_END = pd.Timestamp(pred_end)
        oop, oos_y, oos_dates = mod.predict_oos(final_model, Xs_final,
                                                 dates, y_full)
        df_month = pd.DataFrame({
            "Date": oos_dates,
            "p_mvp_monthly": oop,
            "y": oos_y,
            "month": m_end.strftime("%Y-%m"),
        })
        all_preds.append(df_month)
        n_pred = len(df_month)
        n_pos = int(oos_y.sum())
        elapsed = time.time() - t_start
        print(f"    n_pred={n_pred} n_pos={n_pos} elapsed={elapsed:.0f}s")
        all_metadata.append({
            "month": m_end.strftime("%Y-%m"),
            "n_pred": n_pred,
            "n_pos": n_pos,
            "elapsed_sec": elapsed,
            "train_end": str(train_end_actual.date()),
        })
        # Free GPU memory
        del final_model
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
    except Exception as e:
        print(f"    ERROR: {e}")
        continue

# Save concatenated predictions
preds_all = pd.concat(all_preds, ignore_index=True)
out_path = OUT / "predictions_mvp_monthly_expanding_seed42_y_tail_q15.parquet"
preds_all.to_parquet(out_path, index=False)
print(f"\n[SAVED] {out_path}: {len(preds_all)} rows")

# Save metadata
with open(OUT / "monthly_metadata.json", "w") as f:
    json.dump(all_metadata, f, indent=2, default=str)

# Final OOS PR-AUC
from sklearn.metrics import average_precision_score
pr_overall = average_precision_score(preds_all["y"], preds_all["p_mvp_monthly"])
print(f"\n[FINAL] Monthly expanding OOS PR-AUC = {pr_overall:.4f}")
print(f"  vs prior single-shot Mvp = 0.2540")
print(f"  vs hold-out fold 4 Mvp single-shot = 0.0941")
