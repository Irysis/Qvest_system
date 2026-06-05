#!/usr/bin/env python3
"""314_hgb_y_dd_label_eval.py — Label redefine (y_dd_8pct vs y_tail_q15)

도훈 Cycle 58T 정신: y_tail_q15 endpoint label은 mid-month crash 놓침 (2024-08 -12.1% / 2025-04 -9.0%).
y_dd_8pct (forward 21d max drawdown ≤ -8%) drawdown label은 mid-month event capture.

HGB V1 expanding 99mo, label 비교:
  A: y_tail_q15 (endpoint, current baseline)
  B: y_dd_8pct  (drawdown-based, alternative)

Period-balanced focus on 2024-2026 (where y_dd_8pct captures 5 vs y_tail_q15 3 positives).

Output: outputs/04_evaluation/cycle58dd_label_redefine.json
"""
import json
from pathlib import Path
import pandas as pd
import numpy as np
import xgboost as xgb
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, roc_auc_score
from sklearn.preprocessing import StandardScaler
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
IN = WS / "outputs/01_data/monthly_features.parquet"
OUT = WS / "outputs/04_evaluation/cycle58dd_label_redefine.json"
TEST_START = pd.Timestamp('2018-01-01')


def prep_for_label(label_col):
    d = pd.read_parquet(IN)
    d['Date'] = pd.to_datetime(d['Date'])
    d = d.sort_values('Date').reset_index(drop=True)
    non_feat = ['Date', 'y_tail_q15', 'fwd_dd_21', 'y_dd_8pct']
    feat_cols = [c for c in d.columns if c not in non_feat]
    d = d.dropna(subset=[label_col]).reset_index(drop=True)
    d[feat_cols] = d[feat_cols].ffill().bfill().replace([np.inf, -np.inf], np.nan).clip(-1e6, 1e6).fillna(0)
    return d, feat_cols


def walkforward(label_col, label):
    d, fc = prep_for_label(label_col)
    X = d[fc].values; y = d[label_col].values
    dates = pd.to_datetime(d['Date'])
    test_start_idx = max((dates >= TEST_START).idxmax(), 100)
    print(f"\n[{label} : {label_col}] features={len(fc)}, OOS start={dates.iloc[test_start_idx].date()}")

    p_xgb=[]; p_rid=[]; p_hgb=[]; y_ex=[]; dates_ex=[]
    for i in range(test_start_idx, len(d) - 1):
        tr_idx = np.arange(0, i)
        if y[tr_idx].sum() < 20: continue
        Xtr=X[tr_idx]; ytr=y[tr_idx]; Xte=X[i:i+1]
        pos_w = (1 - ytr.mean()) / max(ytr.mean(), 1e-9)
        mx = xgb.XGBClassifier(n_estimators=200, max_depth=4, learning_rate=0.05,
            scale_pos_weight=pos_w, random_state=42, eval_metric='logloss', verbosity=0, n_jobs=4)
        mx.fit(Xtr, ytr); p_xgb.append(mx.predict_proba(Xte)[0, 1])
        sc = StandardScaler(); Xtr_sc = sc.fit_transform(Xtr); Xte_sc = sc.transform(Xte)
        mr = LogisticRegression(C=0.5, penalty='l2', max_iter=2000, class_weight='balanced',
            solver='lbfgs', random_state=42)
        mr.fit(Xtr_sc, ytr); p_rid.append(mr.predict_proba(Xte_sc)[0, 1])
        mh = HistGradientBoostingClassifier(max_iter=200, max_depth=4, learning_rate=0.05,
            class_weight='balanced', random_state=42)
        mh.fit(Xtr, ytr); p_hgb.append(mh.predict_proba(Xte)[0, 1])
        y_ex.append(y[i]); dates_ex.append(dates.iloc[i])

    y_ex = np.array(y_ex); p_xgb=np.array(p_xgb); p_rid=np.array(p_rid); p_hgb=np.array(p_hgb)
    p_ens = (p_xgb + p_rid + p_hgb) / 3
    n = len(y_ex); base = y_ex.mean()
    print(f"  OOS n={n} base={base*100:.1f}%")
    res = {}
    for name, p in [('xgb', p_xgb), ('ridge', p_rid), ('hgb', p_hgb), ('top3', p_ens)]:
        pr = average_precision_score(y_ex, p); roc = roc_auc_score(y_ex, p)
        res[name] = {'pr_auc': float(pr), 'lift': float(pr / base), 'roc': float(roc)}
        print(f"    {name:<8s} PR-AUC {pr:.4f} lift {pr/base:.2f}x ROC {roc:.4f}")
    res['n'] = int(n); res['base'] = float(base)

    # Period-balanced (HGB + top3)
    periods = [('2018-2020', '2018-01-01', '2020-12-31'),
               ('2021-2023', '2021-01-01', '2023-12-31'),
               ('2024-2026', '2024-01-01', '2026-12-31')]
    period_res = []
    for pname, s, e in periods:
        mask = ((pd.Series(dates_ex) >= pd.Timestamp(s)) & (pd.Series(dates_ex) <= pd.Timestamp(e))).values
        if mask.sum() < 12: continue
        for clf_name, p_clf in [('hgb', p_hgb), ('xgb', p_xgb), ('top3', p_ens)]:
            yp = y_ex[mask]; pp = p_clf[mask]
            if yp.sum() < 2: continue
            pr = average_precision_score(yp, pp); bp = yp.mean()
            period_res.append({'period': pname, 'clf': clf_name, 'n': int(mask.sum()),
                                'pos': int(yp.sum()), 'base': float(bp),
                                'pr_auc': float(pr), 'lift': float(pr / bp)})
            print(f"    [{pname}] {clf_name:<5s} n={int(mask.sum())} pos={int(yp.sum())} PR-AUC {pr:.4f} lift {pr/bp:.2f}x")
    res['period_balanced'] = period_res

    # Bootstrap CI on HGB
    B = 5000; np.random.seed(42)
    prs_hgb = []
    for b in range(B):
        idx = np.random.choice(n, n, replace=True)
        if y_ex[idx].sum() < 5: continue
        prs_hgb.append(average_precision_score(y_ex[idx], p_hgb[idx]))
    prs_hgb = np.array(prs_hgb)
    res['hgb_bootstrap'] = {
        'ci': [float(np.quantile(prs_hgb, 0.025)), float(np.quantile(prs_hgb, 0.975))],
        'p_lift_gt_2x': float((prs_hgb > 2*base).mean()),
        'p_lift_gt_1_5x': float((prs_hgb > 1.5*base).mean()),
    }
    print(f"  HGB bootstrap CI: [{res['hgb_bootstrap']['ci'][0]:.4f}, {res['hgb_bootstrap']['ci'][1]:.4f}]")
    print(f"  P(HGB lift > 2x) = {res['hgb_bootstrap']['p_lift_gt_2x']:.3f}")
    print(f"  P(HGB lift > 1.5x) = {res['hgb_bootstrap']['p_lift_gt_1_5x']:.3f}")
    return res


res_q15 = walkforward('y_tail_q15', 'A_y_tail_q15')
res_dd  = walkforward('y_dd_8pct',  'B_y_dd_8pct')

# Summary
print("\n" + "="*60)
print("SUMMARY — Label redefine (HGB V1 expanding 99mo)")
print("="*60)
for label, r in [('y_tail_q15', res_q15), ('y_dd_8pct', res_dd)]:
    p24 = next((x for x in r['period_balanced'] if x['period']=='2024-2026' and x['clf']=='hgb'), None)
    p24_lift = f"{p24['lift']:.2f}x" if p24 else "N/A"
    print(f"  {label}: full PR-AUC {r['hgb']['pr_auc']:.4f} lift {r['hgb']['lift']:.2f}x  "
          f"2024-2026 HGB lift {p24_lift}"
          f"  P(>2x) {r['hgb_bootstrap']['p_lift_gt_2x']:.3f}")

audit = {'cycle': '58DD_label_redefine_y_dd', 'y_tail_q15': res_q15, 'y_dd_8pct': res_dd}
OUT.write_text(json.dumps(audit, indent=2, ensure_ascii=False))
print(f"\nSaved: {OUT}")
