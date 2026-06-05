#==============================================================================
# 200_cycle58d_stacking_metalearner.py
#
# 목적: 4-cluster diagnostic + 58C 결과 종합 → meta-learner stacking 실험.
# Simple mean ensemble은 cluster 다양성 무시 (weight 동등). Ridge / LGBM 으로
# 가중 학습 → cluster-representative predictions 결합.
#
# 5 cluster representatives (58C + 58C diag 통합):
#   1. 53I_v5f_FIXED2_5seed   (Cluster 1: clean BBVA, no cross-market)
#   2. 54A_v3_patch7_5seed    (Cluster 2: isolated patch=7 architecture)
#   3. 54A_v3_patch7_FIXED2   (Cluster 3: dm=32 family post-cleanup)
#   4. 53I_v5g_cross_market_15seed (Cluster 4: full cross-market 15-seed)
#   5. 53I_v5h_interactions_5seed (Cluster 5: 58C winner +0.030 sig)
#
# Stacker: Ridge L2 logistic regression + LightGBM (if available).
# Eval: chronological 60% train / 40% test split (within OOS).
# Compare: bootstrap CI vs current best v5h 0.2762.
# CPU only.
#==============================================================================

import os
import sys
import json
import numpy as np
import pandas as pd
from pathlib import Path
from datetime import datetime

import pyarrow.parquet as pq  # noqa: E402
from sklearn.linear_model import LogisticRegression  # noqa: E402
from sklearn.metrics import average_precision_score  # noqa: E402

PROJECT_ROOT = Path(
    "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
)
WS = (PROJECT_ROOT /
      "04_Research/decision_framework/bearish_forecast_v2_alt_data")
MODELS = WS / "outputs/03_models"
OUT_DIR = WS / "outputs/04_evaluation"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# 1. 5 cluster representatives (mean5 / mean15 predictions)
REPS = {
    "v5f_FIXED2_C1": (
        MODELS / "cycle57b_q15_BBVA_fixed" /
        "predictions_53I_v5f_FIXED2_mean5_y_tail_q15.parquet"
    ),
    "v3_patch7_C2": (
        MODELS / "cycle54a_q15_phase3_v3" /
        "predictions_53I_v3_patch7_mean5_y_tail_q15.parquet"
    ),
    "v3_patch7_FIXED2_C3": (
        MODELS / "cycle57b_q15_BBVA_fixed" /
        "predictions_54A_v3_patch7_FIXED2_mean5_y_tail_q15.parquet"
    ),
    "v5g_cross_market_C4": (
        MODELS / "cycle58c_v5g_15seed" /
        "predictions_53I_v5g_cross_market_mean15_y_tail_q15.parquet"
    ),
    "v5h_interactions_C5": (
        MODELS / "cycle58c_v5h_5seed" /
        "predictions_53I_v5h_interactions_mean5_y_tail_q15.parquet"
    ),
}

# Existence check + fallback for v3_patch7 if file missing
print(f"[{datetime.now():%H:%M:%S}] Loading 5 cluster representatives...")
for name, path in REPS.items():
    if not path.exists():
        print(f"  [MISSING] {name}: {path}")

# Validate critical files (fallback for v3_patch7 if not in expected location)
v3_patch7_search = list(MODELS.rglob(
    "predictions_*v3_patch7*mean5_y_tail_q15.parquet"
))
print(f"  v3_patch7 alternatives found: {len(v3_patch7_search)}")
for p in v3_patch7_search[:5]:
    print(f"    {p.relative_to(MODELS)}")

# Use first found if original missing
if not REPS["v3_patch7_C2"].exists() and v3_patch7_search:
    # Prefer non-FIXED2 (Cluster 2)
    non_fixed2 = [p for p in v3_patch7_search if "FIXED2" not in p.name]
    if non_fixed2:
        REPS["v3_patch7_C2"] = non_fixed2[0]
        print(f"  [FALLBACK] v3_patch7_C2 → {REPS['v3_patch7_C2'].name}")
    else:
        REPS["v3_patch7_C2"] = v3_patch7_search[0]
        print(f"  [FALLBACK] v3_patch7_C2 → {REPS['v3_patch7_C2'].name}")

# 2. Load + OOS filter + date align
dfs = {}
for name, path in REPS.items():
    if not path.exists():
        print(f"  [SKIP] {name}: file missing → dropping from corpus")
        continue
    t = pq.read_table(path)
    df = t.to_pandas()
    df["Date"] = pd.to_datetime(df["Date"]).dt.date
    # Auto-detect prediction column (p_mean5 or p_mean15)
    p_col = "p_mean15" if "p_mean15" in df.columns else "p_mean5"
    df = df[df["split"] == "oos"][["Date", p_col, "y"]].copy()
    df = df.rename(columns={p_col: f"p_{name}"})
    df = df.sort_values("Date").drop_duplicates(subset=["Date"])
    dfs[name] = df
    print(f"  [{name}] n_oos={len(df)} dates "
          f"({df['Date'].min()} ~ {df['Date'].max()}) col={p_col}")

n_reps = len(dfs)
print(f"\n[{datetime.now():%H:%M:%S}] {n_reps} representatives loaded.")

# 3. Inner-join on Date
keys = list(dfs.keys())
merged = dfs[keys[0]].copy()
for k in keys[1:]:
    df_k = dfs[k][["Date", f"p_{k}", "y"]].rename(
        columns={"y": f"y_{k}"}
    )
    merged = merged.merge(df_k, on="Date", how="inner")
    # Use first y_ for consistency check
print(f"\n[{datetime.now():%H:%M:%S}] Merged: n_dates={len(merged)}")

# Verify y consistency across all reps
y_cols = ["y"] + [c for c in merged.columns if c.startswith("y_")]
y_check = merged[y_cols].nunique(axis=1)
inconsistent = (y_check > 1).sum()
print(f"  y inconsistent rows: {inconsistent} (should be 0)")
y = merged["y"].values

# Feature matrix X
feat_cols = [f"p_{k}" for k in keys]
X = merged[feat_cols].values
dates = pd.to_datetime(merged["Date"]).values
print(f"  X shape: {X.shape}, y positive rate: {y.mean():.3%}")

# 4. Chronological split: 50% train / 25% val (C tuning) / 25% test
split_train = int(len(merged) * 0.5)
split_val = int(len(merged) * 0.75)
X_train = X[:split_train]
X_val = X[split_train:split_val]
X_test = X[split_val:]
y_train = y[:split_train]
y_val = y[split_train:split_val]
y_test = y[split_val:]
dates_train = dates[:split_train]
dates_val = dates[split_train:split_val]
dates_test = dates[split_val:]
print(f"\n[{datetime.now():%H:%M:%S}] Train: {len(X_train)} "
      f"({dates_train[0]} ~ {dates_train[-1]})")
print(f"  Val:   {len(X_val)} "
      f"({dates_val[0]} ~ {dates_val[-1]})")
print(f"  Test:  {len(X_test)} "
      f"({dates_test[0]} ~ {dates_test[-1]})")
print(f"  Train pos rate: {y_train.mean():.3%}  "
      f"Val: {y_val.mean():.3%}  Test: {y_test.mean():.3%}")

# 5. Baseline: simple mean (current best v5h on this subset)
print(f"\n[{datetime.now():%H:%M:%S}] === Baselines on test ===")

# Simple mean of all 5
simple_mean_test = X_test.mean(axis=1)
pr_simple = average_precision_score(y_test, simple_mean_test)
print(f"  Simple mean (5 reps): PR-AUC={pr_simple:.4f}")

# Each rep alone on test
print("  Individual reps on test:")
for i, k in enumerate(keys):
    pr_i = average_precision_score(y_test, X_test[:, i])
    print(f"    {k}: PR-AUC={pr_i:.4f}")

# 6. Meta-learner 1: Ridge logistic regression
# C tuning on validation set (NOT test, prevent peeking)
print(f"\n[{datetime.now():%H:%M:%S}] === Ridge Logistic — C tuning on VAL ===")
import warnings  # noqa: E402
warnings.filterwarnings("ignore", category=FutureWarning)

c_grid = [0.01, 0.1, 1.0, 10.0]
val_results = {}
for C in c_grid:
    clf = LogisticRegression(
        C=C, penalty="l2", solver="lbfgs", max_iter=2000,
        class_weight="balanced", random_state=42,
    )
    clf.fit(X_train, y_train)
    p_val = clf.predict_proba(X_val)[:, 1]
    pr_val = average_precision_score(y_val, p_val)
    val_results[C] = pr_val
    coefs = clf.coef_[0]
    coef_str = ", ".join(f"{k}={c:+.3f}" for k, c in zip(keys, coefs))
    print(f"  C={C}: VAL PR-AUC={pr_val:.4f}  "
          f"intercept={clf.intercept_[0]:+.3f}")
    print(f"    coefs: {coef_str}")

best_C = max(val_results, key=val_results.get)
print(f"\n  ✓ Best C on VAL: {best_C} (val PR-AUC={val_results[best_C]:.4f})")

# Re-fit on train ONLY (no val leakage) with best C → predict TEST
clf_best = LogisticRegression(
    C=best_C, penalty="l2", solver="lbfgs", max_iter=2000,
    class_weight="balanced", random_state=42,
)
clf_best.fit(X_train, y_train)
p_test = clf_best.predict_proba(X_test)[:, 1]
pr_meta = average_precision_score(y_test, p_test)
print(f"  Test PR-AUC (best C={best_C}, train-only fit): {pr_meta:.4f}")

# 7. Meta-learner 2: LightGBM if available
print(f"\n[{datetime.now():%H:%M:%S}] === LightGBM Meta-learner ===")
try:
    import lightgbm as lgb
    pos_weight = (1 - y_train.mean()) / max(y_train.mean(), 1e-9)
    for n_est in [50, 100, 200]:
        for max_depth in [3, 5]:
            mdl = lgb.LGBMClassifier(
                n_estimators=n_est, max_depth=max_depth,
                learning_rate=0.05, scale_pos_weight=pos_weight,
                random_state=42, verbose=-1,
            )
            mdl.fit(X_train, y_train)
            p_test = mdl.predict_proba(X_test)[:, 1]
            pr_lgb = average_precision_score(y_test, p_test)
            print(f"  n_est={n_est} depth={max_depth}: PR-AUC={pr_lgb:.4f}")
except ImportError:
    print("  lightgbm not available — skipping")

# 8. Bootstrap CI on best stacker (already fit with best_C above)
print(f"\n[{datetime.now():%H:%M:%S}] === Bootstrap CI (best C={best_C}) ===")

B = 1000
np.random.seed(42)
n_test = len(y_test)
pr_boot = np.empty(B)
for b in range(B):
    idx = np.random.choice(n_test, n_test, replace=True)
    if y_test[idx].sum() < 5:
        pr_boot[b] = np.nan
        continue
    pr_boot[b] = average_precision_score(y_test[idx], p_test[idx])
pr_boot = pr_boot[~np.isnan(pr_boot)]
print(f"  Ridge stacker on test: PR-AUC={pr_meta:.4f} (point)")
print(f"  Bootstrap CI [95%]: [{np.quantile(pr_boot, 0.025):.4f}, "
      f"{np.quantile(pr_boot, 0.975):.4f}]  mean={pr_boot.mean():.4f}")

# 9. Compare to v5h (Cluster 5) on test alone
v5h_test = X_test[:, keys.index("v5h_interactions_C5")]
pr_v5h_test = average_precision_score(y_test, v5h_test)
print(f"\n  v5h alone on test: PR-AUC={pr_v5h_test:.4f}")

# Paired bootstrap delta
delta_boot = np.empty(B)
for b in range(B):
    idx = np.random.choice(n_test, n_test, replace=True)
    if y_test[idx].sum() < 5:
        delta_boot[b] = np.nan
        continue
    pr_a = average_precision_score(y_test[idx], p_test[idx])
    pr_b = average_precision_score(y_test[idx], v5h_test[idx])
    delta_boot[b] = pr_a - pr_b
delta_boot = delta_boot[~np.isnan(delta_boot)]
delta_lo, delta_hi = np.quantile(delta_boot, [0.025, 0.975])
p_gt_0 = (delta_boot > 0).mean()
print(f"\n  Stacker vs v5h paired Δ: mean={delta_boot.mean():+.4f}")
print(f"    CI=[{delta_lo:+.4f}, {delta_hi:+.4f}]  P(Δ>0)={p_gt_0:.4f}")

# 10. Save audit JSON
audit = {
    "cycle": "58D_stacking_metalearner",
    "script": "200_cycle58d_stacking_metalearner.py",
    "generated_at": datetime.now().isoformat(),
    "n_representatives": len(keys),
    "representatives": keys,
    "n_dates_total": len(merged),
    "n_train": len(X_train),
    "n_test": len(X_test),
    "train_period": [str(dates_train[0]), str(dates_train[-1])],
    "test_period": [str(dates_test[0]), str(dates_test[-1])],
    "baselines": {
        "simple_mean_pr_auc_test": float(pr_simple),
        "v5h_alone_pr_auc_test": float(pr_v5h_test),
    },
    "ridge_stacker": {
        "C_best": float(best_C),
        "val_pr_auc_grid": {str(c): float(v) for c, v in val_results.items()},
        "pr_auc_test": float(pr_meta),
        "coefficients": dict(zip(keys, clf_best.coef_[0].tolist())),
        "intercept": float(clf_best.intercept_[0]),
        "bootstrap_ci": [
            float(np.quantile(pr_boot, 0.025)),
            float(np.quantile(pr_boot, 0.975)),
        ],
        "bootstrap_mean": float(pr_boot.mean()),
    },
    "vs_v5h": {
        "delta_mean": float(delta_boot.mean()),
        "delta_ci": [float(delta_lo), float(delta_hi)],
        "p_gt_0": float(p_gt_0),
        "significance": (
            "SIG_POSITIVE" if delta_lo > 0 else
            "SIG_NEGATIVE" if delta_hi < 0 else
            "NOT_SIG"
        ),
    },
    "verdict": (
        "STACKING_IMPROVES_OVER_BEST_BASE" if delta_lo > 0 else
        "STACKING_INFERIOR_TO_BEST_BASE" if delta_hi < 0 else
        "STACKING_EQUIVALENT_TO_BEST_BASE_NOT_SIG"
    ),
}
out_path = OUT_DIR / "cycle58d_stacking_metalearner.json"
out_path.write_text(json.dumps(audit, indent=2, ensure_ascii=False))
print(f"\n[{datetime.now():%H:%M:%S}] Saved: {out_path}")
print(f"  Verdict: {audit['verdict']}")
