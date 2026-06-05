#!/usr/bin/env python3
"""191_v5g_q15_10seed_extension.py — Cycle 58F

Extend 53I_v5h_interactions q15 from 5 seeds (58B) to 15 seeds total
by training 10 NEW seeds: [2048, 3000, 5000, 7777, 9999, 10000, 20000, 30000, 40000, 50000]

Strategy:
  - Import run_one_seed + prepare_data from scripts/167b_patchtst_strict_PIT_q15_template.py
    via runpy (template SEEDS list left untouched).
  - Override SEEDS at module-level for our purposes (sub-loop).
  - Save outputs to outputs/03_models/cycle58f_v5h_15seed/
    with file naming consistent with template: predictions_53I_v5h_interactions_seed{S}_y_tail_q15.parquet
  - Also COPY the 5 existing seeds from cycle58c_v5h_5seed/ for completeness in 15seed dir.

Inputs:
  - outputs/01_data/feature_panel_v5h_cross_market_interactions.parquet (86 features)
  - outputs/02_targets/targets_long_horizon_observable.parquet

Outputs:
  - outputs/03_models/cycle58f_v5h_15seed/predictions_53I_v5h_interactions_seed{S}_y_tail_q15.parquet (15 files)
  - outputs/03_models/cycle58f_v5h_15seed/audit_53I_v5h_interactions_strict_PIT_q15.json
"""

import sys
import shutil
import time
import json
from pathlib import Path
import runpy
import importlib.util

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"

TEMPLATE = WS / "scripts/167b_patchtst_strict_PIT_q15_template.py"
PANEL = WS / "outputs/01_data/feature_panel_v5h_cross_market_interactions.parquet"
EXIST_DIR = WS / "outputs/03_models/cycle58c_v5h_5seed"  # existing 5-seed
OUT_DIR = WS / "outputs/03_models/cycle58f_v5h_15seed"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# 15 seeds total
EXISTING_SEEDS = [42, 123, 456, 789, 1024]
NEW_SEEDS = [2048, 3000, 5000, 7777, 9999, 10000, 20000, 30000, 40000, 50000]
ALL_SEEDS = EXISTING_SEEDS + NEW_SEEDS  # 15 seeds


def load_template_module():
    """Import template as a module so we can call its functions directly."""
    spec = importlib.util.spec_from_file_location("patchtst_q15_tpl", TEMPLATE)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["patchtst_q15_tpl"] = mod
    spec.loader.exec_module(mod)
    return mod


def main():
    print("=" * 70)
    print("[Cycle 58F] 53I_v5h 15-seed extension (10 NEW seeds)")
    print("=" * 70)
    print(f"Existing 5 seeds: {EXISTING_SEEDS}")
    print(f"NEW 10 seeds: {NEW_SEEDS}")
    print(f"Output dir: {OUT_DIR}")

    # ===== Step 1: Copy existing 5 seed prediction files =====
    print("\n[Step 1] Copy existing 5-seed predictions:")
    for s in EXISTING_SEEDS:
        src = EXIST_DIR / f"predictions_53I_v5h_interactions_seed{s}_y_tail_q15.parquet"
        dst = OUT_DIR / src.name
        if not src.exists():
            raise FileNotFoundError(f"Missing existing seed file: {src}")
        if not dst.exists():
            shutil.copy2(src, dst)
            print(f"  copied seed{s}: {dst.name}")
        else:
            print(f"  exists seed{s}: {dst.name} (skip copy)")

    # ===== Step 2: Train 10 NEW seeds =====
    print("\n[Step 2] Load template module + prepare data ONCE")
    mod = load_template_module()
    cycle_name = "53I_v5h_interactions"
    n_features = 91

    X_full, y_full, y_valid_mask, dates, feature_cols = mod.prepare_data(
        str(PANEL), n_features)
    print(f"[Data] X.shape={X_full.shape} y_valid_count={int(y_valid_mask.sum())}")

    # Configure CUDA fraction
    try:
        import torch
        if torch.cuda.is_available():
            torch.cuda.set_per_process_memory_fraction(0.4, device=0)
            print(f"[CUDA] fraction = 0.4")
    except Exception as e:
        print(f"[CUDA] fraction set failed: {e}")

    print("\n[Step 3] Train 10 NEW seeds sequentially (each ~5-15min)")
    cycle_start = time.time()
    new_per_seed_results = []
    for i, s in enumerate(NEW_SEEDS, 1):
        # Skip if already exists (resume)
        exist_pred = OUT_DIR / f"predictions_{cycle_name}_seed{s}_y_tail_q15.parquet"
        if exist_pred.exists():
            print(f"\n  [{i}/{len(NEW_SEEDS)}] seed={s} ALREADY EXISTS → skip training")
            # Reconstruct a minimal pseudo-result for ensemble (load file)
            import pandas as pd
            df = pd.read_parquet(exist_pred)
            # Template (167b) writes prediction column as 'p_strict' (NOT 'p_oos').
            # Verified from cycle58c_v5h_5seed/predictions_*_seed42_y_tail_q15.parquet cols
            # = ['Date', 'p_strict', 'y', 'split', 'target', 'cycle', 'seed']
            pred_col = "p_strict" if "p_strict" in df.columns else ("p_expert" if "p_expert" in df.columns else "p_oos")
            assert pred_col in df.columns, f"no known pred col in {exist_pred}"
            assert "y" in df.columns, f"missing y col in {exist_pred}"
            new_per_seed_results.append(dict(
                seed=s,
                oos_dates=df["Date"].values,
                oos_pred=df[pred_col].values,
                oos_y=df["y"].values,
                skipped_train=True
            ))
            continue
        print(f"\n  [{i}/{len(NEW_SEEDS)}] seed={s} TRAIN start")
        t0 = time.time()
        r = mod.run_one_seed(
            s, X_full, y_full, y_valid_mask, dates,
            patch_size=4, d_model=64, nhead=4, nlayers=3,
            output_dir=OUT_DIR, cycle_name=cycle_name, stride=2
        )
        elapsed = time.time() - t0
        print(f"  [{i}/{len(NEW_SEEDS)}] seed={s} DONE  elapsed={elapsed:.1f}s")
        new_per_seed_results.append(r)

    cycle_elapsed = time.time() - cycle_start
    print(f"\n[Phase 2] Total NEW seeds elapsed: {cycle_elapsed:.1f}s ({cycle_elapsed/60:.1f}min)")

    # ===== Step 4: Build 15-seed mean ensemble =====
    print("\n[Step 4] Load all 15 seed predictions + build mean15 ensemble")
    import pandas as pd
    import numpy as np

    all_preds = {}
    ref_dates = None
    ref_y = None
    for s in ALL_SEEDS:
        f = OUT_DIR / f"predictions_{cycle_name}_seed{s}_y_tail_q15.parquet"
        if not f.exists():
            raise FileNotFoundError(f"Missing seed{s} prediction: {f}")
        df = pd.read_parquet(f)
        # Template (167b) writes 'p_strict' (verified 58B cols). Robust to 'p_expert' fallback.
        date_col = "Date"
        if "p_strict" in df.columns:
            pred_col = "p_strict"
        elif "p_expert" in df.columns:
            pred_col = "p_expert"
        elif "p_oos" in df.columns:
            pred_col = "p_oos"
        else:
            raise RuntimeError(f"no known pred col in {f}; cols={list(df.columns)}")
        if "y" not in df.columns:
            raise RuntimeError(f"missing y col in {f}; cols={list(df.columns)}")
        y_col = "y"

        d = pd.to_datetime(df[date_col]).reset_index(drop=True)
        p = df[pred_col].to_numpy().astype(np.float64)
        y = df[y_col].to_numpy().astype(np.float64)
        all_preds[s] = (d, p, y)
        if ref_dates is None:
            ref_dates = d
            ref_y = y
        else:
            # Sanity check
            if not (d.values == ref_dates.values).all():
                raise RuntimeError(f"date mismatch at seed={s}")
            if not np.array_equal(y, ref_y):
                # Allow small numeric diffs in y (label encoding) — should be identical
                if not np.allclose(y, ref_y, equal_nan=False):
                    raise RuntimeError(f"y mismatch at seed={s}")

    print(f"  All 15 seeds loaded successfully.")
    print(f"  ref_dates: {ref_dates.min()} → {ref_dates.max()}  n={len(ref_dates)}")
    print(f"  n_events (sum y): {int(ref_y.sum())}")

    pred_matrix = np.stack([all_preds[s][1] for s in ALL_SEEDS], axis=0)
    mean15_pred = pred_matrix.mean(axis=0)
    per_date_std = pred_matrix.std(axis=0, ddof=0)

    # PR-AUC compute (use mod functions)
    mean15_pr = mod.pr_auc(mean15_pred, ref_y)
    mean15_ic = mod.ic_spearman(mean15_pred, ref_y)
    per_seed_pr = {s: mod.pr_auc(all_preds[s][1], ref_y) for s in ALL_SEEDS}
    per_seed_ic = {s: mod.ic_spearman(all_preds[s][1], ref_y) for s in ALL_SEEDS}

    print(f"\n[15-seed mean ensemble]")
    print(f"  PR-AUC: {mean15_pr:.4f}  IC: {mean15_ic:.4f}")
    print(f"  Per-seed mean: {np.mean(list(per_seed_pr.values())):.4f}  "
          f"std: {np.std(list(per_seed_pr.values()), ddof=1):.4f}  "
          f"range: [{min(per_seed_pr.values()):.4f}, {max(per_seed_pr.values()):.4f}]")

    # Save mean15 prediction
    df_mean15 = pd.DataFrame({
        "Date": ref_dates.values,
        "p_mean15": mean15_pred,
        "p_per_seed_std": per_date_std,
        "y": ref_y,
        "split": "oos",
        "target": "y_tail_q15",
        "cycle": cycle_name,
        "n_seeds": int(len(ALL_SEEDS)),
    })
    out_mean = OUT_DIR / f"predictions_{cycle_name}_mean15_y_tail_q15.parquet"
    df_mean15.to_parquet(out_mean, index=False)
    print(f"  Saved: {out_mean}")

    # ===== Step 5: Save 15-seed audit JSON =====
    audit = dict(
        cycle="58C_v5g_15seed",
        feature_panel=str(PANEL),
        n_features=n_features,
        n_seeds=len(ALL_SEEDS),
        seeds_used=ALL_SEEDS,
        existing_seeds_inherited=EXISTING_SEEDS,
        new_seeds_trained=NEW_SEEDS,
        per_seed_pr_auc={int(s): round(per_seed_pr[s], 6) for s in ALL_SEEDS},
        per_seed_ic={int(s): round(per_seed_ic[s], 6) for s in ALL_SEEDS},
        per_seed_pr_mean=round(float(np.mean(list(per_seed_pr.values()))), 6),
        per_seed_pr_std=round(float(np.std(list(per_seed_pr.values()), ddof=1)), 6),
        per_seed_pr_min=round(float(np.min(list(per_seed_pr.values()))), 6),
        per_seed_pr_max=round(float(np.max(list(per_seed_pr.values()))), 6),
        per_seed_pr_range=round(float(np.max(list(per_seed_pr.values())) -
                                      np.min(list(per_seed_pr.values()))), 6),
        mean15_pr_auc=round(float(mean15_pr), 6),
        mean15_ic=round(float(mean15_ic), 6),
        per_date_std_mean=round(float(per_date_std.mean()), 6),
        per_date_std_max=round(float(per_date_std.max()), 6),
        n_obs=int(len(ref_dates)),
        n_events=int(ref_y.sum()),
        strict_determinism={
            "CUBLAS_WORKSPACE_CONFIG": ":4096:8",
            "torch_use_deterministic_algorithms": True,
            "cudnn_deterministic": True,
            "cudnn_benchmark": False,
        },
        patchtst_hparams={
            "patch_size": 4, "d_model": 64,
            "nhead": 4, "nlayers": 3, "stride": 2
        },
        cycle_elapsed_sec=round(cycle_elapsed, 1),
    )
    audit_path = OUT_DIR / f"audit_{cycle_name}_strict_PIT_q15.json"
    with open(audit_path, "w") as f:
        json.dump(audit, f, indent=2, default=str)
    print(f"\n[audit] Saved: {audit_path}")

    print("\n" + "=" * 70)
    print(f"[Phase 2 DONE] 15-seed mean PR-AUC: {mean15_pr:.4f}")
    print("=" * 70)
    return audit


if __name__ == "__main__":
    main()
