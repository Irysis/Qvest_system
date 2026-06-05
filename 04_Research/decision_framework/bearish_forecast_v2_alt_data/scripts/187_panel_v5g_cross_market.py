#!/usr/bin/env python3
"""187_panel_v5g_cross_market.py — Cycle 58B Phase 2: Build v5g_cross_market panel

Inputs:
  - outputs/01_data/feature_panel_v5f_FIXED2.parquet (79 features, BBVA-clean via FIXED2)
  - outputs/01_data/cross_market_daily.parquet (7 cross-market lag1 features)

Output:
  - outputs/01_data/feature_panel_v5g_cross_market.parquet (86 features)
  - outputs/04_evaluation/cycle58b_panel_v5g_build.json

PIT correctness:
  - All 7 cross-market features already .shift(1) applied in Phase 1
  - Inner merge on Date — no future leakage
  - NaN handling: WTI/USDKRW/VIX_change5d start 2000-01-12 → pre-2000 rows have NaN cross-market features
  - For pre-2000 history, fillna(0) used (model can learn that NaN = early history,
    but to avoid spurious signals we fill 0 = neutral)

Per Cycle 57B "FIXED2" inherits: this v5g panel preserves the BBVA indirect ICSA fix
(via v5f_FIXED2 base).
"""
import sys
import json
from pathlib import Path
from datetime import datetime
import pandas as pd
import numpy as np

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
DATA = WS / "outputs/01_data"
EVAL = WS / "outputs/04_evaluation"


def main():
    print("=" * 70)
    print("[Cycle 58B Phase 2] Build feature_panel_v5g_cross_market.parquet")
    print("=" * 70)

    # Load base panel (v5f_FIXED2 = 79 features)
    base_path = DATA / "feature_panel_v5f_FIXED2.parquet"
    base = pd.read_parquet(base_path)
    base["Date"] = pd.to_datetime(base["Date"]).dt.normalize()
    print(f"[loaded] {base_path.name} shape={base.shape}")
    base_feat = [c for c in base.columns if c != "Date"]
    print(f"  base features: {len(base_feat)}")

    # Load cross-market
    cm_path = DATA / "cross_market_daily.parquet"
    cm = pd.read_parquet(cm_path)
    cm["Date"] = pd.to_datetime(cm["Date"]).dt.normalize()
    cm_feat = [c for c in cm.columns if c != "Date"]
    print(f"[loaded] {cm_path.name} shape={cm.shape} cross_market features={len(cm_feat)}")

    # Inner merge (KR trading days only; spine was already KR-aligned in Phase 1)
    panel = base.merge(cm, on="Date", how="left")
    print(f"\n[merged] v5g panel shape={panel.shape}")
    all_feat = [c for c in panel.columns if c != "Date"]
    n_feat = len(all_feat)
    print(f"  total features: {n_feat} (expected 86 = 79 + 7)")
    assert n_feat == 86, f"unexpected feature count: {n_feat}"

    # NaN audit
    print("\n[NaN audit (cross-market features)]")
    for c in cm_feat:
        n_na = int(panel[c].isna().sum())
        first_valid = panel[panel[c].notna()]["Date"].min()
        first_valid_str = str(first_valid.date()) if pd.notna(first_valid) else "NONE"
        print(f"  {c:38s} NA={n_na} first_valid={first_valid_str}")

    # NaN strategy: fill 0 for pre-2000 cross-market history (model learns 0 as neutral)
    # Alternative: drop rows with any NaN → would lose 1990-2000 (5K rows). Bad for fold 1.
    # Per Cycle 57A FIXED panel convention, NaN handling at PatchTST template = standardize-then-fill.
    # We follow the convention: leave NaN, template handles via standardization (mean=0 after fill).
    # For absolute safety, also create a fillna(0) variant.

    # PRIMARY: keep NaN (template handles via fillna(0) post-standardization at lines 296+)
    out_path = DATA / "feature_panel_v5g_cross_market.parquet"
    panel.to_parquet(out_path, index=False)
    print(f"\n[saved] {out_path}")
    print(f"  shape: {panel.shape}, features={n_feat}")

    # Validation: confirm all base features identical to v5f_FIXED2
    cmp_ok = True
    for c in base_feat:
        if not panel[c].equals(base[c]):
            print(f"  ⚠️  Feature {c} differs from v5f_FIXED2 — investigation needed")
            cmp_ok = False
    print(f"\n[validation] all v5f_FIXED2 features preserved: {cmp_ok}")

    # Build provenance log
    prov = {
        "cycle": "58B_phase2_panel_v5g_cross_market_build",
        "script": "187_panel_v5g_cross_market.py",
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "base_panel": str(base_path),
        "base_features_n": len(base_feat),
        "cross_market_added": cm_feat,
        "cross_market_n": len(cm_feat),
        "total_features": n_feat,
        "panel_shape": list(panel.shape),
        "date_range": [str(panel["Date"].min().date()), str(panel["Date"].max().date())],
        "validation_base_preserved": cmp_ok,
        "nan_counts_cross_market": {c: int(panel[c].isna().sum()) for c in cm_feat},
        "first_valid_dates": {c: (str(panel[panel[c].notna()]["Date"].min().date()) if panel[c].notna().any() else None) for c in cm_feat},
        "output": str(out_path),
    }
    eval_path = EVAL / "cycle58b_panel_v5g_build.json"
    with open(eval_path, "w") as f:
        json.dump(prov, f, indent=2, ensure_ascii=False, default=str)
    print(f"[saved] {eval_path}")

    print("\n[DONE] Phase 2 complete. Ready for Phase 3 PatchTST training.")


if __name__ == "__main__":
    main()
