#!/usr/bin/env python3
"""306_monthly_focal_xgb_sweep.py — Phase 1.1 후속 sweep

305 결과: α=0.25, γ=2.0 → Δ -0.018 (focal worse).
도훈 audit 정신: 단일 hyperparam settling 전 sweep 의무 — focal Robust 검증.

Sweep: α ∈ {0.25, 0.50, 0.75} × γ ∈ {0.5, 1.0, 2.0} = 9 configs.
Walk-forward expanding monthly (99mo same as 305).
Bootstrap CI per config. Best vs baseline 비교.

Output: outputs/04_evaluation/cycle58dd_focal_xgb_sweep.json
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
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
IN = WS / "outputs/01_data/monthly_features.parquet"
OUT = WS / "outputs/04_evaluation/cycle58dd_focal_xgb_sweep.json"
TEST_START = pd.Timestamp('2018-01-01')


def focal_weights(p, y, alpha, gamma):
    p = np.clip(p, 1e-7, 1 - 1e-7)
    pt = np.where(y == 1, p, 1 - p)
    at = np.where(y == 1, alpha, 1 - alpha)
    return at * (1 - pt) ** gamma


def train_focal_xgb(X_tr, y_tr, alpha, gamma, random_state=42):
    pos_w = (1 - y_tr.mean()) / max(y_tr.mean(), 1e-9)
    probe = xgb.XGBClassifier(n_estimators=200, max_depth=4, learning_rate=0.05,
        scale_pos_weight=pos_w, random_state=random_state,
        eval_metric='logloss', verbosity=0, n_jobs=4)
    probe.fit(X_tr, y_tr)
    p_probe = probe.predict_proba(X_tr)[:, 1]
    fw = focal_weights(p_probe, y_tr, alpha=alpha, gamma=gamma)
    base_w = np.where(y_tr == 1, pos_w, 1.0)
    final_w = fw * base_w
    final_w = final_w * (len(final_w) / final_w.sum())
    final = xgb.XGBClassifier(n_estimators=200, max_depth=4, learning_rate=0.05,
        random_state=random_state, eval_metric='logloss', verbosity=0, n_jobs=4)
    final.fit(X_tr, y_tr, sample_weight=final_w)
    return final


def train_baseline_xgb(X_tr, y_tr, random_state=42):
    pos_w = (1 - y_tr.mean()) / max(y_tr.mean(), 1e-9)
    m = xgb.XGBClassifier(n_estimators=200, max_depth=4, learning_rate=0.05,
        scale_pos_weight=pos_w, random_state=random_state,
        eval_metric='logloss', verbosity=0, n_jobs=4)
    m.fit(X_tr, y_tr)
    return m


# Load
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
test_start_idx = max((dates >= TEST_START).idxmax(), 100)
print(f"[Load] {len(d)} months × {len(feat_cols)} features, OOS n={len(d) - test_start_idx - 1}")

# Build baseline + each focal once via walk-forward expanding (reuse predictions)
configs = []
for alpha in [0.25, 0.50, 0.75]:
    for gamma in [0.5, 1.0, 2.0]:
        configs.append((alpha, gamma))
print(f"Sweep: {len(configs)} configs (α × γ)")

all_preds = {f'focal_a{a}_g{g}': [] for a, g in configs}
all_preds['baseline'] = []
y_ex = []
dates_ex = []
for i in range(test_start_idx, len(d) - 1):
    tr_idx = np.arange(0, i)
    if y[tr_idx].sum() < 30: continue
    Xtr = X[tr_idx]; ytr = y[tr_idx]
    Xte = X[i:i+1]
    # Baseline
    mb = train_baseline_xgb(Xtr, ytr)
    all_preds['baseline'].append(mb.predict_proba(Xte)[0, 1])
    # Each focal config
    for alpha, gamma in configs:
        mf = train_focal_xgb(Xtr, ytr, alpha=alpha, gamma=gamma)
        all_preds[f'focal_a{alpha}_g{gamma}'].append(mf.predict_proba(Xte)[0, 1])
    y_ex.append(y[i])
    dates_ex.append(dates.iloc[i])

y_ex = np.array(y_ex)
n = len(y_ex)
base = y_ex.mean()
print(f"  OOS n={n} months, base rate {base*100:.1f}%")

# Per-config eval
print("\n" + "="*60)
print(f"{'Config':<20s} {'PR-AUC':>9s} {'Lift':>7s} {'ROC':>7s} {'Δ vs base':>11s}")
print("="*60)
results = {}
pr_base = average_precision_score(y_ex, np.array(all_preds['baseline']))
results['baseline'] = {'pr_auc': float(pr_base), 'lift': float(pr_base / base),
                       'roc': float(roc_auc_score(y_ex, np.array(all_preds['baseline'])))}
print(f"{'baseline':<20s} {pr_base:>9.4f} {pr_base/base:>6.2f}x {results['baseline']['roc']:>7.4f} {'(ref)':>11s}")

for alpha, gamma in configs:
    k = f'focal_a{alpha}_g{gamma}'
    p = np.array(all_preds[k])
    pr = average_precision_score(y_ex, p)
    roc = roc_auc_score(y_ex, p)
    delta = pr - pr_base
    results[k] = {'alpha': alpha, 'gamma': gamma, 'pr_auc': float(pr),
                  'lift': float(pr / base), 'roc': float(roc), 'delta': float(delta)}
    flag = '⭐' if delta > 0 else ''
    print(f"{k:<20s} {pr:>9.4f} {pr/base:>6.2f}x {roc:>7.4f} {delta:>+11.4f} {flag}")

# Best focal config
best = max([(k, v) for k, v in results.items() if 'focal' in k], key=lambda kv: kv[1]['pr_auc'])
best_k, best_v = best
print(f"\nBest focal: {best_k}  PR-AUC {best_v['pr_auc']:.4f}  Δ {best_v['delta']:+.4f}")

# Bootstrap CI for best vs baseline (paired)
print(f"\n=== Bootstrap CI paired (B=5000) — best ({best_k}) vs baseline ===")
B = 5000
np.random.seed(42)
prs_base = []; prs_best = []; deltas = []
p_base = np.array(all_preds['baseline'])
p_best = np.array(all_preds[best_k])
for b in range(B):
    idx = np.random.choice(n, n, replace=True)
    if y_ex[idx].sum() < 5: continue
    prs_base.append(average_precision_score(y_ex[idx], p_base[idx]))
    prs_best.append(average_precision_score(y_ex[idx], p_best[idx]))
    deltas.append(prs_best[-1] - prs_base[-1])
prs_base = np.array(prs_base); prs_best = np.array(prs_best); deltas = np.array(deltas)
print(f"  Baseline CI: [{np.quantile(prs_base, 0.025):.4f}, {np.quantile(prs_base, 0.975):.4f}]")
print(f"  Best CI:     [{np.quantile(prs_best, 0.025):.4f}, {np.quantile(prs_best, 0.975):.4f}]")
print(f"  Delta CI:    [{np.quantile(deltas, 0.025):+.4f}, {np.quantile(deltas, 0.975):+.4f}]")
print(f"  P(best > baseline) = {(deltas > 0).mean():.3f}")

# Save
audit = {
    'cycle': '58DD_focal_xgb_sweep_phase1.1',
    'n_train_initial': int(test_start_idx),
    'n_test_months': int(n),
    'base_rate': float(base),
    'configs': [{'alpha': a, 'gamma': g} for a, g in configs],
    'results': results,
    'best_focal': {'key': best_k, **best_v},
    'best_vs_baseline_paired_bootstrap': {
        'baseline_ci': [float(np.quantile(prs_base, 0.025)), float(np.quantile(prs_base, 0.975))],
        'best_ci': [float(np.quantile(prs_best, 0.025)), float(np.quantile(prs_best, 0.975))],
        'delta_ci': [float(np.quantile(deltas, 0.025)), float(np.quantile(deltas, 0.975))],
        'p_best_gt_baseline': float((deltas > 0).mean()),
    },
}
OUT.write_text(json.dumps(audit, indent=2, ensure_ascii=False))
print(f"\nSaved: {OUT}")
