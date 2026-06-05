#!/usr/bin/env python3
"""
133b_us_macro_xgb_importance.py — Cycle 53H US macro feature importance sanity

Since PatchTST attention extraction is non-trivial, run XGBoost on the v5e panel
under q15 + q126 forward labels to verify Cycle 48A finding:
  - q126: us_initial_claims_4w_avg_lag1 rank 1
  - q15/q63: us_cfnai_lag1 rank 1

This is a SANITY check (XGB ≠ PatchTST architecture), but the feature importance
ranking should be consistent if US macro really is informative at q126.

Output:
  outputs/04_evaluation/patchtst_q126_usmacro_v5e_xgb_importance.json
"""
import json
import sys
from pathlib import Path
import numpy as np
import pandas as pd

try:
    import xgboost as xgb
except ImportError:
    sys.exit("xgboost not installed in venv")

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
DATA = WS / "outputs/01_data"
TGT = WS / "outputs/02_targets"
EVAL_DIR = WS / "outputs/04_evaluation"

FULL_TRAIN_START = pd.Timestamp("1995-01-01")
FULL_TRAIN_END = pd.Timestamp("2015-12-31")

US_MACRO = [
    "us_t10y2y_spread_lag1",
    "us_initial_claims_4w_avg_lag1",
    "us_cfnai_lag1",
    "us_stlfsi_lag1",
]


def fit_and_rank(target_col):
    feat = pd.read_parquet(DATA / "feature_panel_v5e_q126_usmacro.parquet")
    tgt = pd.read_parquet(TGT / "targets_long_horizon.parquet")[["Date", target_col]]
    feat["Date"] = pd.to_datetime(feat["Date"])
    tgt["Date"] = pd.to_datetime(tgt["Date"])
    panel = feat.merge(tgt, on="Date", how="left").sort_values("Date").reset_index(drop=True)

    feature_cols = [c for c in panel.columns if c not in ("Date", target_col)]
    assert len(feature_cols) == 74, f"v5e expects 74 features, got {len(feature_cols)}"

    train = panel[(panel["Date"] >= FULL_TRAIN_START) & (panel["Date"] <= FULL_TRAIN_END)].copy()
    X = train[feature_cols].astype(np.float32)
    y = train[target_col].fillna(0).astype(np.int8).values

    # Fill NaNs with column median for XGB
    col_med = X.median()
    X = X.fillna(col_med).values

    pos = int(y.sum()); neg = int((y == 0).sum())
    spw = max(neg / max(pos, 1), 1.0)

    clf = xgb.XGBClassifier(
        n_estimators=300, max_depth=4, learning_rate=0.05,
        subsample=0.8, colsample_bytree=0.6,
        scale_pos_weight=spw,
        eval_metric="aucpr", tree_method="hist", n_jobs=4,
        random_state=42, verbosity=0,
    )
    clf.fit(X, y)
    importances = clf.feature_importances_
    rank_df = pd.DataFrame({
        "feature": feature_cols,
        "importance": importances,
    }).sort_values("importance", ascending=False).reset_index(drop=True)
    rank_df["rank"] = rank_df.index + 1
    return rank_df


def main():
    results = {}
    for tgt in ["y_tail_q15", "y_tail_q126"]:
        print(f"\n========== XGB importance ({tgt}) ==========")
        rank_df = fit_and_rank(tgt)
        top30 = rank_df.head(30)
        print(top30.to_string(index=False))

        # US macro rank lookup
        us_macro_ranks = {}
        for f in US_MACRO:
            row = rank_df[rank_df["feature"] == f]
            if len(row) > 0:
                us_macro_ranks[f] = dict(
                    rank=int(row["rank"].iloc[0]),
                    importance=float(row["importance"].iloc[0]),
                    in_top_30=bool(row["rank"].iloc[0] <= 30),
                )
            else:
                us_macro_ranks[f] = dict(rank=None, importance=None, in_top_30=False)
        print(f"\n[US macro rank summary for {tgt}]")
        for f, r in us_macro_ranks.items():
            if r["importance"] is not None:
                print(f"  {f}: rank={r['rank']} importance={r['importance']:.5f} in_top30={r['in_top_30']}")
            else:
                print(f"  {f}: rank=None")

        results[tgt] = dict(
            top30_features=top30[["rank", "feature", "importance"]].to_dict(orient="records"),
            us_macro_ranks=us_macro_ranks,
            total_features=len(rank_df),
        )

    out_path = EVAL_DIR / "patchtst_q126_usmacro_v5e_xgb_importance.json"
    with out_path.open("w") as f:
        json.dump({
            "cycle": "53H_us_macro_xgb_importance_sanity",
            "method": "XGBoost feature_importances_ on full train 1995-2015 (sanity proxy for PatchTST attention)",
            "panel": "feature_panel_v5e_q126_usmacro.parquet (74 features)",
            "us_macro_features": US_MACRO,
            "results_per_target": results,
            "cycle_48a_reference": {
                "q126_xgb_rank_1": "us_initial_claims_4w_avg_lag1",
                "q126_rf_rank_1": "us_initial_claims_4w_avg_lag1",
                "q15_xgb_rank_1": "us_cfnai_lag1",
                "q63_xgb_rank_1": "us_cfnai_lag1",
            },
        }, f, indent=2, default=str)
    print(f"\n[Saved] {out_path}")


if __name__ == "__main__":
    main()
