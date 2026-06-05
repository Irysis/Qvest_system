#!/usr/bin/env python3
"""227_mvp_monthly_expanding_driver.py — Cycle 58R Monthly (도훈 mandate)

진정 monthly expanding: 100 monthly windows × 1 seed × ~17 sec each ≈ 30 min.
Each iter: train 1995 ~ {month_start - 1day}, predict that month.
2018-01 ~ 2026-04 = ~100 monthly retrainings.

Result: 진정 concept-drift-adaptive Mvp predictions for full 2018-2026.
"""
import os
os.environ["CUBLAS_WORKSPACE_CONFIG"] = ":4096:8"
import sys, json, time, importlib.util
from pathlib import Path
import numpy as np
import pandas as pd
import torch
from sklearn.metrics import average_precision_score

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
TEMPLATE = WS / "scripts/225_mvg_monthly_expanding_v5g.py"  # v5p Mvp fork
OUT = WS / "outputs/03_models/cycle58r_mvp_monthly_expanding"
OUT.mkdir(parents=True, exist_ok=True)

# Import 225 (Mvp v5p) as module
spec = importlib.util.spec_from_file_location("mvp_tpl", TEMPLATE)
mod = importlib.util.module_from_spec(spec)
sys.modules["mvp_tpl"] = mod
spec.loader.exec_module(mod)
print(f"[Loaded] {TEMPLATE.name}")

# 100 monthly cutoffs: predict 2018-01 ~ 2026-04
month_starts = pd.date_range("2018-01-01", "2026-04-01", freq="MS")
cutoffs = [(ms - pd.Timedelta(days=1), ms, ms + pd.offsets.MonthEnd(0))
           for ms in month_starts]
SEED = 42
print(f"[Monthly] {len(cutoffs)} windows")

# Load data ONCE
mod.OOS_END = pd.Timestamp("2026-04-30")
X_full, y_full, dates, feature_cols = mod.prepare_data_full("y_tail_q15")
print(f"[Data] X.shape={X_full.shape}")

if torch.cuda.is_available():
    torch.cuda.set_per_process_memory_fraction(0.4, device=0)

preds_per_window = []
metadata = []
overall_t0 = time.time()
for i, (train_end, pred_start, pred_end) in enumerate(cutoffs, 1):
    t0 = time.time()
    mod.FULL_TRAIN_END = train_end
    mod.OOS_START = pred_start
    mod.OOS_END = pred_end
    try:
        final_model, Xs_final, _, _, _ = mod.train_one_window(
            "y_tail_q15", X_full, y_full, dates,
            train_start=str(mod.FULL_TRAIN_START.date()),
            train_end=str(train_end.date()),
            valid_start=None, valid_end=None,
            fixed_epochs=10,
            fold_label=f"MONTH_{pred_start.strftime('%Y%m')}",
            seed=SEED,
        )
        oop, oos_y, oos_dates = mod.predict_oos(final_model, Xs_final, dates, y_full)
        df_w = pd.DataFrame({
            "Date": oos_dates,
            "p_mvp": oop,
            "y": oos_y,
            "month": pred_start.strftime("%Y-%m"),
            "train_end": str(train_end.date()),
        })
        preds_per_window.append(df_w)
        elapsed = time.time() - t0
        if i % 10 == 0 or i == 1 or i == len(cutoffs):
            print(f"  [{i}/{len(cutoffs)}] {pred_start.strftime('%Y-%m')}: "
                  f"n={len(df_w)} pos={int(oos_y.sum())} elapsed={elapsed:.0f}s")
        del final_model
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
    except Exception as e:
        print(f"  [{i}] {pred_start.strftime('%Y-%m')} ERROR: {e}")
        continue

overall_elapsed = time.time() - overall_t0
print(f"\n[DONE] Total elapsed: {overall_elapsed:.0f}s ({overall_elapsed/60:.1f}min)")

# Save + aggregate
all_preds = pd.concat(preds_per_window, ignore_index=True)
all_preds = all_preds.sort_values(["Date", "train_end"]).drop_duplicates("Date", keep="last")
out_path = OUT / "predictions_mvp_monthly_expanding_seed42.parquet"
all_preds.to_parquet(out_path, index=False)
print(f"[SAVED] {out_path}: {len(all_preds)} rows")

# Final PR-AUC
valid = all_preds["y"].notna()
pr_overall = average_precision_score(all_preds["y"][valid], all_preds["p_mvp"][valid])
# Window-별
print(f"\n[OVERALL] Monthly expanding 2018-2026: PR-AUC = {pr_overall:.4f}")
# vs single-shot
print(f"  vs single-shot Mvp 2018-2026 = 0.2540")
print(f"  vs bi-annual expanding overall = 0.1985")
print(f"  vs 58Q single-shift hold-out (2024-08+) = 0.1148")

# Last hold-out period only
hold_out_mask = (pd.to_datetime(all_preds["Date"]) >= pd.Timestamp("2024-08-12"))
ho = all_preds[hold_out_mask]
ho_valid = ho["y"].notna()
if ho_valid.sum() > 5:
    pr_ho = average_precision_score(ho["y"][ho_valid], ho["p_mvp"][ho_valid])
    print(f"\n[HOLD-OUT 2024-08-2026-04]: PR-AUC = {pr_ho:.4f}  (vs single-shot 0.094)")
