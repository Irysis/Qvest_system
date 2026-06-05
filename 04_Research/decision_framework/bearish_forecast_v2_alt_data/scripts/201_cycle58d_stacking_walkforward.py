#==============================================================================
# 201_cycle58d_stacking_walkforward.py
#
# 200_cycle58d_stacking_metalearner.py 보강:
#   1. Walk-forward CV (same 5-fold structure as base models) — chronological
#      brittleness 해소
#   2. XGB stacker (LightGBM 대체)
#   3. Median ensemble baseline (Ridge 대신 robust)
#   4. Trim mean ensemble (top/bottom 1 제거)
#   5. Per-fold + overall PR-AUC + bootstrap
#
# Goal: stacking은 OOF에서 evaluate해야 fair (chronological은 regime drift bias).
# CPU only.
#==============================================================================

import json
import warnings
import numpy as np
import pandas as pd
from pathlib import Path
from datetime import datetime

import pyarrow.parquet as pq
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score
import xgboost as xgb

warnings.filterwarnings("ignore", category=FutureWarning)
warnings.filterwarnings("ignore", category=UserWarning)

PROJECT_ROOT = Path(
    "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
)
WS = (PROJECT_ROOT /
      "04_Research/decision_framework/bearish_forecast_v2_alt_data")
MODELS = WS / "outputs/03_models"
OUT_DIR = WS / "outputs/04_evaluation"

REPS = {
    "v5f_FIXED2_C1": MODELS / "cycle57b_q15_BBVA_fixed" /
        "predictions_53I_v5f_FIXED2_mean5_y_tail_q15.parquet",
    "v3_patch7_C2": MODELS / "cycle56a_q15_strict_PIT" /
        "predictions_54A_v3_patch7_mean5_y_tail_q15.parquet",
    "v3_patch7_FIXED2_C3": MODELS / "cycle57b_q15_BBVA_fixed" /
        "predictions_54A_v3_patch7_FIXED2_mean5_y_tail_q15.parquet",
    "v5g_cross_market_C4": MODELS / "cycle58c_v5g_15seed" /
        "predictions_53I_v5g_cross_market_mean15_y_tail_q15.parquet",
    "v5h_interactions_C5": MODELS / "cycle58c_v5h_5seed" /
        "predictions_53I_v5h_interactions_mean5_y_tail_q15.parquet",
}

print(f"[{datetime.now():%H:%M:%S}] Loading 5 representatives...")
dfs = {}
for name, path in REPS.items():
    t = pq.read_table(path)
    df = t.to_pandas()
    df["Date"] = pd.to_datetime(df["Date"]).dt.date
    p_col = "p_mean15" if "p_mean15" in df.columns else "p_mean5"
    df = df[df["split"] == "oos"][["Date", p_col, "y"]].copy()
    df = df.rename(columns={p_col: f"p_{name}"})
    df = df.sort_values("Date").drop_duplicates(subset=["Date"])
    dfs[name] = df

keys = list(dfs.keys())
merged = dfs[keys[0]].copy()
for k in keys[1:]:
    df_k = dfs[k][["Date", f"p_{k}"]]
    merged = merged.merge(df_k, on="Date", how="inner")
print(f"  Merged: n_dates={len(merged)}")

y = merged["y"].values
feat_cols = [f"p_{k}" for k in keys]
X = merged[feat_cols].values
dates = pd.to_datetime(merged["Date"]).values

# Simple ensemble baselines (no stacking, just combinations)
print(f"\n[{datetime.now():%H:%M:%S}] === Ensemble baselines on FULL OOS ===")
pr_simple = average_precision_score(y, X.mean(axis=1))
pr_median = average_precision_score(y, np.median(X, axis=1))
# Trim mean: remove min + max per row
X_sorted = np.sort(X, axis=1)
trim_mean = X_sorted[:, 1:-1].mean(axis=1)
pr_trim = average_precision_score(y, trim_mean)
# v5h alone
pr_v5h = average_precision_score(y, X[:, keys.index("v5h_interactions_C5")])
print(f"  Simple mean (5):     PR-AUC={pr_simple:.4f}")
print(f"  Median (5):          PR-AUC={pr_median:.4f}")
print(f"  Trim mean (3 inner): PR-AUC={pr_trim:.4f}")
print(f"  v5h alone (best base): PR-AUC={pr_v5h:.4f}")

# 5-fold walk-forward CV (chronological)
print(f"\n[{datetime.now():%H:%M:%S}] === 5-fold Walk-Forward Stacking ===")
n = len(merged)
fold_size = n // 5

# Fold definitions (expanding train, fixed-size val)
folds = []
for fold in range(5):
    val_start = fold * fold_size
    val_end = (fold + 1) * fold_size if fold < 4 else n
    train_idx = list(range(0, val_start))
    val_idx = list(range(val_start, val_end))
    folds.append((train_idx, val_idx, fold))

# Skip fold 0 (no train) — use folds 1-4 with expanding train
ridge_preds = np.full(n, np.nan)
xgb_preds = np.full(n, np.nan)

for train_idx, val_idx, fold in folds:
    if len(train_idx) < 100:  # skip fold 0
        continue
    X_tr = X[train_idx]
    y_tr = y[train_idx]
    X_val = X[val_idx]
    y_val = y[val_idx]

    # Ridge
    ridge = LogisticRegression(
        C=0.1, penalty="l2", solver="lbfgs", max_iter=2000,
        class_weight="balanced", random_state=42,
    )
    ridge.fit(X_tr, y_tr)
    ridge_preds[val_idx] = ridge.predict_proba(X_val)[:, 1]

    # XGB
    pos_weight = (1 - y_tr.mean()) / max(y_tr.mean(), 1e-9)
    xmdl = xgb.XGBClassifier(
        n_estimators=100, max_depth=3, learning_rate=0.05,
        scale_pos_weight=pos_weight, random_state=42,
        eval_metric="logloss", verbosity=0,
    )
    xmdl.fit(X_tr, y_tr)
    xgb_preds[val_idx] = xmdl.predict_proba(X_val)[:, 1]

    fold_pr_ridge = average_precision_score(
        y_val, ridge_preds[val_idx]
    )
    fold_pr_xgb = average_precision_score(
        y_val, xgb_preds[val_idx]
    )
    fold_pr_simple = average_precision_score(
        y_val, X[val_idx].mean(axis=1)
    )
    fold_pr_v5h = average_precision_score(
        y_val, X[val_idx, keys.index("v5h_interactions_C5")]
    )
    print(f"  Fold {fold} ({dates[val_idx[0]]} ~ "
          f"{dates[val_idx[-1]]}):"
          f"  n={len(val_idx)} pos={y_val.mean():.1%}")
    print(f"    simple={fold_pr_simple:.4f} v5h={fold_pr_v5h:.4f}"
          f" ridge={fold_pr_ridge:.4f} xgb={fold_pr_xgb:.4f}")

# Overall OOF PR-AUC (excluding fold 0 with no preds)
valid_mask = ~np.isnan(ridge_preds)
pr_ridge_oof = average_precision_score(y[valid_mask], ridge_preds[valid_mask])
pr_xgb_oof = average_precision_score(y[valid_mask], xgb_preds[valid_mask])
pr_simple_oof = average_precision_score(
    y[valid_mask], X[valid_mask].mean(axis=1)
)
pr_v5h_oof = average_precision_score(
    y[valid_mask], X[valid_mask, keys.index("v5h_interactions_C5")]
)
print(f"\n  === OOF (fold 1-4 only) ===")
print(f"  Simple mean:  PR-AUC={pr_simple_oof:.4f}")
print(f"  v5h alone:    PR-AUC={pr_v5h_oof:.4f}")
print(f"  Ridge stacker:PR-AUC={pr_ridge_oof:.4f}")
print(f"  XGB stacker:  PR-AUC={pr_xgb_oof:.4f}")

# Bootstrap CIs (paired)
print(f"\n[{datetime.now():%H:%M:%S}] === Bootstrap (B=1000) ===")
B = 1000
np.random.seed(42)
y_v = y[valid_mask]
v5h_v = X[valid_mask, keys.index("v5h_interactions_C5")]
n_v = len(y_v)

def boot_pr(p, n_pos_min=5):
    out = np.empty(B)
    for b in range(B):
        idx = np.random.choice(n_v, n_v, replace=True)
        if y_v[idx].sum() < n_pos_min:
            out[b] = np.nan
            continue
        out[b] = average_precision_score(y_v[idx], p[idx])
    return out[~np.isnan(out)]

ridge_boot = boot_pr(ridge_preds[valid_mask])
xgb_boot = boot_pr(xgb_preds[valid_mask])
v5h_boot = boot_pr(v5h_v)

def ci(b, q1=0.025, q2=0.975):
    return float(np.quantile(b, q1)), float(np.quantile(b, q2))

print(f"  v5h:    PR-AUC={v5h_boot.mean():.4f} CI={ci(v5h_boot)}")
print(f"  Ridge:  PR-AUC={ridge_boot.mean():.4f} CI={ci(ridge_boot)}")
print(f"  XGB:    PR-AUC={xgb_boot.mean():.4f} CI={ci(xgb_boot)}")

# Paired delta (ridge vs v5h, xgb vs v5h)
def paired_delta(p1, p2, n_pos_min=5):
    out = np.empty(B)
    for b in range(B):
        idx = np.random.choice(n_v, n_v, replace=True)
        if y_v[idx].sum() < n_pos_min:
            out[b] = np.nan
            continue
        pa = average_precision_score(y_v[idx], p1[idx])
        pb = average_precision_score(y_v[idx], p2[idx])
        out[b] = pa - pb
    return out[~np.isnan(out)]

np.random.seed(42)
d_ridge = paired_delta(ridge_preds[valid_mask], v5h_v)
np.random.seed(42)
d_xgb = paired_delta(xgb_preds[valid_mask], v5h_v)
print(f"\n  Δ(Ridge - v5h): mean={d_ridge.mean():+.4f}"
      f"  CI={ci(d_ridge)}  P(Δ>0)={(d_ridge>0).mean():.4f}")
print(f"  Δ(XGB   - v5h): mean={d_xgb.mean():+.4f}"
      f"  CI={ci(d_xgb)}  P(Δ>0)={(d_xgb>0).mean():.4f}")

# Save audit
audit = {
    "cycle": "58D_stacking_walkforward",
    "script": "201_cycle58d_stacking_walkforward.py",
    "generated_at": datetime.now().isoformat(),
    "n_representatives": len(keys),
    "representatives": keys,
    "n_dates_total": int(n),
    "n_oof_dates": int(valid_mask.sum()),
    "full_oos_baselines": {
        "simple_mean_5": float(pr_simple),
        "median_5": float(pr_median),
        "trim_mean_3": float(pr_trim),
        "v5h_alone": float(pr_v5h),
    },
    "oof_walkforward": {
        "simple_mean": float(pr_simple_oof),
        "v5h_alone": float(pr_v5h_oof),
        "ridge_stacker": float(pr_ridge_oof),
        "xgb_stacker": float(pr_xgb_oof),
    },
    "bootstrap_ci": {
        "v5h": [float(v5h_boot.mean()), *ci(v5h_boot)],
        "ridge": [float(ridge_boot.mean()), *ci(ridge_boot)],
        "xgb": [float(xgb_boot.mean()), *ci(xgb_boot)],
    },
    "paired_delta_vs_v5h": {
        "ridge": {
            "mean": float(d_ridge.mean()),
            "CI": list(ci(d_ridge)),
            "p_gt_0": float((d_ridge > 0).mean()),
        },
        "xgb": {
            "mean": float(d_xgb.mean()),
            "CI": list(ci(d_xgb)),
            "p_gt_0": float((d_xgb > 0).mean()),
        },
    },
    "verdict": (
        "STACKING_BEATS_BEST_BASE_SIG" if (
            d_xgb.mean() > 0 and ci(d_xgb)[0] > 0
        ) else
        "STACKING_NEUTRAL_NOT_SIG" if (
            -0.01 < d_xgb.mean() < 0.01
        ) else
        "STACKING_INFERIOR_OR_INCONCLUSIVE"
    ),
}
out_path = OUT_DIR / "cycle58d_stacking_walkforward.json"
out_path.write_text(json.dumps(audit, indent=2, ensure_ascii=False))
print(f"\n[{datetime.now():%H:%M:%S}] Saved: {out_path}")
print(f"  Verdict: {audit['verdict']}")
