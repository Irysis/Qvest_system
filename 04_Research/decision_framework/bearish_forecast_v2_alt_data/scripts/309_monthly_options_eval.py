#!/usr/bin/env python3
"""309_monthly_options_eval.py — Phase 1.2 robust eval

Walk-forward expanding 99mo, monthly_features.parquet (v1, 62 cols) vs
monthly_features_v2_options.parquet (v2, 62+8=70 cols).

3 model variants per features:
  baseline_xgb  : XGB scale_pos_weight
  ridge         : LogReg L2 class_weight=balanced
  hgb           : HistGradientBoosting class_weight=balanced
  top3_ens      : (xgb + ridge + hgb) / 3

Output: outputs/04_evaluation/cycle58dd_options_eval.json
"""
import json
from pathlib import Path
import pandas as pd
import numpy as np
import xgboost as xgb
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.metrics import average_precision_score, roc_auc_score
from sklearn.preprocessing import StandardScaler
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
DATA_DIR = WS / "outputs/01_data"
IN_V1 = DATA_DIR / "monthly_features.parquet"
IN_V2 = DATA_DIR / "monthly_features_v2_options.parquet"
OUT = WS / "outputs/04_evaluation/cycle58dd_options_eval.json"

TEST_START = pd.Timestamp('2018-01-01')


def prepare(d):
    d = d.copy()
    d['Date'] = pd.to_datetime(d['Date'])
    d = d.sort_values('Date').reset_index(drop=True)
    non_feat = ['Date', 'y_tail_q15', 'fwd_dd_21', 'y_dd_8pct']
    feat_cols = [c for c in d.columns if c not in non_feat]
    d = d.dropna(subset=['y_tail_q15'])
    d[feat_cols] = d[feat_cols].ffill().bfill().replace([np.inf, -np.inf], np.nan).clip(-1e6, 1e6).fillna(0)
    return d, feat_cols


def walkforward_eval(d, feat_cols, label="?"):
    X = d[feat_cols].values; y = d['y_tail_q15'].values
    dates = pd.to_datetime(d['Date'])
    test_start_idx = max((dates >= TEST_START).idxmax(), 100)
    print(f"\n[{label}] features={len(feat_cols)}  OOS start={dates.iloc[test_start_idx].date()}")

    p_xgb = []; p_rid = []; p_hgb = []
    y_ex = []; dates_ex = []
    for i in range(test_start_idx, len(d) - 1):
        tr_idx = np.arange(0, i)
        if y[tr_idx].sum() < 30: continue
        Xtr = X[tr_idx]; ytr = y[tr_idx]
        Xte = X[i:i+1]
        pos_w = (1 - ytr.mean()) / max(ytr.mean(), 1e-9)
        # XGB
        mx = xgb.XGBClassifier(n_estimators=200, max_depth=4, learning_rate=0.05,
            scale_pos_weight=pos_w, random_state=42,
            eval_metric='logloss', verbosity=0, n_jobs=4)
        mx.fit(Xtr, ytr); p_xgb.append(mx.predict_proba(Xte)[0, 1])
        # Ridge
        sc = StandardScaler(); Xtr_sc = sc.fit_transform(Xtr); Xte_sc = sc.transform(Xte)
        mr = LogisticRegression(C=0.5, penalty='l2', max_iter=2000,
            class_weight='balanced', solver='lbfgs', random_state=42)
        mr.fit(Xtr_sc, ytr); p_rid.append(mr.predict_proba(Xte_sc)[0, 1])
        # HGB
        mh = HistGradientBoostingClassifier(max_iter=200, max_depth=4, learning_rate=0.05,
            class_weight='balanced', random_state=42)
        mh.fit(Xtr, ytr); p_hgb.append(mh.predict_proba(Xte)[0, 1])

        y_ex.append(y[i])
        dates_ex.append(dates.iloc[i])

    y_ex = np.array(y_ex)
    p_xgb = np.array(p_xgb); p_rid = np.array(p_rid); p_hgb = np.array(p_hgb)
    p_ens = (p_xgb + p_rid + p_hgb) / 3
    base = y_ex.mean()
    n = len(y_ex)
    print(f"  OOS n={n} months, base rate {base*100:.1f}%")
    results = {}
    for name, p in [('xgb', p_xgb), ('ridge', p_rid), ('hgb', p_hgb), ('top3', p_ens)]:
        pr = average_precision_score(y_ex, p)
        roc = roc_auc_score(y_ex, p)
        results[name] = {'pr_auc': float(pr), 'lift': float(pr / base), 'roc': float(roc)}
        print(f"    {name:<8s} PR-AUC {pr:.4f}  lift {pr/base:.2f}x  ROC {roc:.4f}")
    results['n_test_months'] = int(n)
    results['base_rate'] = float(base)
    # Also return raw preds for delta bootstrap
    return results, p_xgb, p_rid, p_hgb, p_ens, y_ex


# Eval v1 and v2
d1 = pd.read_parquet(IN_V1)
d2 = pd.read_parquet(IN_V2)
d1_p, fc1 = prepare(d1)
d2_p, fc2 = prepare(d2)

res_v1, p1_xgb, p1_rid, p1_hgb, p1_ens, y_ex1 = walkforward_eval(d1_p, fc1, label="V1 baseline (62)")
res_v2, p2_xgb, p2_rid, p2_hgb, p2_ens, y_ex2 = walkforward_eval(d2_p, fc2, label="V2 + options (70)")

# Bootstrap paired delta for ens
print("\n" + "="*60)
print("Bootstrap CI 95% paired (v2 ens - v1 ens) — n_boot=5000")
print("="*60)
assert np.array_equal(y_ex1, y_ex2), "y mismatch between v1 and v2 walkforward"
n = len(y_ex1)
B = 5000
np.random.seed(42)
deltas = []
prs_v1 = []; prs_v2 = []
for b in range(B):
    idx = np.random.choice(n, n, replace=True)
    if y_ex1[idx].sum() < 5: continue
    pr1 = average_precision_score(y_ex1[idx], p1_ens[idx])
    pr2 = average_precision_score(y_ex2[idx], p2_ens[idx])
    prs_v1.append(pr1); prs_v2.append(pr2); deltas.append(pr2 - pr1)
prs_v1 = np.array(prs_v1); prs_v2 = np.array(prs_v2); deltas = np.array(deltas)
print(f"  V1 ens CI: [{np.quantile(prs_v1, 0.025):.4f}, {np.quantile(prs_v1, 0.975):.4f}]")
print(f"  V2 ens CI: [{np.quantile(prs_v2, 0.025):.4f}, {np.quantile(prs_v2, 0.975):.4f}]")
print(f"  Delta CI: [{np.quantile(deltas, 0.025):+.4f}, {np.quantile(deltas, 0.975):+.4f}]")
print(f"  P(v2 > v1) = {(deltas > 0).mean():.3f}")
print(f"  P(v2 lift > 2x) = {(prs_v2 > 2*res_v2['base_rate']).mean():.3f}")
print(f"  P(v1 lift > 2x) = {(prs_v1 > 2*res_v1['base_rate']).mean():.3f}")

audit = {
    'cycle': '58DD_phase1.2_options',
    'features_v1': len(fc1),
    'features_v2': len(fc2),
    'v1_baseline': res_v1,
    'v2_with_options': res_v2,
    'paired_bootstrap_v2_vs_v1_ens': {
        'v1_ci': [float(np.quantile(prs_v1, 0.025)), float(np.quantile(prs_v1, 0.975))],
        'v2_ci': [float(np.quantile(prs_v2, 0.025)), float(np.quantile(prs_v2, 0.975))],
        'delta_ci': [float(np.quantile(deltas, 0.025)), float(np.quantile(deltas, 0.975))],
        'p_v2_gt_v1': float((deltas > 0).mean()),
    },
}
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps(audit, indent=2, ensure_ascii=False))
print(f"\nSaved: {OUT}")
