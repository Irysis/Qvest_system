#!/usr/bin/env python3
"""
137b_ecos_xgb_importance.py — Cycle 53I ECOS KR macro feature importance sanity

Run XGBoost on v5f panel (79 features) under q15 + q126 forward labels.
Verify whether ECOS KR macro features rank in top-30, compare with:
  - Cycle 48A: us_initial_claims rank 1 (q126), us_cfnai rank 1 (q15/q63)
  - Cycle 53H 133b reproduction: same ranks reproduce in v5e
  - This 137b: do ECOS features show up in top-30, and vs BBVA composite ranks?

Output:
  outputs/04_evaluation/patchtst_q126_v5f_ecos_xgb_importance.json
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

ECOS_KR_MACRO = [
    "ecos_m2_yoy_lag1",
    "ecos_krw_usd_change_5d_lag1",
    "ecos_base_rate_lag1",
    "ecos_industrial_production_yoy_lag1",
    "ecos_cpi_yoy_lag1",
]

US_MACRO = [
    "us_t10y2y_spread_lag1",
    "us_initial_claims_4w_avg_lag1",
    "us_cfnai_lag1",
    "us_stlfsi_lag1",
]


def fit_and_rank(target_col):
    feat = pd.read_parquet(DATA / "feature_panel_v5f_ecos_kr.parquet")
    tgt = pd.read_parquet(TGT / "targets_long_horizon.parquet")[["Date", target_col]]
    feat["Date"] = pd.to_datetime(feat["Date"])
    tgt["Date"] = pd.to_datetime(tgt["Date"])
    panel = feat.merge(tgt, on="Date", how="left").sort_values("Date").reset_index(drop=True)

    feature_cols = [c for c in panel.columns if c not in ("Date", target_col)]
    assert len(feature_cols) == 79, f"v5f expects 79 features, got {len(feature_cols)}"

    train = panel[(panel["Date"] >= FULL_TRAIN_START) & (panel["Date"] <= FULL_TRAIN_END)].copy()
    X = train[feature_cols].astype(np.float32)
    y = train[target_col].fillna(0).astype(np.int8).values

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


def lookup_features(rank_df, features, label):
    """Return rank/importance summary for a feature group."""
    out = {}
    for f in features:
        row = rank_df[rank_df["feature"] == f]
        if len(row) > 0:
            out[f] = dict(
                rank=int(row["rank"].iloc[0]),
                importance=float(row["importance"].iloc[0]),
                in_top_30=bool(row["rank"].iloc[0] <= 30),
            )
        else:
            out[f] = dict(rank=None, importance=None, in_top_30=False)
    return out


def main():
    results = {}
    for tgt in ["y_tail_q15", "y_tail_q126"]:
        print(f"\n========== XGB importance ({tgt}) ==========")
        rank_df = fit_and_rank(tgt)
        top30 = rank_df.head(30)
        print("Top-30 features:")
        print(top30.to_string(index=False))

        ecos_ranks = lookup_features(rank_df, ECOS_KR_MACRO, "ECOS_KR_MACRO")
        us_ranks = lookup_features(rank_df, US_MACRO, "US_MACRO")
        bbva_features = [c for c in rank_df["feature"] if c.startswith("bbva_")]
        bbva_ranks_top10 = {f: int(rank_df[rank_df["feature"]==f]["rank"].iloc[0])
                            for f in bbva_features
                            if rank_df[rank_df["feature"]==f]["rank"].iloc[0] <= 10}

        print(f"\n[ECOS KR macro rank summary for {tgt}]")
        for f, r in ecos_ranks.items():
            if r["importance"] is not None:
                print(f"  {f}: rank={r['rank']:>3d} importance={r['importance']:.5f} in_top30={r['in_top_30']}")
            else:
                print(f"  {f}: rank=None")

        print(f"\n[US macro rank summary for {tgt}]")
        for f, r in us_ranks.items():
            if r["importance"] is not None:
                print(f"  {f}: rank={r['rank']:>3d} importance={r['importance']:.5f} in_top30={r['in_top_30']}")
            else:
                print(f"  {f}: rank=None")

        print(f"\n[BBVA composite features in top-10 for {tgt}] {len(bbva_ranks_top10)}")
        for f, r in sorted(bbva_ranks_top10.items(), key=lambda x: x[1]):
            print(f"  {f}: rank={r}")

        results[tgt] = dict(
            top30_features=top30[["rank", "feature", "importance"]].to_dict(orient="records"),
            ecos_kr_macro_ranks=ecos_ranks,
            us_macro_ranks=us_ranks,
            bbva_composite_top10=bbva_ranks_top10,
            total_features=len(rank_df),
        )

    out_path = EVAL_DIR / "patchtst_q126_v5f_ecos_xgb_importance.json"
    with out_path.open("w") as f:
        json.dump({
            "cycle": "53I_ecos_kr_macro_xgb_importance_sanity",
            "method": "XGBoost feature_importances_ on full train 1995-2015 (sanity proxy for PatchTST attention)",
            "panel": "feature_panel_v5f_ecos_kr.parquet (79 features)",
            "ecos_kr_macro_features": ECOS_KR_MACRO,
            "us_macro_features": US_MACRO,
            "results_per_target": results,
            "cycle_48a_reference": {
                "q126_xgb_rank_1": "us_initial_claims_4w_avg_lag1",
                "q15_xgb_rank_1": "us_cfnai_lag1",
            },
        }, f, indent=2, default=str)
    print(f"\n[Saved] {out_path}")


if __name__ == "__main__":
    main()
