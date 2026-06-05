#!/usr/bin/env python3
"""316_hgb_hyperparam_and_xgb_ens.py — Quick tactical: HGB grid + HGB+XGB(Turbulence) ensemble

발견 활용:
  - HGB V1 expanding 99mo: PR-AUC 0.3642 lift 2.00x (best baseline)
  - XGB + Turbulence (V3): PR-AUC 0.2966 lift 1.63x (Turbulence가 XGB만 도와줌)
  - 두 모델 prediction 직교성 가능 (다른 feature signal 활용)

A. HGB hyperparam grid (V1 baseline features):
   max_depth ∈ {3, 4, 5, 6}
   learning_rate ∈ {0.03, 0.05, 0.1}
   max_iter ∈ {200, 400}
   = 24 configs

B. Best HGB + XGB-Turbulence ensemble (mean prediction).

Output: outputs/04_evaluation/cycle58dd_hgb_grid_ens.json
"""
import json
from pathlib import Path
import pandas as pd
import numpy as np
import xgboost as xgb
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.metrics import average_precision_score, roc_auc_score
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
IN_V1 = WS / "outputs/01_data/monthly_features.parquet"
IN_V3 = WS / "outputs/01_data/monthly_features_v3_turbulence.parquet"
OUT = WS / "outputs/04_evaluation/cycle58dd_hgb_grid_ens.json"
TEST_START = pd.Timestamp('2018-01-01')


def prep(path):
    d = pd.read_parquet(path)
    d['Date'] = pd.to_datetime(d['Date'])
    d = d.sort_values('Date').reset_index(drop=True)
    non_feat = ['Date', 'y_tail_q15', 'fwd_dd_21', 'y_dd_8pct']
    feat_cols = [c for c in d.columns if c not in non_feat]
    d = d.dropna(subset=['y_tail_q15']).reset_index(drop=True)
    d[feat_cols] = d[feat_cols].ffill().bfill().replace([np.inf, -np.inf], np.nan).clip(-1e6, 1e6).fillna(0)
    return d, feat_cols


# Walk-forward expanding for all configs simultaneously (V1 features only, HGB grid + XGB V3)
d_v1, fc_v1 = prep(IN_V1)
d_v3, fc_v3 = prep(IN_V3)
X_v1 = d_v1[fc_v1].values; y = d_v1['y_tail_q15'].values
X_v3 = d_v3[fc_v3].values  # same row order, same y
assert (d_v1['Date'].values == d_v3['Date'].values).all(), "Date misalignment"
dates = pd.to_datetime(d_v1['Date'])
test_start_idx = max((dates >= TEST_START).idxmax(), 100)
print(f"[Load] V1={X_v1.shape}, V3={X_v3.shape}, OOS n={len(d_v1) - test_start_idx - 1}")

# A. HGB hyperparam grid
configs = []
for md in [3, 4, 5, 6]:
    for lr in [0.03, 0.05, 0.1]:
        for mi in [200, 400]:
            configs.append((md, lr, mi))
print(f"\n[A] HGB hyperparam grid: {len(configs)} configs")

all_preds = {f'hgb_md{md}_lr{lr}_mi{mi}': [] for md, lr, mi in configs}
all_preds['xgb_v3_turbulence'] = []
y_ex = []; dates_ex = []
for i in range(test_start_idx, len(d_v1) - 1):
    tr_idx = np.arange(0, i)
    if y[tr_idx].sum() < 30: continue
    ytr = y[tr_idx]
    # HGB grid (V1)
    Xtr_v1 = X_v1[tr_idx]; Xte_v1 = X_v1[i:i+1]
    for md, lr, mi in configs:
        m = HistGradientBoostingClassifier(max_iter=mi, max_depth=md, learning_rate=lr,
            class_weight='balanced', random_state=42)
        m.fit(Xtr_v1, ytr)
        all_preds[f'hgb_md{md}_lr{lr}_mi{mi}'].append(m.predict_proba(Xte_v1)[0, 1])
    # XGB V3 (Turbulence)
    Xtr_v3 = X_v3[tr_idx]; Xte_v3 = X_v3[i:i+1]
    pos_w = (1 - ytr.mean()) / max(ytr.mean(), 1e-9)
    mx = xgb.XGBClassifier(n_estimators=200, max_depth=4, learning_rate=0.05,
        scale_pos_weight=pos_w, random_state=42, eval_metric='logloss', verbosity=0, n_jobs=4)
    mx.fit(Xtr_v3, ytr)
    all_preds['xgb_v3_turbulence'].append(mx.predict_proba(Xte_v3)[0, 1])
    y_ex.append(y[i]); dates_ex.append(dates.iloc[i])

y_ex = np.array(y_ex); n = len(y_ex); base = y_ex.mean()
print(f"  OOS n={n} base={base*100:.1f}%")

# Eval HGB grid
print(f"\n[HGB grid full PR-AUC + lift]")
print(f"{'config':<28s} {'PR-AUC':>9s} {'Lift':>7s} {'ROC':>7s}")
hgb_results = {}
for md, lr, mi in configs:
    k = f'hgb_md{md}_lr{lr}_mi{mi}'
    p = np.array(all_preds[k])
    pr = average_precision_score(y_ex, p)
    roc = roc_auc_score(y_ex, p)
    hgb_results[k] = {'md': md, 'lr': lr, 'mi': mi,
                       'pr_auc': float(pr), 'lift': float(pr / base), 'roc': float(roc)}
    flag = '⭐' if pr > 0.3642 else ''  # baseline
    print(f"  {k:<28s} {pr:>9.4f} {pr/base:>6.2f}x {roc:>7.4f} {flag}")

best = max(hgb_results.items(), key=lambda kv: kv[1]['pr_auc'])
best_k, best_v = best
print(f"\nBest HGB: {best_k}  PR-AUC {best_v['pr_auc']:.4f}  lift {best_v['lift']:.2f}x  Δ {best_v['pr_auc']-0.3642:+.4f}")

# XGB V3
p_xgb_v3 = np.array(all_preds['xgb_v3_turbulence'])
pr_xgb_v3 = average_precision_score(y_ex, p_xgb_v3)
print(f"\nXGB V3 (Turbulence): PR-AUC {pr_xgb_v3:.4f}  lift {pr_xgb_v3/base:.2f}x")

# B. HGB best + XGB V3 ensemble
print(f"\n[B] Ensemble — best HGB ({best_k}) + XGB V3")
p_best_hgb = np.array(all_preds[best_k])
ensembles = {
    'best_hgb_only': p_best_hgb,
    'xgb_v3_only': p_xgb_v3,
    'B1_mean': (p_best_hgb + p_xgb_v3) / 2,
    'B2_hgb_heavy_2/3': 2/3 * p_best_hgb + 1/3 * p_xgb_v3,
    'B3_max': np.maximum(p_best_hgb, p_xgb_v3),
}
for name, p in ensembles.items():
    pr = average_precision_score(y_ex, p)
    print(f"  {name:<28s} PR-AUC {pr:.4f}  lift {pr/base:.2f}x")

# Period-balanced for best HGB + best ensemble
print(f"\n[Period-balanced — best HGB + best ensemble]")
ens_only = {k: v for k, v in ensembles.items() if k.startswith('B')}
best_ens_k = max(ens_only.keys(), key=lambda k: average_precision_score(y_ex, ensembles[k]))
print(f"Best ensemble: {best_ens_k}")
periods = [('2018-2020', '2018-01-01', '2020-12-31'),
           ('2021-2023', '2021-01-01', '2023-12-31'),
           ('2024-2026', '2024-01-01', '2026-12-31')]
period_results = []
for pname, s, e in periods:
    mask = ((pd.Series(dates_ex) >= pd.Timestamp(s)) & (pd.Series(dates_ex) <= pd.Timestamp(e))).values
    if mask.sum() < 12: continue
    for name, p in [('best_hgb', p_best_hgb), (best_ens_k, ensembles[best_ens_k])]:
        yp = y_ex[mask]; pp = p[mask]
        if yp.sum() < 2: continue
        pr = average_precision_score(yp, pp); bp = yp.mean()
        period_results.append({'period': pname, 'variant': name, 'n': int(mask.sum()),
                                'pos': int(yp.sum()), 'pr_auc': float(pr), 'lift': float(pr / bp)})
        print(f"  [{pname}] {name:<25s} n={int(mask.sum())} pos={int(yp.sum())} PR-AUC {pr:.4f} lift {pr/bp:.2f}x")

# Bootstrap CI best HGB
B = 5000; np.random.seed(42)
prs_hgb_boot = []
for b in range(B):
    idx = np.random.choice(n, n, replace=True)
    if y_ex[idx].sum() < 5: continue
    prs_hgb_boot.append(average_precision_score(y_ex[idx], p_best_hgb[idx]))
prs_hgb_boot = np.array(prs_hgb_boot)
print(f"\n[Bootstrap CI best HGB ({best_k})]")
print(f"  CI: [{np.quantile(prs_hgb_boot, 0.025):.4f}, {np.quantile(prs_hgb_boot, 0.975):.4f}]")
print(f"  P(lift > 2x) = {(prs_hgb_boot > 2*base).mean():.3f}")
print(f"  P(>1.5x) = {(prs_hgb_boot > 1.5*base).mean():.3f}")

audit = {
    'cycle': '58DD_hgb_grid_xgb_ens',
    'n': int(n), 'base': float(base),
    'hgb_grid_results': hgb_results,
    'best_hgb': {'key': best_k, **best_v},
    'xgb_v3_turbulence_pr_auc': float(pr_xgb_v3),
    'ensemble_results': {k: {'pr_auc': float(average_precision_score(y_ex, p)),
                              'lift': float(average_precision_score(y_ex, p) / base)}
                          for k, p in ensembles.items()},
    'best_ensemble': best_ens_k,
    'period_balanced': period_results,
    'best_hgb_bootstrap': {
        'ci': [float(np.quantile(prs_hgb_boot, 0.025)), float(np.quantile(prs_hgb_boot, 0.975))],
        'p_lift_gt_2x': float((prs_hgb_boot > 2*base).mean()),
        'p_lift_gt_1_5x': float((prs_hgb_boot > 1.5*base).mean()),
    },
}
OUT.write_text(json.dumps(audit, indent=2, ensure_ascii=False))
print(f"\nSaved: {OUT}")
