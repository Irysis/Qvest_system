#!/usr/bin/env python3
"""229_mvp_rolling10y_monthly_driver.py — Cycle 58U (도훈 mandate Rolling 10y monthly)

진정 Rolling window monthly retrain:
  Each iter: train = (month_start - 10y) to (month_start - 1d), predict = month.
  100 monthly windows × 1 seed × ~17 sec = ~30 min.

vs 58R Expanding (fixed start 1995):
  Rolling 10y → recent regime focus + concept drift adaptive (도훈 audit instinct).
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
TEMPLATE = WS / "scripts/225_mvg_monthly_expanding_v5g.py"  # Mvp v5p fork
OUT = WS / "outputs/03_models/cycle58v_mvp_rolling10y_PURGED"
OUT.mkdir(parents=True, exist_ok=True)

# Import 225 (Mvp v5p) as module
spec = importlib.util.spec_from_file_location("mvp_tpl", TEMPLATE)
mod = importlib.util.module_from_spec(spec)
sys.modules["mvp_tpl"] = mod
spec.loader.exec_module(mod)

month_starts = pd.date_range("2018-01-01", "2026-04-01", freq="MS")
SEED = 42
ROLLING_YEARS = 10
print(f"[Rolling 10y Monthly] {len(month_starts)} windows, seed={SEED}")

mod.OOS_END = pd.Timestamp("2026-04-30")
X_full, y_full, dates, feature_cols = mod.prepare_data_full("y_tail_q15")
print(f"[Data] X.shape={X_full.shape}")

if torch.cuda.is_available():
    torch.cuda.set_per_process_memory_fraction(0.4, device=0)

preds_per_window = []
metadata = []
overall_t0 = time.time()
for i, ms in enumerate(month_starts, 1):
    t0 = time.time()
    train_end = ms - pd.Timedelta(days=22)
    train_start = ms - pd.DateOffset(years=ROLLING_YEARS)  # 10y rolling
    pred_start = ms
    pred_end = ms + pd.offsets.MonthEnd(0)
    mod.FULL_TRAIN_START = train_start
    mod.FULL_TRAIN_END = train_end
    mod.OOS_START = pred_start
    mod.OOS_END = pred_end
    try:
        final_model, Xs_final, _, _, _ = mod.train_one_window(
            "y_tail_q15", X_full, y_full, dates,
            train_start=str(train_start.date()),
            train_end=str(train_end.date()),
            valid_start=None, valid_end=None,
            fixed_epochs=10,
            fold_label=f"MONTH_{ms.strftime('%Y%m')}",
            seed=SEED,
        )
        oop, oos_y, oos_dates = mod.predict_oos(final_model, Xs_final, dates, y_full)
        df_w = pd.DataFrame({
            "Date": oos_dates,
            "p_mvp": oop,
            "y": oos_y,
            "month": ms.strftime("%Y-%m"),
            "train_start": str(train_start.date()),
            "train_end": str(train_end.date()),
        })
        preds_per_window.append(df_w)
        elapsed = time.time() - t0
        if i % 10 == 0 or i == 1 or i == len(month_starts):
            print(f"  [{i}/{len(month_starts)}] {ms.strftime('%Y-%m')}: "
                  f"train {train_start.date()} ~ {train_end.date()} "
                  f"n={len(df_w)} pos={int(oos_y.sum())} elapsed={elapsed:.0f}s")
        del final_model
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
    except Exception as e:
        import traceback
        traceback.print_exc()
        continue

overall = time.time() - overall_t0
print(f"\n[DONE] Total: {overall:.0f}s ({overall/60:.1f}min)")

all_preds = pd.concat(preds_per_window, ignore_index=True)
all_preds = all_preds.sort_values(["Date","train_end"]).drop_duplicates("Date", keep="last")
out_path = OUT / "predictions_mvp_rolling10y_monthly_seed42.parquet"
all_preds.to_parquet(out_path, index=False)
print(f"[SAVED] {out_path}: {len(all_preds)} rows")

valid = all_preds["y"].notna()
pr_overall = average_precision_score(all_preds["y"][valid], all_preds["p_mvp"][valid])
print(f"\n[OVERALL Rolling 10y monthly] 2018-2026 daily-level PR-AUC = {pr_overall:.4f}")
print(f"  vs 58R Expanding monthly = 0.2431")
print(f"  vs single-shot fixed = 0.2540")

# Hold-out
hold_mask = pd.to_datetime(all_preds["Date"]) >= pd.Timestamp("2024-08-12")
ho = all_preds[hold_mask]
ho_valid = ho["y"].notna()
if ho_valid.sum() > 5:
    pr_ho = average_precision_score(ho["y"][ho_valid], ho["p_mvp"][ho_valid])
    print(f"\n[HOLD-OUT 2024-08-2026-04] daily-level PR-AUC = {pr_ho:.4f}")
    print(f"  vs 58R Expanding hold-out = 0.1004")
    print(f"  vs single-shot fixed hold-out = 0.0941")

# Monthly granularity
all_preds['Date'] = pd.to_datetime(all_preds['Date'])
all_preds['year_month'] = all_preds['Date'].dt.to_period('M')
monthly = all_preds.groupby('year_month').first().reset_index()
monthly_valid = monthly['y'].notna()
pr_monthly = average_precision_score(monthly['y'][monthly_valid], monthly['p_mvp'][monthly_valid])
print(f"\n[MONTHLY granularity] n={monthly_valid.sum()} months, "
      f"base={monthly['y'][monthly_valid].mean()*100:.1f}%, PR-AUC={pr_monthly:.4f}")
