#!/usr/bin/env python3
"""312_monthly_with_turbulence_eval.py — Phase 2.1 merge + eval

Turbulence daily → monthly aggregate (PIT lag1, cut = m_start - 1d).
Append to monthly_features.parquet → monthly_features_v3_turbulence.parquet.

Walk-forward expanding 99mo eval — V1 baseline (62) vs V3 (62+3=65 features).
HGB classifier (Phase 1.2 surprise winner) + XGB + Ridge ensemble.

Period-balanced: 2018-2020 / 2021-2023 / 2024-2026 — 2024-2026 lift focus
  (HGB V1에서 1.17x로 약했던 period, Turbulence가 회복하는지 검증).

Output: outputs/04_evaluation/cycle58dd_turbulence_eval.json
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
DATA = WS / "outputs/01_data"
IN_M = DATA / "monthly_features.parquet"
IN_T = DATA / "turbulence_daily.parquet"
OUT_M = DATA / "monthly_features_v3_turbulence.parquet"
OUT_E = WS / "outputs/04_evaluation/cycle58dd_turbulence_eval.json"
TEST_START = pd.Timestamp('2018-01-01')


# === Merge ===
m = pd.read_parquet(IN_M)
m['Date'] = pd.to_datetime(m['Date'])
t = pd.read_parquet(IN_T)
t['Date'] = pd.to_datetime(t['Date'])
t = t.sort_values('Date').reset_index(drop=True)

t_lag_cols = [c for c in t.columns if c.endswith('_lag1')]
print(f"[Load] monthly: {m.shape}, turbulence daily: {t.shape}")
print(f"  turbulence lag1 cols: {t_lag_cols}")

def fetch_t(ms):
    cut = ms - pd.Timedelta(days=1)
    past = t[t['Date'] <= cut]
    if len(past) == 0:
        return {f'm_start_{c}': np.nan for c in t_lag_cols}
    last = past.iloc[-1]
    return {f'm_start_{c}': last[c] for c in t_lag_cols}

new_rows = [fetch_t(ms) for ms in m['Date']]
m_v3 = pd.concat([m.reset_index(drop=True), pd.DataFrame(new_rows)], axis=1)
new_cols = [c for c in m_v3.columns if c not in m.columns]
print(f"\n[Merge] added cols: {new_cols}")
for c in new_cols:
    v = m_v3[c].dropna()
    if len(v) > 0:
        print(f"  {c:<45s} n={len(v):>3d} mean={v.mean():.3f} std={v.std():.3f}")
m_v3.to_parquet(OUT_M, index=False)
print(f"  Saved: {OUT_M} — {len(m_v3)} rows × {len(m_v3.columns)} cols")


# === Eval ===
def prep(d):
    d = d.copy()
    d['Date'] = pd.to_datetime(d['Date'])
    d = d.sort_values('Date').reset_index(drop=True)
    non_feat = ['Date', 'y_tail_q15', 'fwd_dd_21', 'y_dd_8pct']
    feat_cols = [c for c in d.columns if c not in non_feat]
    d = d.dropna(subset=['y_tail_q15'])
    d[feat_cols] = d[feat_cols].ffill().bfill().replace([np.inf, -np.inf], np.nan).clip(-1e6, 1e6).fillna(0)
    return d, feat_cols


def walkforward(d, feat_cols, label):
    X = d[feat_cols].values; y = d['y_tail_q15'].values
    dates = pd.to_datetime(d['Date'])
    test_start_idx = max((dates >= TEST_START).idxmax(), 100)
    print(f"\n[{label}] features={len(feat_cols)}  OOS start={dates.iloc[test_start_idx].date()}")
    p_xgb=[]; p_rid=[]; p_hgb=[]; y_ex=[]; dates_ex=[]
    for i in range(test_start_idx, len(d) - 1):
        tr_idx = np.arange(0, i)
        if y[tr_idx].sum() < 30: continue
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

    y_ex = np.array(y_ex); p_xgb = np.array(p_xgb); p_rid = np.array(p_rid); p_hgb = np.array(p_hgb)
    p_ens = (p_xgb + p_rid + p_hgb) / 3
    base = y_ex.mean(); n = len(y_ex)
    print(f"  OOS n={n} base={base*100:.1f}%")
    res = {}
    for name, p in [('xgb', p_xgb), ('ridge', p_rid), ('hgb', p_hgb), ('top3', p_ens)]:
        pr = average_precision_score(y_ex, p)
        roc = roc_auc_score(y_ex, p)
        res[name] = {'pr_auc': float(pr), 'lift': float(pr / base), 'roc': float(roc)}
        print(f"    {name:<8s} PR-AUC {pr:.4f} lift {pr/base:.2f}x ROC {roc:.4f}")
    res['n_test_months'] = int(n); res['base_rate'] = float(base)

    # Period-balanced (HGB focus, 2024-2026 critical)
    periods = [('2018-2020', '2018-01-01', '2020-12-31'),
               ('2021-2023', '2021-01-01', '2023-12-31'),
               ('2024-2026', '2024-01-01', '2026-12-31')]
    period_res = []
    for pname, s, e in periods:
        mask = ((pd.Series(dates_ex) >= pd.Timestamp(s)) & (pd.Series(dates_ex) <= pd.Timestamp(e))).values
        if mask.sum() < 12: continue
        for clf_name, p_clf in [('hgb', p_hgb), ('xgb', p_xgb), ('top3', p_ens)]:
            yp = y_ex[mask]; pp = p_clf[mask]
            if yp.sum() < 3: continue
            pr = average_precision_score(yp, pp); bp = yp.mean()
            period_res.append({'period': pname, 'clf': clf_name, 'n': int(mask.sum()),
                                'pos': int(yp.sum()), 'base': float(bp),
                                'pr_auc': float(pr), 'lift': float(pr / bp)})
            print(f"    [{pname}] {clf_name:<5s} n={int(mask.sum())} pos={int(yp.sum())} PR-AUC {pr:.4f} lift {pr/bp:.2f}x")
    res['period_balanced'] = period_res
    return res, p_xgb, p_rid, p_hgb, p_ens, y_ex


d1, fc1 = prep(pd.read_parquet(IN_M))
d3, fc3 = prep(m_v3)
res_v1, p1x, p1r, p1h, p1e, y_ex = walkforward(d1, fc1, "V1 baseline (62)")
res_v3, p3x, p3r, p3h, p3e, _ = walkforward(d3, fc3, "V3 + turbulence")

# Paired bootstrap for HGB (the winner)
print("\n" + "="*60)
print("Paired bootstrap CI 95% — HGB V3 vs HGB V1 (B=5000)")
print("="*60)
n = len(y_ex); B = 5000
np.random.seed(42)
prs_v1=[]; prs_v3=[]; deltas=[]
for b in range(B):
    idx = np.random.choice(n, n, replace=True)
    if y_ex[idx].sum() < 5: continue
    pr1 = average_precision_score(y_ex[idx], p1h[idx])
    pr3 = average_precision_score(y_ex[idx], p3h[idx])
    prs_v1.append(pr1); prs_v3.append(pr3); deltas.append(pr3 - pr1)
prs_v1=np.array(prs_v1); prs_v3=np.array(prs_v3); deltas=np.array(deltas)
print(f"  HGB V1 CI: [{np.quantile(prs_v1, 0.025):.4f}, {np.quantile(prs_v1, 0.975):.4f}]")
print(f"  HGB V3 CI: [{np.quantile(prs_v3, 0.025):.4f}, {np.quantile(prs_v3, 0.975):.4f}]")
print(f"  Δ CI: [{np.quantile(deltas, 0.025):+.4f}, {np.quantile(deltas, 0.975):+.4f}]")
print(f"  P(V3 > V1) = {(deltas > 0).mean():.3f}")
print(f"  P(V3 lift > 2x) = {(prs_v3 > 2*res_v3['base_rate']).mean():.3f}")

audit = {
    'cycle': '58DD_phase2.1_turbulence',
    'v1_baseline': res_v1,
    'v3_with_turbulence': res_v3,
    'paired_bootstrap_hgb': {
        'v1_ci': [float(np.quantile(prs_v1, 0.025)), float(np.quantile(prs_v1, 0.975))],
        'v3_ci': [float(np.quantile(prs_v3, 0.025)), float(np.quantile(prs_v3, 0.975))],
        'delta_ci': [float(np.quantile(deltas, 0.025)), float(np.quantile(deltas, 0.975))],
        'p_v3_gt_v1': float((deltas > 0).mean()),
        'p_v3_lift_gt_2x': float((prs_v3 > 2*res_v3['base_rate']).mean()),
    }
}
OUT_E.write_text(json.dumps(audit, indent=2, ensure_ascii=False))
print(f"\nSaved: {OUT_E}")
