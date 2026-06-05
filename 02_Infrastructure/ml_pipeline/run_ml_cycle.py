"""ML cycle orchestrator — GPU + walk-forward + 5(+2 Phase1) candidates + ensemble.

Usage (Base):
    source /home/quant/qvest_ml_venv/bin/activate
    python 02_Infrastructure/ml_pipeline/run_ml_cycle.py \
        --features-master stage_artifacts/WT_D20260514_008/features_master.parquet \
        --returns-panel stage_artifacts/WT_D20260514_008/returns_monthly_panel.parquet \
        --out-dir stage_artifacts/WT_D20260514_010 \
        --train-months 60 --val-months 12 --step-months 12 --lockbox-folds 2

Phase 1.A (Uncertainty-aware, Liao 2025 RFS):
    add --enable-uncertainty [--bootstraps 50 --k-discount 1.0]
    → outputs predictions_with_ci.parquet (mean/std/p05/p25/p50/p75/p95)
    → summary_metrics.json adds confident_high_low_* per model

Phase 1.B (Cost-aware, Jensen-Kelly-Malamud-Pedersen 2022):
    add --enable-cost-aware [--gamma 0.001 --cost-bps-oneway 15]
    → adds M7_XGB_CostAware candidate
    → summary_metrics.json adds gross_sr / net_sr / cost_drag / turnover per model

Outputs:
    out-dir/predictions.parquet            — sig_date × Ticker × model × score
    out-dir/predictions_with_ci.parquet    — (when --enable-uncertainty) + std/p05~p95
    out-dir/fold_metrics.parquet           — per fold per model {ic, turnover}
    out-dir/summary_metrics.json           — overall + Phase 1 extensions
"""
import argparse
import json
from pathlib import Path
import numpy as np
import pandas as pd

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))

from walk_forward_cv import walk_forward_folds, split_train_val, fold_turnover_summary
from ml_models import (train_ridge, train_lasso, train_elastic_net,
                        train_xgboost_gpu, train_lightgbm,
                        train_xgboost_gpu_cost_aware,
                        bootstrap_predictions, uncertainty_discounted_alpha,
                        predict, predict_ensemble)
try:
    from ml_models_gpu import bootstrap_predictions_gpu
    GPU_BOOTSTRAP_AVAILABLE = True
except ImportError:
    GPU_BOOTSTRAP_AVAILABLE = False
from quality_metrics import (rank_ic_per_date, summary_stats,
                              dsr_bailey_lopez_de_prado, monotonicity_q1_q10,
                              confident_high_low_evaluation,
                              cost_adjusted_ic)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--features-master", required=True)
    parser.add_argument("--returns-panel", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--train-months", type=int, default=60)
    parser.add_argument("--val-months", type=int, default=12)
    parser.add_argument("--step-months", type=int, default=12)
    parser.add_argument("--lockbox-folds", type=int, default=2)
    parser.add_argument("--target-col", default="fwd_ret_1m")
    parser.add_argument("--date-col", default="sig_date")
    parser.add_argument("--ticker-col", default="Ticker")
    parser.add_argument("--max-features", type=int, default=None,
                        help="Optional limit for dev/test")
    # Phase 1.A — Uncertainty-aware
    parser.add_argument("--enable-uncertainty", action="store_true",
                        help="Phase 1.A: bootstrap CI (Liao 2025 RFS)")
    parser.add_argument("--bootstraps", type=int, default=50,
                        help="N bootstrap rounds for uncertainty (default 50)")
    parser.add_argument("--k-discount", type=float, default=1.0,
                        help="μ̃ = μ̂ - k·SE (default k=1.0)")
    parser.add_argument("--uncertainty-base", default="M1_Ridge",
                        help="Which candidate to bootstrap (default M1_Ridge, fast)")
    parser.add_argument("--gpu-bootstrap", action="store_true",
                        help="Phase 1.A GPU acceleration: PyTorch CUDA Ridge closed-form (178× speedup vs sklearn CPU)")
    parser.add_argument("--gpu-batch-chunk", type=int, default=5,
                        help="GPU bootstraps per memory chunk (default 5, lower if OOM)")
    parser.add_argument("--ridge-alpha", type=float, default=1.0,
                        help="Ridge regularization alpha for uncertainty bootstrap (default 1.0)")
    # Phase 1.B — Cost-aware
    parser.add_argument("--enable-cost-aware", action="store_true",
                        help="Phase 1.B: add M7_XGB_CostAware + net-of-cost stats")
    parser.add_argument("--gamma", type=float, default=0.001,
                        help="Cost penalty λ for XGB-CostAware (default 0.001)")
    parser.add_argument("--cost-bps-oneway", type=float, default=15.0,
                        help="One-way cost in bps (default 15 = KR retail)")
    parser.add_argument("--top-n", type=int, default=20,
                        help="Portfolio top-N (default 20 = Production Constraint)")
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    flags_active = []
    if args.enable_uncertainty:
        flags_active.append(f"UNCERTAINTY(B={args.bootstraps},k={args.k_discount})")
    if args.enable_cost_aware:
        flags_active.append(f"COST_AWARE(γ={args.gamma},bps={args.cost_bps_oneway})")
    if flags_active:
        print(f"[Phase 1 flags] {' | '.join(flags_active)}")

    print(f"[1/5] Load features_master + returns_panel ...", flush=True)
    features = pd.read_parquet(args.features_master)
    returns = pd.read_parquet(args.returns_panel)

    print(f"  features: {features.shape}")
    print(f"  returns:  {returns.shape}")

    if args.date_col not in features.columns and "Date" in features.columns:
        features = features.rename(columns={"Date": args.date_col})
    if args.date_col not in returns.columns and "Date" in returns.columns:
        returns = returns.rename(columns={"Date": args.date_col})

    features[args.date_col] = pd.to_datetime(features[args.date_col])
    returns[args.date_col] = pd.to_datetime(returns[args.date_col])

    panel = features.merge(returns[[args.date_col, args.ticker_col, args.target_col]],
                            on=[args.date_col, args.ticker_col], how="inner")
    print(f"  merged panel: {panel.shape}")

    feature_cols = [c for c in panel.columns
                    if c not in [args.date_col, args.ticker_col, args.target_col]
                    and pd.api.types.is_numeric_dtype(panel[c])]
    if args.max_features:
        feature_cols = feature_cols[: args.max_features]
    print(f"  feature_cols count: {len(feature_cols)}")

    print(f"\n[2/5] Walk-forward folds ...", flush=True)
    sig_dates = panel[args.date_col]
    fold_records = list(walk_forward_folds(sig_dates,
                                            train_months=args.train_months,
                                            val_months=args.val_months,
                                            step_months=args.step_months,
                                            lockbox_folds=args.lockbox_folds))
    print(f"  total folds: {len(fold_records)} (lockbox: {args.lockbox_folds})")

    all_preds = []
    all_preds_with_ci = []  # Phase 1.A
    fold_metrics = []
    panel_clean = panel.dropna(subset=[args.target_col]).copy()

    candidate_label = "5"
    if args.enable_cost_aware:
        candidate_label = "6 + Ensemble (incl. M7_XGB_CostAware)"
    else:
        candidate_label = "5 + Ensemble"
    print(f"\n[3/5] Train {candidate_label} per fold ...", flush=True)

    for (fid, ts, te, vs, ve, mode) in fold_records:
        train, val = split_train_val(panel_clean, args.date_col, ts, te, vs, ve)
        if len(train) < 1000 or len(val) < 100:
            print(f"  Fold {fid} ({mode}): skip — train {len(train)} val {len(val)}")
            continue

        X_train = train[feature_cols]
        y_train = train[args.target_col].values
        X_val = val[feature_cols]

        fitted = {
            "M1_Ridge": train_ridge(X_train, y_train, alpha=1.0),
            "M2_LASSO": train_lasso(X_train, y_train, alpha=0.005),
            "M3_EN":    train_elastic_net(X_train, y_train, alpha=0.005, l1_ratio=0.5),
            "M4_XGB_GPU": train_xgboost_gpu(X_train, y_train, n_rounds=200, max_depth=6, eta=0.05),
            "M5_LGB":   train_lightgbm(X_train, y_train, n_rounds=200, max_depth=6, lr=0.05),
        }
        if args.enable_cost_aware:
            fitted["M7_XGB_CostAware"] = train_xgboost_gpu_cost_aware(
                X_train, y_train, n_rounds=200, max_depth=6, eta=0.05,
                cost_penalty_lambda=args.gamma)

        preds = {name: predict(m, X_val) for name, m in fitted.items()}
        preds["M6_Ensemble"] = predict_ensemble(preds)

        # Phase 1.A: Bootstrap CI on a designated base model (default M1_Ridge for speed)
        if args.enable_uncertainty:
            # GPU path (Ridge only — closed-form batch) vs CPU sklearn fallback
            if args.gpu_bootstrap and GPU_BOOTSTRAP_AVAILABLE and args.uncertainty_base == "M1_Ridge":
                ci = bootstrap_predictions_gpu(X_train, y_train, X_val,
                                                  n_bootstraps=args.bootstraps,
                                                  sample_frac=0.8,
                                                  alpha=args.ridge_alpha,
                                                  random_state=42 + fid,
                                                  batch_chunk=args.gpu_batch_chunk,
                                                  device="cuda")
            else:
                base_train_fn = {
                    "M1_Ridge": lambda X, y: train_ridge(X, y, alpha=args.ridge_alpha),
                    "M2_LASSO": lambda X, y: train_lasso(X, y, alpha=0.005),
                    "M3_EN":    lambda X, y: train_elastic_net(X, y, alpha=0.005, l1_ratio=0.5),
                }.get(args.uncertainty_base, lambda X, y: train_ridge(X, y, alpha=args.ridge_alpha))

                ci = bootstrap_predictions(base_train_fn, X_train, y_train, X_val,
                                           n_bootstraps=args.bootstraps,
                                           sample_frac=0.8,
                                           random_state=42 + fid)
            ci_df = val[[args.date_col, args.ticker_col]].copy()
            ci_df["pred_mean"] = ci["mean"]
            ci_df["pred_std"]  = ci["std"]
            ci_df["pred_p05"]  = ci["p05"]
            ci_df["pred_p25"]  = ci["p25"]
            ci_df["pred_p50"]  = ci["p50"]
            ci_df["pred_p75"]  = ci["p75"]
            ci_df["pred_p95"]  = ci["p95"]
            ci_df["pred_discounted"] = uncertainty_discounted_alpha(
                ci["mean"], ci["std"], k=args.k_discount)
            ci_df["uncertainty_base"] = args.uncertainty_base
            ci_df["k_discount"] = args.k_discount
            ci_df["fold_id"] = fid
            ci_df["mode"] = mode
            all_preds_with_ci.append(ci_df)

        for name, p in preds.items():
            pred_df = val[[args.date_col, args.ticker_col]].copy()
            pred_df["score"] = p
            pred_df["model"] = name
            pred_df["fold_id"] = fid
            pred_df["mode"] = mode
            all_preds.append(pred_df)

            ret_df = val[[args.date_col, args.ticker_col, args.target_col]]
            ic_df = rank_ic_per_date(pred_df, ret_df,
                                       date_col=args.date_col,
                                       ticker_col=args.ticker_col,
                                       score_col="score",
                                       ret_col=args.target_col)
            ic_mean = ic_df["ic"].mean() if len(ic_df) else np.nan
            ic_std = ic_df["ic"].std(ddof=1) if len(ic_df) >= 2 else np.nan

            # Phase 1.B: per-fold turnover
            fold_to = {}
            if args.enable_cost_aware:
                fold_to = fold_turnover_summary(pred_df, args.date_col,
                                                 args.ticker_col, "score",
                                                 top_n=args.top_n)
            fold_metrics.append({
                "fold_id": fid, "mode": mode, "model": name,
                "train_start": ts, "train_end": te,
                "val_start": vs, "val_end": ve,
                "n_train": len(train), "n_val": len(val),
                "fold_ic_mean": ic_mean, "fold_ic_std": ic_std,
                "fold_turnover_monthly": fold_to.get("mean_turnover_monthly", np.nan),
                "fold_turnover_annualized": fold_to.get("annualized_turnover", np.nan),
            })
        print(f"  Fold {fid} ({mode}): train {len(train):>6} → val {len(val):>5} ✓", flush=True)

        # Checkpoint: save per-fold artifacts immediately (resilient against silent termination)
        ckpt_dir = out_dir / "_checkpoint"
        ckpt_dir.mkdir(exist_ok=True)
        pd.concat(all_preds, ignore_index=True).to_parquet(ckpt_dir / f"predictions_through_fold{fid}.parquet", index=False)
        if all_preds_with_ci:
            pd.concat(all_preds_with_ci, ignore_index=True).to_parquet(ckpt_dir / f"predictions_with_ci_through_fold{fid}.parquet", index=False)
        pd.DataFrame(fold_metrics).to_parquet(ckpt_dir / f"fold_metrics_through_fold{fid}.parquet", index=False)
        print(f"    ✓ Checkpoint saved: fold {fid} done", flush=True)

    print(f"\n[4/5] Aggregate predictions + summary metrics ...", flush=True)
    pred_all = pd.concat(all_preds, ignore_index=True)
    fold_m = pd.DataFrame(fold_metrics)

    summary = {}
    for model_name in pred_all["model"].unique():
        p_m = pred_all[pred_all["model"] == model_name]
        for mode_key in ["is", "lockbox", "all"]:
            sub = p_m if mode_key == "all" else p_m[p_m["mode"] == mode_key]
            if len(sub) == 0:
                continue
            ret_df = panel_clean[[args.date_col, args.ticker_col, args.target_col]]
            ic_df = rank_ic_per_date(sub, ret_df,
                                      date_col=args.date_col,
                                      ticker_col=args.ticker_col,
                                      score_col="score",
                                      ret_col=args.target_col)
            stats_dict = summary_stats(ic_df["ic"])
            mono = monotonicity_q1_q10(sub, ret_df,
                                        date_col=args.date_col,
                                        ticker_col=args.ticker_col,
                                        score_col="score",
                                        ret_col=args.target_col)
            icir = stats_dict.get("icir")
            sr_annualized = icir * np.sqrt(12) if icir and not np.isnan(icir) else np.nan
            dsr_z = dsr_bailey_lopez_de_prado(sr_annualized, stats_dict["n"], n_trials=5)
            entry = {
                **stats_dict,
                "monotonicity": mono["monotonicity"],
                "sr_annualized_proxy": sr_annualized,
                "dsr_z_n5": dsr_z,
            }

            # Phase 1.B — Cost-adjusted SR
            if args.enable_cost_aware:
                cost_stats = cost_adjusted_ic(sub, ret_df,
                                               date_col=args.date_col,
                                               ticker_col=args.ticker_col,
                                               score_col="score",
                                               ret_col=args.target_col,
                                               top_n=args.top_n,
                                               cost_bps_oneway=args.cost_bps_oneway)
                entry.update({
                    "gross_port_sr": cost_stats["gross_port_sr_annualized"],
                    "net_port_sr": cost_stats["net_port_sr_annualized"],
                    "cost_drag_pp": cost_stats["cost_drag_annualized_pp"],
                    "annualized_turnover": cost_stats["annualized_turnover"],
                })

            summary[f"{model_name}_{mode_key}"] = entry
            tail = ""
            if args.enable_cost_aware and "net_port_sr" in entry:
                tail = f" gross_sr={entry['gross_port_sr']:.3f} net_sr={entry['net_port_sr']:.3f} TO_yr={entry['annualized_turnover']:.2f}"
            print(f"  {model_name} {mode_key}: ic={stats_dict['rank_ic']:.4f} "
                  f"icir={stats_dict['icir']:.3f} t_nw={stats_dict['t_nw_lag6']:.2f} "
                  f"mono={mono['monotonicity']:.3f}{tail}")

    # Phase 1.A — Confident-High-Low evaluation
    if args.enable_uncertainty and all_preds_with_ci:
        ci_all = pd.concat(all_preds_with_ci, ignore_index=True)
        for mode_key in ["is", "lockbox", "all"]:
            sub = ci_all if mode_key == "all" else ci_all[ci_all["mode"] == mode_key]
            if len(sub) == 0:
                continue
            sub2 = sub.rename(columns={"pred_mean": "score", "pred_std": "score_std"})
            ret_df = panel_clean[[args.date_col, args.ticker_col, args.target_col]]
            chl = confident_high_low_evaluation(sub2, ret_df,
                                                  date_col=args.date_col,
                                                  ticker_col=args.ticker_col,
                                                  score_col="score",
                                                  std_col="score_std",
                                                  ret_col=args.target_col,
                                                  top_n_naive=args.top_n,
                                                  confidence_quantile=0.5)
            summary[f"ConfidentHighLow_{args.uncertainty_base}_{mode_key}"] = chl
            print(f"  ConfidentHighLow {mode_key}: naive_sr={chl['naive_sr_annualized']:.3f} "
                  f"confident_sr={chl['confident_sr_annualized']:.3f} "
                  f"Δ={chl['sr_improvement']:.3f}")

    print(f"\n[5/5] Save artifacts ...")
    pred_all.to_parquet(out_dir / "predictions.parquet", index=False)
    fold_m.to_parquet(out_dir / "fold_metrics.parquet", index=False)
    with open(out_dir / "summary_metrics.json", "w") as f:
        json.dump(summary, f, indent=2, default=str)
    print(f"  predictions.parquet: {(out_dir / 'predictions.parquet').stat().st_size / 1024:.1f} KB")
    print(f"  fold_metrics.parquet: {(out_dir / 'fold_metrics.parquet').stat().st_size / 1024:.1f} KB")
    print(f"  summary_metrics.json: {(out_dir / 'summary_metrics.json').stat().st_size / 1024:.1f} KB")

    if args.enable_uncertainty and all_preds_with_ci:
        ci_all = pd.concat(all_preds_with_ci, ignore_index=True)
        ci_all.to_parquet(out_dir / "predictions_with_ci.parquet", index=False)
        print(f"  predictions_with_ci.parquet: {(out_dir / 'predictions_with_ci.parquet').stat().st_size / 1024:.1f} KB")

    # Manifest (Phase 1 reproducibility)
    manifest = {
        "phase1_uncertainty_enabled": args.enable_uncertainty,
        "phase1_cost_aware_enabled": args.enable_cost_aware,
        "bootstraps": args.bootstraps if args.enable_uncertainty else None,
        "k_discount": args.k_discount if args.enable_uncertainty else None,
        "uncertainty_base": args.uncertainty_base if args.enable_uncertainty else None,
        "gamma": args.gamma if args.enable_cost_aware else None,
        "cost_bps_oneway": args.cost_bps_oneway if args.enable_cost_aware else None,
        "top_n": args.top_n,
        "features_master": args.features_master,
        "returns_panel": args.returns_panel,
        "n_features": len(feature_cols),
        "n_folds_total": len(fold_records),
        "lockbox_folds": args.lockbox_folds,
        "candidates": ["M1_Ridge", "M2_LASSO", "M3_EN", "M4_XGB_GPU", "M5_LGB", "M6_Ensemble"] +
                       (["M7_XGB_CostAware"] if args.enable_cost_aware else []),
    }
    with open(out_dir / "manifest.json", "w") as f:
        json.dump(manifest, f, indent=2, default=str)

    # ── FR 풀 자동 등재 (마지막 다리): ML/DPL 산출물 → register_research_outputs.R → factor-rotation 풀.
    #    freshness-gated(idempotent) — 새 산출물 있을 때만 등재. 다음 run_factor_rotation서 풀 자동 편입.
    try:
        import os as _os, subprocess as _sp, shutil as _sh
        _proj = _os.environ.get("CLAUDE_PROJECT_DIR") or _os.environ.get("QM_ROOT") or "G:/Quant_Module_Moltbot"
        _rbin = _sh.which("Rscript") or r"C:/Program Files/R/R-4.5.2/bin/Rscript.exe"
        _sp.run([_rbin, _os.path.join(_proj, "02_Infrastructure/contracts/register_research_outputs.R")], check=False)
        print("[run_ml_cycle] register_research_outputs 호출 — ML/DPL 산출물 FR 풀 등재 시도")
    except Exception as _e:
        print(f"[run_ml_cycle] FR 등재 브릿지 생략: {_e}")

    print(f"\nDONE. out_dir = {out_dir}")


if __name__ == "__main__":
    main()
