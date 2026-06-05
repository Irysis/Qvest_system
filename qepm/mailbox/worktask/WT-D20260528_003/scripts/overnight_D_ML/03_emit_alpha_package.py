#!/usr/bin/env python
"""
WT-D20260528_003 Hypothesis D — ML Daily-Informed Monthly Model
Step 3: Emit alpha_package_draft_D_ML.json

Reads:
  stage_artifacts/WT_D20260528_003_overnight_D_ML/
    - cv_results.json (overall + subperiod metrics)
    - predictions_walkforward.parquet
    - feature_importance.parquet
    - best_hyperparams.json
    - panel_summary.json

Writes:
  qepm/mailbox/worktask/WT-D20260528_003/alpha_package_draft_D_ML.json
"""

import json
import time
from pathlib import Path
from datetime import datetime

import numpy as np
import pandas as pd

PROJ = Path('/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot')
WT_ID = 'WT-D20260528_003'
OUT_DIR = PROJ / 'stage_artifacts' / 'WT_D20260528_003_overnight_D_ML'
WT_DIR = PROJ / 'qepm' / 'mailbox' / 'worktask' / WT_ID

t0 = time.time()
print(f"[{datetime.now().strftime('%H:%M:%S')}] Step 3 — emit alpha_package_draft_D_ML.json")

# Load inputs
with open(OUT_DIR / 'cv_results.json') as f:
    cv = json.load(f)
with open(OUT_DIR / 'best_hyperparams.json') as f:
    bh = json.load(f)
with open(OUT_DIR / 'panel_summary.json') as f:
    ps = json.load(f)

preds = pd.read_parquet(OUT_DIR / 'predictions_walkforward.parquet')
fi = pd.read_parquet(OUT_DIR / 'feature_importance.parquet')

# Latest sig_date predictions for alpha_vector (last valid month in walk-forward)
preds['sig_date'] = pd.to_datetime(preds['sig_date'])
latest_sd = preds['sig_date'].max()
latest_preds = preds[preds['sig_date'] == latest_sd].copy()
latest_preds = latest_preds.sort_values('pred', ascending=False)
print(f"  Latest sig_date: {latest_sd}, n={len(latest_preds)}")

# Top-20 selection
TOP_K = 20
top20 = latest_preds.head(TOP_K).copy()
top20['rank_idx'] = range(1, TOP_K + 1)

# Alpha vector: z-score of predictions
mu = latest_preds['pred'].mean()
sd = latest_preds['pred'].std()
latest_preds['alpha_z'] = (latest_preds['pred'] - mu) / (sd + 1e-8)
top20['alpha_z'] = (top20['pred'] - mu) / (sd + 1e-8)

# Full alpha vector (all universe ranked, top 20 = highest predicted return)
alpha_vector = {}
for _, row in latest_preds.iterrows():
    alpha_vector[row['Ticker']] = float(round(row['alpha_z'], 4))

# Top 20 list (for multi-sleeve / production downstream)
top20_list = top20['Ticker'].tolist()

# Confidence vector (from prediction magnitude rank)
latest_preds['conf'] = latest_preds['pred'].rank(pct=True)
confidence_vector = {row['Ticker']: float(round(row['conf'], 3)) for _, row in latest_preds.iterrows()}

# Get top features
top_features = fi.head(15).to_dict('records')

# Build alpha_package_draft
alpha_pkg = {
    "task_id": WT_ID,
    "hypothesis_handle": "hypothesis_D",
    "wt_type": "discovery",
    "schema_version": "alpha_package_v1",
    "as_of_date": "2026-05-28",
    "signal_cutoff": cv['lockbox_cutoff'],
    "forecast_horizon": "1M",
    "rebalance_frequency": "monthly",
    "universe": f"KOSPI200 union KOSDAQ150 intersection (panel rows={cv['panel_rows']}, sig_dates={cv['panel_sig_dates']})",
    "liquidity_floor_won_20d_avg": 200000000,
    "benchmark": "KOSPI200_total_return",
    "hypothesis_title": "STR_1726_DML XGBoost Daily-Informed Monthly Model (Gu-Kelly-Xiu 2020 RFS)",
    "hypothesis_description": (
        "Daily-informed monthly ML alpha model. Compresses 33 daily factor signals (8.07M daily rows) into monthly snapshots at sig_date t (with strict t-1 PIT lag), then trains XGBoost regressor with walk-forward purged CV + 30d embargo (López de Prado 2018). "
        "Feature engineering Block 1 (rolling moments mean/std/zscore @ 21d/60d), Block 2 (cross-section rank dynamics), Block 4 (academic-grounded interactions: value-momentum Asness 2013, quality-lowbeta AQR 2019, skew-MAX Bali-Murray 2013, kurt-turnover). "
        "Target: cross-section z-score of forward 1M log return (winsorize 99.5%). Optuna 50-trial sweep on Fold 0 hyperparams (learning_rate, max_depth, regularization). "
        "Academic grounding: Gu-Kelly-Xiu 2020 RFS 'Empirical Asset Pricing via ML' (gold standard), López de Prado 2018 Purged CV, Jensen-Kelly-Malamud-Pedersen 2022 Net-of-Cost framework, Bryzgalova-Pelger-Zhu 2024 deep learning asset pricing. "
        "AX-007 exception clause #4 (ML sizing via confidence-weighted top-K). "
        "Lockbox: sig_date <= 2023-12-22 strict (alpha-research scope per lockbox-scope.md)."
    ),
    "selection_objective": "icir",
    "n_trials": cv['n_optuna_trials'] + cv['n_folds'] + 1,  # Optuna trials + fold count + model selection
    "n_trials_effective_for_dsr": cv['n_trials_effective_for_dsr'],
    "parallel_exec": True,
    "rcpp_used": False,
    "model_type": "XGBoost_walkforward_purged_cv",
    "ml_framework": {
        "library": "XGBoost",
        "version": "3.2.0",
        "device": "cpu",
        "n_folds": cv['n_folds'],
        "min_train_years": cv['min_train_years'],
        "embargo_days": cv['embargo_days'],
        "best_hyperparams": cv['best_hyperparams'],
        "best_n_estimators": cv['best_n_estimators'],
        "target_column": cv['target'],
        "n_features": cv['n_features'],
    },
    "alpha_vector": alpha_vector,
    "confidence_vector": confidence_vector,
    "signal_matrix_ref": str(OUT_DIR / "predictions_walkforward.parquet"),
    "top20_selection": top20_list,
    "multi_sleeve": {
        "enabled": False,
        "rationale": "ML sizing per AX-007 exception #4 — confidence-weighted top-K selection (not equal-weight). Multi-sleeve not needed as ML inherent diversification."
    },
    "factor_specs": [
        {
            "factor_family": "ML_daily_informed_monthly",
            "proxy": "XGBoost_ensemble_33factor_pred",
            "formula": (
                "XGBoost(features={Block1+Block2+Block4 from 33 daily factors selected from 298 daily DB + sector dummies}, "
                "target=z_xs(forward_1M_log_return), folds=walk_forward_purged({min_train=5y, embargo=30d, test=1y}), "
                "loss=reg_squarederror, hyperparams=Optuna_50trial)"
            ),
            "lag_rule": "Daily features at t-1 trading day snapshot (PIT C1 strict, Cycle 51 shift convention positive n+lead)",
            "winsorization": "Target winsorized 99.5% per panel build (Step 1 R)",
            "neutralization": "Sector_Lv2 dummies as ML feature (model learns sector neutrality endogenously) + cross-section z-score target",
            "economic_rationale": (
                "Gu-Kelly-Xiu 2020 RFS demonstrate nonlinear ML models (gradient boosting + NN) double Sharpe vs linear factor models in US equity. "
                "KR market hypothesis: daily microstructure (vol/turnover/skew rolling dynamics) + cross-factor interactions captures alpha invisible to monthly linear factors. "
                "Walk-forward Purged CV (López de Prado 2018) rigorously prevents look-ahead via embargo. "
                "Multi-horizon rolling moments (mean/std/zscore @21d/60d) per factor extract regime + momentum + dispersion all in one feature space. "
                "Academic interactions (value×momentum, quality×lowbeta, skew×MAX, kurt×turnover) reflect proven KR style premia (AQR-style)."
            ),
            "weight_theta": 1.0,
            "weight_source": "ml_prediction_zscore_at_latest_sig_date",
            "references": [
                "Gu-Kelly-Xiu 2020 RFS Empirical Asset Pricing via Machine Learning",
                "López de Prado 2018 Advances in Financial Machine Learning (Purged CV + Embargo)",
                "Jensen-Kelly-Malamud-Pedersen 2022 Net-of-Cost ML",
                "Bryzgalova-Pelger-Zhu 2024 Deep Learning Asset Pricing",
                "Asness-Frazzini-Pedersen 2019 Quality Minus Junk",
                "Bali-Murray 2013 Tail Risk and Asset Prices (skew×MAX interaction)"
            ],
            "icir_wf": cv['overall_metrics']['icir'],
            "harvey_t_nw": cv['overall_metrics']['t_hac_newey_west'],
            "selected": True,
        }
    ],
    "top_features_by_importance": [
        {"feature": row['feature'], "importance": float(row['importance'])}
        for row in top_features
    ],
    "diagnostics": {
        "rank_ic": cv['overall_metrics']['rank_ic_mean'],
        "rank_ic_median": cv['overall_metrics']['rank_ic_median'],
        "icir": cv['overall_metrics']['icir'],
        "hit_rate": cv['overall_metrics']['hit_rate'],
        "n_sig_dates": cv['overall_metrics']['n_sig_dates'],
        "ic_ci_95_lower": cv['overall_metrics']['ic_ci_95_lower'],
        "ic_ci_95_upper": cv['overall_metrics']['ic_ci_95_upper'],
        "harvey_t_stat_nw": cv['overall_metrics']['t_hac_newey_west'],
        "p_value_hac": cv['overall_metrics']['p_value_hac'],
        "subperiod_stability": cv['subperiod_stability_fraction'],
        "subperiod_metrics": cv['subperiod_metrics'],
        "ax001_v2_bad_normal_ratio": cv['ax001_v2']['ratio_bad_over_normal'],
        "ax001_v2_pass_threshold_05": cv['ax001_v2']['pass_threshold_05'],
        "deflated_sharpe_simplified": cv['dsr_simplified'],
        "fold_metrics": cv['fold_metrics'],
    },
    "method_shopping_log": [
        {
            "name": f"Fold_{f['fold_id']}",
            "rank_ic": f['rank_ic_mean'],
            "icir": f['rank_ic_ir'],
            "selected": True,
            "note": f"Walk-forward fold test_start={f['test_start']} test_end={f['test_end']}"
        }
        for f in cv['fold_metrics']
    ] + [{
        "name": "Optuna_Fold0_BestComposite",
        "rank_ic": float(bh['fold0_optuna_best_score']),
        "icir": None,
        "selected": True,
        "note": f"Optuna 50-trial sweep on Fold 0 (TPE sampler, seed=42)"
    }],
    "challenge_flags": [],
    "pit_assertions": {
        "factor_load": "Daily Factor DB direct load (C15 carve-out: ML + daily parquet exception per .claude/rules/factor-db.md)",
        "sig_date_cutoff": "Date <= 2023-12-22 (alpha-research lockbox per lockbox-scope.md)",
        "walk_forward": f"Walk-forward Purged CV: train >= 5y expanding, test 1y, embargo {cv['embargo_days']}d (López de Prado 2018)",
        "feature_lag": "Daily features at t-1 trading day strict (Cycle 51 shift convention: positive n + type='lag')",
        "forward_return": "log(P_next_me / P_this_me), winsorize 99.5% (target_zxs cross-section z-score)",
        "sector_neutralize": "Sector_Lv2 dummies as ML features (model learns sector premium endogenously)",
        "pit_clean": True,
        "c1_c15_assertion": "C1 expanding rolling CV / C13 not applicable (ML direct features not Z_Score_Aligned) / C14 N/A (no IC pre-load — ML inferred) / C15 CARVE-OUT for ML + daily parquet",
        "c15_carve_out_justification": ".claude/rules/factor-db.md allows ML + daily parquet exception. ML model requires rich daily-rolling features beyond load_month_factors() output schema."
    },
    "graduation_criteria_check": {
        "min_rank_ic": {
            "threshold": 0.04,
            "actual": cv['overall_metrics']['rank_ic_mean'],
            "PASS": cv['overall_metrics']['rank_ic_mean'] >= 0.04,
        },
        "min_icir": {
            "threshold": 0.2,
            "actual": cv['overall_metrics']['icir'],
            "PASS": cv['overall_metrics']['icir'] >= 0.2,
        },
        "min_subperiod_stability": {
            "threshold": 0.5,
            "actual": cv['subperiod_stability_fraction'],
            "PASS": cv['subperiod_stability_fraction'] >= 0.5,
        },
        "min_harvey_t_stat": {
            "threshold": 3.0,
            "actual": cv['overall_metrics']['t_hac_newey_west'],
            "PASS": cv['overall_metrics']['t_hac_newey_west'] >= 3.0,
        },
        "min_deflated_sharpe_ratio": {
            "threshold": 0.5,
            "actual": cv['dsr_simplified'],
            "PASS": cv['dsr_simplified'] >= 0.5 if cv['dsr_simplified'] is not None else False,
        },
        "max_drawdown_days": {
            "threshold": 100,
            "actual": None,
            "note": "Not computed (single-period rebalance, drawdown only meaningful after backtest)",
            "PASS": None,
        },
        "ax001_v2": {
            "threshold": 0.5,
            "actual": cv['ax001_v2']['ratio_bad_over_normal'],
            "PASS": cv['ax001_v2']['pass_threshold_05'],
        },
    },
    "challenge_flags": [],
    "build_meta": {
        "step1_panel_rows": cv['panel_rows'],
        "step1_feature_cols": cv['n_features'],
        "step1_build_time_min": ps.get('build_time_min'),
        "step2_cv_elapsed_sec": cv['elapsed_seconds'],
        "step2_optuna_n_trials": cv['n_optuna_trials'],
        "step3_emit_ts": datetime.now().isoformat(),
    },
}

# Add challenge flags based on graduation check
gc = alpha_pkg["graduation_criteria_check"]

if not gc['min_rank_ic']['PASS']:
    alpha_pkg["challenge_flags"].append({
        "id": "IC_LOW",
        "severity": "HIGH",
        "detail": f"Rank IC mean {gc['min_rank_ic']['actual']:.4f} < 0.04 graduation threshold.",
        "action_required": "ML alpha below alpha lab threshold. Either signal genuinely weak in lockbox, or feature engineering insufficient."
    })

if not gc['min_icir']['PASS']:
    alpha_pkg["challenge_flags"].append({
        "id": "ICIR_LOW",
        "severity": "HIGH",
        "detail": f"ICIR {gc['min_icir']['actual']:.3f} < 0.20 alpha lab threshold (Charter v1.7).",
        "action_required": "Signal not stable across sig_dates. Consider feature reduction or different model class."
    })

if not gc['min_harvey_t_stat']['PASS']:
    alpha_pkg["challenge_flags"].append({
        "id": "HARVEY_FAIL",
        "severity": "HIGH",
        "detail": f"Harvey-Liu-Zhu adjusted t_HAC = {gc['min_harvey_t_stat']['actual']:.2f} < 3.0 threshold (multi-testing adjusted for {alpha_pkg['n_trials']} trials).",
        "action_required": "Discovery certificate eligibility FAIL — does not survive multi-testing correction."
    })

if not gc['min_deflated_sharpe_ratio']['PASS']:
    alpha_pkg["challenge_flags"].append({
        "id": "DSR_FAIL",
        "severity": "HIGH",
        "detail": f"Deflated Sharpe Ratio (simplified) = {gc['min_deflated_sharpe_ratio']['actual']} < 0.5 graduation threshold (Bailey-Lopez de Prado 2014).",
        "action_required": "After Optuna multi-trial adjustment, SR not distinguishable from null."
    })

if not gc['ax001_v2']['PASS']:
    alpha_pkg["challenge_flags"].append({
        "id": "AX001_v2_FAIL",
        "severity": "MEDIUM",
        "detail": f"AX-001 v2 bad/normal IC ratio = {gc['ax001_v2']['actual']:.3f} < 0.5 threshold. Signal does not retain efficacy in bad regimes.",
        "action_required": "ML may overfit to normal regime. Crisis robustness check needed."
    })

# Add ML-specific challenges
top10_sum_imp = float(fi.head(10)['importance'].sum())
total_imp = float(fi['importance'].sum())
if total_imp > 0 and top10_sum_imp / total_imp > 0.80:
    alpha_pkg["challenge_flags"].append({
        "id": "FEATURE_CONCENTRATION",
        "severity": "MEDIUM",
        "detail": f"Top 10 features hold {top10_sum_imp/total_imp:.1%} of importance — model effectively low-dimensional.",
        "action_required": "Consider feature reduction or linear baseline comparison."
    })

# Save draft
out_path = WT_DIR / 'alpha_package_draft_D_ML.json'
with open(out_path, 'w', encoding='utf-8') as f:
    json.dump(alpha_pkg, f, indent=2, ensure_ascii=False, default=str)

print(f"  Saved: {out_path}")
print(f"\n=== Step 3 COMPLETE — elapsed {(time.time()-t0):.1f}s ===")
print(f"  Graduation check:")
for k, v in gc.items():
    if isinstance(v, dict) and 'PASS' in v:
        status = "PASS" if v['PASS'] else "FAIL" if v['PASS'] is False else "N/A"
        print(f"    {k:<25} {status:<6} actual={v.get('actual')}")
print(f"  Challenge flags: {len(alpha_pkg['challenge_flags'])}")
for cf in alpha_pkg['challenge_flags']:
    print(f"    [{cf['severity']}] {cf['id']}: {cf['detail']}")
