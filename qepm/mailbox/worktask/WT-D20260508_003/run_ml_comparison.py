"""
WT-D20260508_003 — ML XGBoost CUDA vs Classical OLS Fama-MacBeth Baseline

Purpose:
  - Compare ML (XGBoost CUDA) vs classical baseline (OLS Fama-MacBeth) for VRP vol-beta
  - WT_001 v3 trap detection: feature leakage (lag-0 / target leakage), naive long bias
  - GPU acceleration report (CPU vs GPU train time)

Inputs:
  - stage_artifacts/WT_D20260508_003/ml_panel.parquet
    cols: Ticker, yearmonth, Date, fwd_ret, beta_*, alpha_*_sn, alpha_F5, period, Sector

Outputs:
  - stage_artifacts/WT_D20260508_003/ml_comparison_results.json
  - stage_artifacts/WT_D20260508_003/feature_leakage_check.json
  - stage_artifacts/WT_D20260508_003/gpu_acceleration_report.json
"""

import json
import time
import warnings
import numpy as np
import pandas as pd
import pyarrow.parquet as pq
from pathlib import Path

warnings.filterwarnings("ignore")

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WT_ID = "WT-D20260508_003"
STAGE_DIR = PROJECT_ROOT / "stage_artifacts" / "WT_D20260508_003"
WT_DIR = PROJECT_ROOT / "qepm" / "mailbox" / "worktask" / WT_ID

print("=== WT-D20260508_003 ML Comparison (XGBoost CUDA vs OLS) ===")

# Load ML panel
ml_panel_path = STAGE_DIR / "ml_panel.parquet"
print(f"Loading ML panel: {ml_panel_path}")
df = pq.read_table(ml_panel_path).to_pandas()
print(f"  rows: {len(df)}, periods: {df['period'].value_counts().to_dict()}")

# Feature columns (lag-1 only, no target leakage)
FEATURE_COLS = [
    "beta_BKM", "beta_CW", "beta_BTZ", "beta_BCI",
    "alpha_BKM_sn", "alpha_CW_sn", "alpha_BTZ_sn", "alpha_BCI_sn",
    "alpha_F5"
]
TARGET_COL = "fwd_ret"

# ─────────────────────────────────────────────────────────────────────────────
# Step A: Feature Leakage Check (WT_001 v3 trap)
#   - Each feature must be lag-1 (no contemporaneous use)
#   - target = next-month r_i (already shifted in R script)
#   - Test: cor(feature, target) per ticker — should be near-zero on lag-0 contamporaneous join
# ─────────────────────────────────────────────────────────────────────────────
print("\n[Step A] Feature leakage check (lag-0 / target leakage detection)...")

# Self-correlation check: feature_t vs feature_t (should be 1.0 by definition)
# vs feature_t vs fwd_ret (should be IC-level, not 1.0)
leakage_check = {}
for fc in FEATURE_COLS:
    # Cross-section IC (target leakage would inflate this to >0.3)
    df_clean = df.dropna(subset=[fc, TARGET_COL])
    if len(df_clean) < 100:
        leakage_check[fc] = {"n": 0, "ic": None, "leakage_risk": "INSUFFICIENT_DATA"}
        continue

    # Per-month IC (Spearman)
    ics = df_clean.groupby("yearmonth").apply(
        lambda g: g[fc].corr(g[TARGET_COL], method="spearman") if len(g) >= 10 else np.nan
    )
    mean_ic = ics.dropna().mean()

    # Pearson cor (raw level)
    raw_cor = df_clean[fc].corr(df_clean[TARGET_COL])

    leakage_check[fc] = {
        "n": int(len(df_clean)),
        "mean_monthly_ic_spearman": float(round(mean_ic, 4)) if not pd.isna(mean_ic) else None,
        "pooled_pearson_cor": float(round(raw_cor, 4)) if not pd.isna(raw_cor) else None,
        "leakage_risk": (
            "HIGH_TARGET_LEAKAGE_SUSPECTED"
            if (not pd.isna(mean_ic) and abs(mean_ic) > 0.30) or
               (not pd.isna(raw_cor) and abs(raw_cor) > 0.30)
            else "OK_NORMAL_IC_RANGE"
        )
    }

leakage_report = {
    "purpose": "WT_001 v3 trap: ML XGBoost IC=0.9953 was r_AR_lag1 feature leakage. Re-test all features.",
    "leakage_threshold_ic_spearman": 0.30,
    "leakage_threshold_pearson_cor": 0.30,
    "n_features_checked": len(FEATURE_COLS),
    "features_at_risk": sum(1 for v in leakage_check.values() if v.get("leakage_risk", "").startswith("HIGH")),
    "details": leakage_check
}
with open(STAGE_DIR / "feature_leakage_check.json", "w") as f:
    json.dump(leakage_report, f, indent=2, ensure_ascii=False, default=str)

print(f"  Features checked: {len(FEATURE_COLS)}")
print(f"  Features at risk (target leakage): {leakage_report['features_at_risk']}")
for fc, v in leakage_check.items():
    risk = v.get("leakage_risk", "")
    ic = v.get("mean_monthly_ic_spearman")
    print(f"    {fc}: IC={ic} risk={risk}")

# ─────────────────────────────────────────────────────────────────────────────
# Step B: Train/Validation/Lockbox Split (R2 Window Isolation HARD)
# ─────────────────────────────────────────────────────────────────────────────
print("\n[Step B] Window isolation split...")

# train = 2008~2014 (p1)
# validation = 2015~2019 (p2)
# lockbox = 2020~2026.04 (p3) — Alpha access HARD BLOCK
#   But we evaluate ML on lockbox SEPARATELY (diagnostic only, not for selection)

train_df = df[df["period"] == "p1_2008_14"].copy()
val_df = df[df["period"] == "p2_2015_19"].copy()
lockbox_df = df[df["period"] == "p3_lockbox_2020_26"].copy()

# Drop rows with any feature NaN
train_df = train_df.dropna(subset=FEATURE_COLS + [TARGET_COL])
val_df = val_df.dropna(subset=FEATURE_COLS + [TARGET_COL])
lockbox_df = lockbox_df.dropna(subset=FEATURE_COLS + [TARGET_COL])

print(f"  train (2008-14): {len(train_df)} rows")
print(f"  validation (2015-19): {len(val_df)} rows")
print(f"  lockbox (2020-26.04): {len(lockbox_df)} rows [REPORTED SEPARATELY, NOT USED FOR SELECTION]")

X_train = train_df[FEATURE_COLS].values.astype(np.float32)
y_train = train_df[TARGET_COL].values.astype(np.float32)
X_val = val_df[FEATURE_COLS].values.astype(np.float32)
y_val = val_df[TARGET_COL].values.astype(np.float32)
X_lockbox = lockbox_df[FEATURE_COLS].values.astype(np.float32)
y_lockbox = lockbox_df[TARGET_COL].values.astype(np.float32)

# ─────────────────────────────────────────────────────────────────────────────
# Step C: Classical Baseline — OLS Fama-MacBeth (per-month cross-section regression)
# ─────────────────────────────────────────────────────────────────────────────
print("\n[Step C] Classical baseline: OLS Fama-MacBeth (per-month cross-section)...")
import statsmodels.api as sm

def fama_macbeth_predict(train, val, feature_cols):
    """Per-month cross-section OLS coefficients averaged → forward prediction"""
    coefs_list = []
    for ym, g in train.groupby("yearmonth"):
        if len(g) < 30:
            continue
        X = sm.add_constant(g[feature_cols].values)
        y = g[TARGET_COL].values
        try:
            model = sm.OLS(y, X).fit()
            coefs_list.append(model.params)
        except Exception:
            continue
    if not coefs_list:
        return None
    avg_coefs = np.mean(coefs_list, axis=0)

    # Predict on validation
    X_v = sm.add_constant(val[feature_cols].values)
    y_pred = X_v @ avg_coefs
    return y_pred, avg_coefs

t0 = time.time()
fm_result = fama_macbeth_predict(train_df, val_df, FEATURE_COLS)
fm_time = time.time() - t0

if fm_result is not None:
    y_pred_fm, fm_coefs = fm_result
    fm_ic_pooled = pd.Series(y_pred_fm).corr(pd.Series(y_val), method="spearman")
    # Per-month IC
    val_df["pred_fm"] = y_pred_fm
    fm_monthly_ic = val_df.groupby("yearmonth").apply(
        lambda g: g["pred_fm"].corr(g[TARGET_COL], method="spearman") if len(g) >= 10 else np.nan
    )
    fm_mean_ic = fm_monthly_ic.dropna().mean()
    fm_ic_std = fm_monthly_ic.dropna().std()
    fm_icir = fm_mean_ic / fm_ic_std if fm_ic_std > 0 else np.nan
else:
    fm_mean_ic = np.nan; fm_icir = np.nan; fm_ic_pooled = np.nan; fm_coefs = None

print(f"  Fama-MacBeth: time={fm_time:.2f}s, mean_monthly_IC={fm_mean_ic:.4f}, ICIR={fm_icir:.4f}")

# ─────────────────────────────────────────────────────────────────────────────
# Step D: XGBoost CPU vs CUDA timing
# ─────────────────────────────────────────────────────────────────────────────
print("\n[Step D] XGBoost CPU vs CUDA timing benchmark...")
import xgboost as xgb

XGB_PARAMS_BASE = {
    "objective": "reg:squarederror",
    "max_depth": 5,
    "learning_rate": 0.05,
    "subsample": 0.8,
    "colsample_bytree": 0.8,
    "n_estimators": 500,
    "verbosity": 0,
    "early_stopping_rounds": 30
}

# CPU run
print("  XGBoost CPU...")
xgb_cpu = xgb.XGBRegressor(**XGB_PARAMS_BASE, tree_method="hist", device="cpu", n_jobs=8)
t0 = time.time()
xgb_cpu.fit(X_train, y_train, eval_set=[(X_val, y_val)], verbose=False)
cpu_time = time.time() - t0
print(f"    CPU train time: {cpu_time:.2f}s")

# CUDA run
print("  XGBoost CUDA...")
xgb_gpu = xgb.XGBRegressor(**XGB_PARAMS_BASE, tree_method="hist", device="cuda")
t0 = time.time()
xgb_gpu.fit(X_train, y_train, eval_set=[(X_val, y_val)], verbose=False)
gpu_time = time.time() - t0
print(f"    GPU train time: {gpu_time:.2f}s")

# Use GPU for prediction (faster + same output)
y_pred_xgb_val = xgb_gpu.predict(X_val)
y_pred_xgb_lockbox = xgb_gpu.predict(X_lockbox)

# ─────────────────────────────────────────────────────────────────────────────
# Step E: ML diagnostics on validation + lockbox (separate)
# ─────────────────────────────────────────────────────────────────────────────
print("\n[Step E] ML diagnostics (validation + lockbox)...")

val_df_xgb = val_df.copy()
val_df_xgb["pred_xgb"] = y_pred_xgb_val
xgb_monthly_ic_val = val_df_xgb.groupby("yearmonth").apply(
    lambda g: g["pred_xgb"].corr(g[TARGET_COL], method="spearman") if len(g) >= 10 else np.nan
)
xgb_mean_ic_val = xgb_monthly_ic_val.dropna().mean()
xgb_icir_val = xgb_mean_ic_val / xgb_monthly_ic_val.dropna().std() if xgb_monthly_ic_val.dropna().std() > 0 else np.nan
xgb_n_pos_val = int(np.sum(y_pred_xgb_val > 0))
xgb_pos_pct_val = xgb_n_pos_val / len(y_pred_xgb_val)

# Lockbox separate (R2 Window Isolation HARD: report only, not for selection)
lockbox_df_xgb = lockbox_df.copy()
lockbox_df_xgb["pred_xgb"] = y_pred_xgb_lockbox
xgb_monthly_ic_lock = lockbox_df_xgb.groupby("yearmonth").apply(
    lambda g: g["pred_xgb"].corr(g[TARGET_COL], method="spearman") if len(g) >= 10 else np.nan
)
xgb_mean_ic_lock = xgb_monthly_ic_lock.dropna().mean()
xgb_icir_lock = xgb_mean_ic_lock / xgb_monthly_ic_lock.dropna().std() if xgb_monthly_ic_lock.dropna().std() > 0 else np.nan
xgb_pos_pct_lock = float(np.sum(y_pred_xgb_lockbox > 0) / len(y_pred_xgb_lockbox))

# Naive long bias check (WT_001 v3 trap re-detection)
NAIVE_LONG_BIAS_THRESHOLD = 0.70  # If >70% predictions are positive, suspect naive long bias
naive_long_bias_val = xgb_pos_pct_val > NAIVE_LONG_BIAS_THRESHOLD
naive_long_bias_lock = xgb_pos_pct_lock > NAIVE_LONG_BIAS_THRESHOLD

ml_results = {
    "ml_methods": ["XGBoost_GPU_hist_CUDA", "XGBoost_CPU_hist", "OLS_Fama_MacBeth_baseline"],
    "data_split": {
        "train_2008_2014": len(train_df),
        "validation_2015_2019": len(val_df),
        "lockbox_2020_2026_04": len(lockbox_df),
        "policy": "R2 Window Isolation HARD: lockbox NOT used for selection, reported separately"
    },
    "feature_cols": FEATURE_COLS,
    "n_features": len(FEATURE_COLS),

    "xgboost_gpu": {
        "validation_mean_monthly_ic": float(round(xgb_mean_ic_val, 4)),
        "validation_icir": float(round(xgb_icir_val, 4)),
        "validation_n_months": int(xgb_monthly_ic_val.dropna().shape[0]),
        "validation_pos_pred_pct": float(round(xgb_pos_pct_val, 4)),
        "validation_naive_long_bias_detected": bool(naive_long_bias_val),
        "lockbox_mean_monthly_ic": float(round(xgb_mean_ic_lock, 4)),
        "lockbox_icir": float(round(xgb_icir_lock, 4)),
        "lockbox_pos_pred_pct": float(round(xgb_pos_pct_lock, 4)),
        "lockbox_naive_long_bias_detected": bool(naive_long_bias_lock)
    },

    "fama_macbeth_baseline": {
        "validation_mean_monthly_ic": float(round(fm_mean_ic, 4)) if not pd.isna(fm_mean_ic) else None,
        "validation_icir": float(round(fm_icir, 4)) if not pd.isna(fm_icir) else None,
        "fm_avg_coefs": fm_coefs.tolist() if fm_coefs is not None else None,
        "fm_feature_names": ["intercept"] + FEATURE_COLS
    },

    "ml_vs_classical": {
        "xgb_validation_ic_minus_fm_ic": float(round(xgb_mean_ic_val - fm_mean_ic, 4)) if not pd.isna(fm_mean_ic) else None,
        "winner": (
            "XGBoost_GPU" if not pd.isna(fm_mean_ic) and xgb_mean_ic_val > fm_mean_ic
            else "OLS_Fama_MacBeth_baseline"
        ),
        "verdict": (
            "ML beats classical baseline (interpret: nonlinear interactions captured)"
            if not pd.isna(fm_mean_ic) and xgb_mean_ic_val > fm_mean_ic
            else "Classical baseline >= ML — no ML uplift, simpler model preferred"
        )
    },

    "wt_001_trap_redetection": {
        "feature_leakage_features_at_risk": leakage_report["features_at_risk"],
        "naive_long_bias_xgb_validation_pct": float(round(xgb_pos_pct_val, 4)),
        "naive_long_bias_xgb_lockbox_pct": float(round(xgb_pos_pct_lock, 4)),
        "naive_long_bias_threshold": NAIVE_LONG_BIAS_THRESHOLD,
        "trap_status": (
            "WT_001-LIKE NAIVE LONG BIAS DETECTED — INVESTIGATE"
            if naive_long_bias_val or naive_long_bias_lock
            else "OK normal pred sign distribution"
        )
    }
}
with open(STAGE_DIR / "ml_comparison_results.json", "w") as f:
    json.dump(ml_results, f, indent=2, ensure_ascii=False, default=str)

# GPU acceleration report
gpu_report = {
    "hardware": "NVIDIA GeForce RTX 4080 SUPER (17.17 GB)",
    "venv": "/home/quant/.venvs/qvest_ml",
    "torch_version": "2.6.0+cu124",
    "xgboost_version": "3.2.0",
    "models_tested": ["XGBoost"],
    "xgboost_cpu_time_sec": float(round(cpu_time, 3)),
    "xgboost_gpu_time_sec": float(round(gpu_time, 3)),
    "xgboost_gpu_speedup_x": float(round(cpu_time / gpu_time, 2)) if gpu_time > 0 else None,
    "fama_macbeth_time_sec": float(round(fm_time, 3)),
    "n_train_obs": len(train_df),
    "n_features": len(FEATURE_COLS),
    "interpretation": (
        f"XGBoost CUDA {gpu_time:.2f}s vs CPU {cpu_time:.2f}s = "
        f"{cpu_time/gpu_time:.1f}x speedup. Useful for cross-validation grids and DSR bootstrap."
    )
}
with open(STAGE_DIR / "gpu_acceleration_report.json", "w") as f:
    json.dump(gpu_report, f, indent=2, ensure_ascii=False, default=str)

# ─────────────────────────────────────────────────────────────────────────────
# Step F: TimeSeriesCV (Lopez de Prado 2020 — overfitting prevention)
# ─────────────────────────────────────────────────────────────────────────────
print("\n[Step F] Time-series CV (Combinatorial Purged CV approximation)...")

# Simple: 5-fold time-series CV on validation period
from sklearn.model_selection import TimeSeriesSplit

cv_panel = pd.concat([train_df, val_df], ignore_index=True).sort_values(["yearmonth", "Ticker"]).reset_index(drop=True)
X_cv = cv_panel[FEATURE_COLS].values.astype(np.float32)
y_cv = cv_panel[TARGET_COL].values.astype(np.float32)

tscv = TimeSeriesSplit(n_splits=5)
cv_ics = []
for fold_idx, (train_idx, test_idx) in enumerate(tscv.split(X_cv)):
    X_tr, y_tr = X_cv[train_idx], y_cv[train_idx]
    X_te, y_te = X_cv[test_idx], y_cv[test_idx]

    if len(np.unique(y_tr)) < 10 or len(X_te) < 30:
        continue

    model = xgb.XGBRegressor(**{**XGB_PARAMS_BASE, "n_estimators": 200},
                              tree_method="hist", device="cuda")
    # Remove early_stopping for CV (no separate eval set)
    params_cv = {**XGB_PARAMS_BASE, "n_estimators": 200}
    params_cv.pop("early_stopping_rounds", None)
    model = xgb.XGBRegressor(**params_cv, tree_method="hist", device="cuda")
    model.fit(X_tr, y_tr, verbose=False)
    y_pred = model.predict(X_te)

    fold_ic = pd.Series(y_pred).corr(pd.Series(y_te), method="spearman")
    cv_ics.append({"fold": fold_idx + 1, "n_train": len(X_tr), "n_test": len(X_te),
                    "pooled_ic": float(round(fold_ic, 4))})

cv_ic_mean = float(round(np.mean([c["pooled_ic"] for c in cv_ics if not pd.isna(c["pooled_ic"])]), 4)) if cv_ics else None
cv_ic_std = float(round(np.std([c["pooled_ic"] for c in cv_ics if not pd.isna(c["pooled_ic"])]), 4)) if cv_ics else None

cv_summary = {
    "method": "TimeSeriesSplit (Lopez de Prado 2020 simple TSCV)",
    "n_splits": 5,
    "fold_details": cv_ics,
    "mean_pooled_ic": cv_ic_mean,
    "std_pooled_ic": cv_ic_std,
    "stability_assessment": (
        "STABLE" if cv_ic_std is not None and cv_ic_std < 0.10
        else "UNSTABLE" if cv_ic_std is not None
        else "INSUFFICIENT_DATA"
    )
}
ml_results["time_series_cv"] = cv_summary
with open(STAGE_DIR / "ml_comparison_results.json", "w") as f:
    json.dump(ml_results, f, indent=2, ensure_ascii=False, default=str)

print(f"  TimeSeriesCV: mean_IC={cv_ic_mean}, std={cv_ic_std}")

print("\n=== ML COMPARISON COMPLETE ===")
print(f"XGBoost GPU validation IC: {xgb_mean_ic_val:.4f} (vs Fama-MacBeth: {fm_mean_ic:.4f})")
print(f"GPU speedup: {cpu_time/gpu_time:.1f}x")
print(f"Naive long bias risk: VAL={'YES' if naive_long_bias_val else 'NO'}, LOCK={'YES' if naive_long_bias_lock else 'NO'}")
print(f"Feature leakage at risk: {leakage_report['features_at_risk']}/{len(FEATURE_COLS)}")
