#!/usr/bin/env python3
"""305_monthly_focal_xgb_expanding.py — Plan Phase 1.1 Focal Loss

학술 anchor:
  - Lin et al. 2017 (Focal Loss, ICCV) — α=0.25, γ=2.0 표준 sparse class
  - López de Prado 2018 AFML — Meta-Labeling (binary → magnitude 2-stage)

구현: Iteratively reweighted XGBoost (focal-weighted sample weights).
  Step 1: probe XGB (standard BCE) → in-sample p_i
  Step 2: focal weights w_i = α_t (1-p_t)^γ
  Step 3: re-train XGB with sample_weight = base_class_weight * focal_weight

장점 (custom obj 대비):
  - gradient/hessian 분석 derivation 안정성 risk 0
  - XGBoost standard binary:logistic objective 활용
  - α, γ hyperparam sweep 가능 (sample weight)

Walk-forward expanding monthly OOS (same as 303 Section C, 99mo+).
Compare to baseline (non-focal): Δ PR-AUC + bootstrap CI.

Output: outputs/04_evaluation/cycle58dd_focal_xgb.json
"""
import json
from pathlib import Path
import pandas as pd
import numpy as np
import xgboost as xgb
from sklearn.metrics import average_precision_score, roc_auc_score
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = (PROJECT_ROOT /
      "04_Research/decision_framework/bearish_forecast_v2_alt_data")
IN = WS / "outputs/01_data/monthly_features.parquet"
OUT = WS / "outputs/04_evaluation/cycle58dd_focal_xgb.json"

# Focal loss params (Lin 2017 default)
FOCAL_ALPHA = 0.25
FOCAL_GAMMA = 2.0

# Walk-forward expanding monthly window
TEST_START = pd.Timestamp('2018-01-01')  # ~99mo OOS

def focal_weights(p, y, alpha=FOCAL_ALPHA, gamma=FOCAL_GAMMA):
    """Compute focal weights given predicted probabilities and labels.

    w_i = alpha_t * (1 - p_t)^gamma
    where p_t = p if y=1 else (1-p), alpha_t = alpha if y=1 else (1-alpha)
    """
    p = np.clip(p, 1e-7, 1 - 1e-7)
    pt = np.where(y == 1, p, 1 - p)
    at = np.where(y == 1, alpha, 1 - alpha)
    return at * (1 - pt) ** gamma


def train_focal_xgb(X_tr, y_tr, alpha=FOCAL_ALPHA, gamma=FOCAL_GAMMA,
                     n_estimators=200, max_depth=4, learning_rate=0.05, random_state=42):
    """Train XGB with focal loss via iteratively reweighted sample weights."""
    pos_w = (1 - y_tr.mean()) / max(y_tr.mean(), 1e-9)

    # Step 1: probe (standard BCE with class balance)
    probe = xgb.XGBClassifier(
        n_estimators=n_estimators, max_depth=max_depth, learning_rate=learning_rate,
        scale_pos_weight=pos_w, random_state=random_state,
        eval_metric='logloss', verbosity=0, n_jobs=4)
    probe.fit(X_tr, y_tr)
    p_probe = probe.predict_proba(X_tr)[:, 1]

    # Step 2: focal weights from probe predictions
    fw = focal_weights(p_probe, y_tr, alpha=alpha, gamma=gamma)
    # Combine with class balance: w_final = focal_weight * base_class_weight
    # base_class_weight: y=1 → pos_w, y=0 → 1.0
    base_w = np.where(y_tr == 1, pos_w, 1.0)
    final_w = fw * base_w
    # Normalize sum to len (stability)
    final_w = final_w * (len(final_w) / final_w.sum())

    # Step 3: re-train with focal weights (no scale_pos_weight since baked into weights)
    final = xgb.XGBClassifier(
        n_estimators=n_estimators, max_depth=max_depth, learning_rate=learning_rate,
        random_state=random_state, eval_metric='logloss', verbosity=0, n_jobs=4)
    final.fit(X_tr, y_tr, sample_weight=final_w)
    return final


def train_baseline_xgb(X_tr, y_tr, n_estimators=200, max_depth=4, learning_rate=0.05, random_state=42):
    """Baseline XGB (no focal loss, standard scale_pos_weight)."""
    pos_w = (1 - y_tr.mean()) / max(y_tr.mean(), 1e-9)
    m = xgb.XGBClassifier(
        n_estimators=n_estimators, max_depth=max_depth, learning_rate=learning_rate,
        scale_pos_weight=pos_w, random_state=random_state,
        eval_metric='logloss', verbosity=0, n_jobs=4)
    m.fit(X_tr, y_tr)
    return m


# ============================================================
# Load monthly features
# ============================================================
d = pd.read_parquet(IN)
d['Date'] = pd.to_datetime(d['Date'])
d = d.sort_values('Date').reset_index(drop=True)
non_feat = ['Date', 'y_tail_q15', 'fwd_dd_21', 'y_dd_8pct']
feat_cols = [c for c in d.columns if c not in non_feat]
d = d.dropna(subset=['y_tail_q15'])
d[feat_cols] = d[feat_cols].ffill().bfill().replace([np.inf, -np.inf], np.nan).clip(-1e6, 1e6).fillna(0)
X = d[feat_cols].values
y = d['y_tail_q15'].values
dates = pd.to_datetime(d['Date'])
print(f"[Load] {len(d)} months × {len(feat_cols)} features")
print(f"  Date range: {dates.min().date()} ~ {dates.max().date()}")
print(f"  y base rate: {y.mean()*100:.1f}%")

# Find expanding test start
test_start_idx = (dates >= TEST_START).idxmax()
start_idx = 100  # ~8 years initial train
test_start_idx = max(test_start_idx, start_idx)
print(f"  Expanding OOS start: {dates.iloc[test_start_idx].date()} (~{len(d) - test_start_idx} months)")

# ============================================================
# Walk-forward expanding monthly: baseline vs focal
# ============================================================
print("\n" + "="*60)
print(f"Walk-forward expanding (alpha={FOCAL_ALPHA}, gamma={FOCAL_GAMMA})")
print("="*60)

baseline_preds = []
focal_preds = []
y_ex = []
dates_ex = []
for i in range(test_start_idx, len(d) - 1):
    tr_idx = np.arange(0, i)
    if y[tr_idx].sum() < 30: continue
    Xtr = X[tr_idx]; ytr = y[tr_idx]
    Xte = X[i:i+1]

    # Baseline
    mb = train_baseline_xgb(Xtr, ytr)
    p_b = mb.predict_proba(Xte)[0, 1]
    baseline_preds.append(p_b)

    # Focal
    mf = train_focal_xgb(Xtr, ytr, alpha=FOCAL_ALPHA, gamma=FOCAL_GAMMA)
    p_f = mf.predict_proba(Xte)[0, 1]
    focal_preds.append(p_f)

    y_ex.append(y[i])
    dates_ex.append(dates.iloc[i])

y_ex = np.array(y_ex)
baseline_preds = np.array(baseline_preds)
focal_preds = np.array(focal_preds)
base = y_ex.mean()
print(f"  Expanding OOS n={len(y_ex)} months, base rate {base*100:.1f}%")

pr_base = average_precision_score(y_ex, baseline_preds)
pr_focal = average_precision_score(y_ex, focal_preds)
roc_base = roc_auc_score(y_ex, baseline_preds)
roc_focal = roc_auc_score(y_ex, focal_preds)

print(f"\n  Baseline XGB:   PR-AUC {pr_base:.4f}  lift {pr_base/base:.2f}x  ROC {roc_base:.4f}")
print(f"  Focal XGB:      PR-AUC {pr_focal:.4f}  lift {pr_focal/base:.2f}x  ROC {roc_focal:.4f}")
print(f"  Δ (focal-base): PR-AUC {pr_focal-pr_base:+.4f}  lift {(pr_focal-pr_base)/base:+.2f}x")

# ============================================================
# Bootstrap CI
# ============================================================
print("\n=== Bootstrap CI 95% (B=5000) ===")
B = 5000
np.random.seed(42)
n = len(y_ex)
prs_base = []
prs_focal = []
for b in range(B):
    idx = np.random.choice(n, n, replace=True)
    if y_ex[idx].sum() < 5: continue
    prs_base.append(average_precision_score(y_ex[idx], baseline_preds[idx]))
    prs_focal.append(average_precision_score(y_ex[idx], focal_preds[idx]))
prs_base = np.array(prs_base)
prs_focal = np.array(prs_focal)

# Delta distribution (paired bootstrap — same idx for base and focal)
np.random.seed(43)
delta_prs = []
for b in range(B):
    idx = np.random.choice(n, n, replace=True)
    if y_ex[idx].sum() < 5: continue
    d_b = average_precision_score(y_ex[idx], baseline_preds[idx])
    d_f = average_precision_score(y_ex[idx], focal_preds[idx])
    delta_prs.append(d_f - d_b)
delta_prs = np.array(delta_prs)
p_focal_gt_base = (delta_prs > 0).mean()

print(f"  Baseline CI: [{np.quantile(prs_base, 0.025):.4f}, {np.quantile(prs_base, 0.975):.4f}]")
print(f"  Focal CI:    [{np.quantile(prs_focal, 0.025):.4f}, {np.quantile(prs_focal, 0.975):.4f}]")
print(f"  Delta CI:    [{np.quantile(delta_prs, 0.025):+.4f}, {np.quantile(delta_prs, 0.975):+.4f}]")
print(f"  P(focal > baseline) = {p_focal_gt_base:.3f}")
print(f"  P(focal lift > 2x)  = {(prs_focal > 2*base).mean():.3f}")
print(f"  P(baseline lift > 2x) = {(prs_base > 2*base).mean():.3f}")

# ============================================================
# Save
# ============================================================
audit = {
    'cycle': '58DD_focal_xgb_phase1.1',
    'focal_alpha': FOCAL_ALPHA,
    'focal_gamma': FOCAL_GAMMA,
    'n_train_initial': int(test_start_idx),
    'n_test_months': int(len(y_ex)),
    'base_rate': float(base),
    'baseline': {
        'pr_auc': float(pr_base),
        'lift': float(pr_base / base),
        'roc_auc': float(roc_base),
        'bootstrap_ci': [float(np.quantile(prs_base, 0.025)), float(np.quantile(prs_base, 0.975))],
        'p_lift_gt_2x': float((prs_base > 2*base).mean()),
    },
    'focal': {
        'pr_auc': float(pr_focal),
        'lift': float(pr_focal / base),
        'roc_auc': float(roc_focal),
        'bootstrap_ci': [float(np.quantile(prs_focal, 0.025)), float(np.quantile(prs_focal, 0.975))],
        'p_lift_gt_2x': float((prs_focal > 2*base).mean()),
    },
    'delta_focal_vs_baseline': {
        'pr_auc_delta': float(pr_focal - pr_base),
        'lift_delta': float((pr_focal - pr_base) / base),
        'delta_bootstrap_ci': [float(np.quantile(delta_prs, 0.025)), float(np.quantile(delta_prs, 0.975))],
        'p_focal_gt_baseline': float(p_focal_gt_base),
    },
}
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps(audit, indent=2, ensure_ascii=False))
print(f"\nSaved: {OUT}")
