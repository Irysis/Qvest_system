#!/usr/bin/env python3
"""226_mvp_biannual_expanding_driver.py — Cycle 58R revised (sanity first)

진정 monthly expanding은 100 retrain × 25시간이 commitment.
Sanity 먼저: bi-annual expanding (8 retrainings × 1 seed × ~15 min = 2시간).

Each retrain: train 1995 ~ {cutoff}-12-31, predict next 24 months.
8 cutoffs: 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024.
"""
import os
os.environ["CUBLAS_WORKSPACE_CONFIG"] = ":4096:8"
import sys, json, time, importlib.util
from pathlib import Path
import numpy as np
import pandas as pd
import torch

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
TEMPLATE = WS / "scripts/225_mvg_monthly_expanding_v5g.py"  # Mvp v5p fork
OUT = WS / "outputs/03_models/cycle58r_mvp_biannual_expanding"
OUT.mkdir(parents=True, exist_ok=True)

# Import 225 (Mvp v5p) as module
spec = importlib.util.spec_from_file_location("mvp_tpl", TEMPLATE)
mod = importlib.util.module_from_spec(spec)
sys.modules["mvp_tpl"] = mod
spec.loader.exec_module(mod)
print(f"[Loaded] {TEMPLATE.name}")

# Cutoffs (bi-annual sanity) — train end of each year, predict next 24 months
cutoffs = [
    (pd.Timestamp("2017-12-31"), pd.Timestamp("2018-01-01"), pd.Timestamp("2019-12-31")),
    (pd.Timestamp("2019-12-31"), pd.Timestamp("2020-01-01"), pd.Timestamp("2021-12-31")),
    (pd.Timestamp("2021-12-31"), pd.Timestamp("2022-01-01"), pd.Timestamp("2023-12-31")),
    (pd.Timestamp("2023-12-31"), pd.Timestamp("2024-01-01"), pd.Timestamp("2025-12-31")),
    (pd.Timestamp("2024-07-31"), pd.Timestamp("2024-08-01"), pd.Timestamp("2026-04-30")),
]
SEED = 42

# Load data ONCE (full range to 2026-04)
mod.OOS_END = pd.Timestamp("2026-04-30")
X_full, y_full, dates, feature_cols = mod.prepare_data_full("y_tail_q15")
print(f"[Data] X.shape={X_full.shape}")

# Configure CUDA
if torch.cuda.is_available():
    torch.cuda.set_per_process_memory_fraction(0.4, device=0)

# Bi-annual expanding loop
preds_per_window = []
metadata = []
for i, (train_end, pred_start, pred_end) in enumerate(cutoffs, 1):
    t0 = time.time()
    print(f"\n=== [{i}/{len(cutoffs)}] Train 1995-{train_end.date()}, "
          f"Predict {pred_start.date()} ~ {pred_end.date()} ===")
    # Patch globals
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
            fold_label=f"BIANNUAL_{train_end.year}",
            seed=SEED,
        )
        oop, oos_y, oos_dates = mod.predict_oos(final_model, Xs_final, dates, y_full)
        df_w = pd.DataFrame({
            "Date": oos_dates,
            "p_mvp": oop,
            "y": oos_y,
            "window_train_end": str(train_end.date()),
        })
        preds_per_window.append(df_w)
        elapsed = time.time() - t0
        from sklearn.metrics import average_precision_score
        pr_w = average_precision_score(oos_y[~np.isnan(oos_y)], oop[~np.isnan(oos_y)]) if oos_y.sum() > 0 else float('nan')
        print(f"  n_pred={len(df_w)} n_pos={int(oos_y.sum())} PR-AUC={pr_w:.4f} elapsed={elapsed:.0f}s")
        metadata.append({
            "train_end": str(train_end.date()),
            "pred_range": f"{pred_start.date()} ~ {pred_end.date()}",
            "n_pred": len(df_w),
            "n_pos": int(oos_y.sum()),
            "pr_auc": float(pr_w),
            "elapsed_sec": elapsed,
        })
        del final_model
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
    except Exception as e:
        import traceback
        traceback.print_exc()
        print(f"  ERROR: {e}")
        continue

# Save concatenated predictions (last window per date wins)
all_preds = pd.concat(preds_per_window, ignore_index=True) if preds_per_window else None
if all_preds is not None:
    # Keep most-recent train_end per Date (no duplicate dates)
    all_preds = all_preds.sort_values(["Date", "window_train_end"]).drop_duplicates("Date", keep="last")
    out_path = OUT / "predictions_mvp_biannual_expanding_seed42.parquet"
    all_preds.to_parquet(out_path, index=False)
    print(f"\n[SAVED] {out_path}: {len(all_preds)} rows")

with open(OUT / "biannual_metadata.json", "w") as f:
    json.dump(metadata, f, indent=2, default=str)

# Final
if all_preds is not None and len(all_preds) > 0:
    from sklearn.metrics import average_precision_score
    valid = all_preds["y"].notna()
    pr_overall = average_precision_score(all_preds["y"][valid], all_preds["p_mvp"][valid])
    print(f"\n[OVERALL] Bi-annual expanding PR-AUC = {pr_overall:.4f}")
    print(f"  vs single-shot Mvp on 2024-08-2026-04 = 0.094")
    print(f"  vs 2018-2024-07 Mvp single-shot ~ 0.25")
