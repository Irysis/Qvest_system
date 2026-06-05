#!/usr/bin/env python3
"""315_dual_label_ensemble.py — Dual-label complementary ensemble

발견: y_tail_q15 (endpoint) + y_dd_8pct (drawdown) complementary period strength
  y_tail_q15: 2018-2023 strong (lift 1.93-2.41x), 2024-2026 weak (1.17x)
  y_dd_8pct:  2018-2023 weak (lift 0.85-1.05x), 2024-2026 strong (2.25x)

Hypothesis: 두 HGB 모델을 모두 학습 → 각자 probability 산출 → ensemble 함수 적용
  E1: max(P_q15, P_dd)         — OR (any bear event)
  E2: mean(P_q15, P_dd)        — risk score average
  E3: 2/3*P_q15 + 1/3*P_dd     — endpoint weight ↑ (mandate aligned)
  E4: 1/3*P_q15 + 2/3*P_dd     — drawdown weight ↑ (recent regime)

Evaluation: against **y_tail_q15** (user mandate target).
Period-balanced + bootstrap CI.

Output: outputs/04_evaluation/cycle58dd_dual_label_ensemble.json
"""
import json
from pathlib import Path
import pandas as pd
import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.metrics import average_precision_score, roc_auc_score
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
IN = WS / "outputs/01_data/monthly_features.parquet"
OUT = WS / "outputs/04_evaluation/cycle58dd_dual_label_ensemble.json"
TEST_START = pd.Timestamp('2018-01-01')

# Load both labels
d = pd.read_parquet(IN)
d['Date'] = pd.to_datetime(d['Date'])
d = d.sort_values('Date').reset_index(drop=True)
non_feat = ['Date', 'y_tail_q15', 'fwd_dd_21', 'y_dd_8pct']
feat_cols = [c for c in d.columns if c not in non_feat]
d[feat_cols] = d[feat_cols].ffill().bfill().replace([np.inf, -np.inf], np.nan).clip(-1e6, 1e6).fillna(0)

# Drop rows where EITHER label is NaN (need both for dual training)
d_dual = d.dropna(subset=['y_tail_q15', 'y_dd_8pct']).reset_index(drop=True)
X = d_dual[feat_cols].values
y_q15 = d_dual['y_tail_q15'].values
y_dd = d_dual['y_dd_8pct'].values
dates = pd.to_datetime(d_dual['Date'])
test_start_idx = max((dates >= TEST_START).idxmax(), 100)
print(f"[Load] {len(d_dual)} months × {len(feat_cols)} features (both labels), OOS n={len(d_dual) - test_start_idx - 1}")
print(f"  y_tail_q15 base: {y_q15.mean()*100:.1f}%")
print(f"  y_dd_8pct  base: {y_dd.mean()*100:.1f}%")

# Walk-forward expanding — train HGB on each label, get probs
preds_q15 = []
preds_dd = []
y_q15_test = []
dates_ex = []
for i in range(test_start_idx, len(d_dual) - 1):
    tr_idx = np.arange(0, i)
    if y_q15[tr_idx].sum() < 20 or y_dd[tr_idx].sum() < 20: continue
    Xtr = X[tr_idx]; Xte = X[i:i+1]
    # Model 1: y_tail_q15
    m_q15 = HistGradientBoostingClassifier(max_iter=200, max_depth=4, learning_rate=0.05,
        class_weight='balanced', random_state=42)
    m_q15.fit(Xtr, y_q15[tr_idx]); preds_q15.append(m_q15.predict_proba(Xte)[0, 1])
    # Model 2: y_dd_8pct
    m_dd = HistGradientBoostingClassifier(max_iter=200, max_depth=4, learning_rate=0.05,
        class_weight='balanced', random_state=42)
    m_dd.fit(Xtr, y_dd[tr_idx]); preds_dd.append(m_dd.predict_proba(Xte)[0, 1])
    y_q15_test.append(y_q15[i])
    dates_ex.append(dates.iloc[i])

y_q15_test = np.array(y_q15_test)
preds_q15 = np.array(preds_q15)
preds_dd = np.array(preds_dd)
n = len(y_q15_test); base = y_q15_test.mean()
print(f"  OOS n={n} y_tail_q15 base={base*100:.1f}%")
print(f"  preds correlation: cor(P_q15, P_dd) = {np.corrcoef(preds_q15, preds_dd)[0, 1]:.3f}")

# Ensemble variants (vs y_tail_q15 target)
ensembles = {
    'P_q15 only (baseline)': preds_q15,
    'P_dd only': preds_dd,
    'E1_max': np.maximum(preds_q15, preds_dd),
    'E2_mean': (preds_q15 + preds_dd) / 2,
    'E3_endpoint_heavy_2/3': 2/3 * preds_q15 + 1/3 * preds_dd,
    'E4_drawdown_heavy_2/3': 1/3 * preds_q15 + 2/3 * preds_dd,
}

print("\n" + "="*60)
print("Full OOS — vs y_tail_q15")
print("="*60)
results = {}
for name, p in ensembles.items():
    pr = average_precision_score(y_q15_test, p)
    roc = roc_auc_score(y_q15_test, p)
    results[name] = {'pr_auc': float(pr), 'lift': float(pr / base), 'roc': float(roc)}
    print(f"  {name:<35s} PR-AUC {pr:.4f}  lift {pr/base:.2f}x  ROC {roc:.4f}")

# Period-balanced
periods = [('2018-2020', '2018-01-01', '2020-12-31'),
           ('2021-2023', '2021-01-01', '2023-12-31'),
           ('2024-2026', '2024-01-01', '2026-12-31')]
print("\n" + "="*60)
print("Period-balanced — vs y_tail_q15")
print("="*60)
print(f"{'Variant':<35s} {'2018-20':>10s} {'2021-23':>10s} {'2024-26':>10s}")
period_results = {}
for name, p in ensembles.items():
    row = {}
    for pname, s, e in periods:
        mask = ((pd.Series(dates_ex) >= pd.Timestamp(s)) & (pd.Series(dates_ex) <= pd.Timestamp(e))).values
        if mask.sum() < 12 or y_q15_test[mask].sum() < 2:
            row[pname] = 'N/A'
        else:
            pr = average_precision_score(y_q15_test[mask], p[mask])
            bp = y_q15_test[mask].mean()
            row[pname] = f"{pr/bp:.2f}x"
    period_results[name] = row
    print(f"  {name:<35s} {row['2018-2020']:>10s} {row['2021-2023']:>10s} {row['2024-2026']:>10s}")

# Bootstrap for best ensemble vs P_q15 baseline (paired)
print("\n" + "="*60)
# Find best ensemble by full PR-AUC (exclude single-label baselines)
ens_only = {k: v for k, v in results.items() if k.startswith('E')}
best_k = max(ens_only.keys(), key=lambda k: ens_only[k]['pr_auc'])
print(f"Paired bootstrap — {best_k} vs P_q15 only (B=5000)")
print("="*60)
B = 5000; np.random.seed(42)
prs_base = []; prs_best = []; deltas = []
p_base = preds_q15
p_best = ensembles[best_k]
for b in range(B):
    idx = np.random.choice(n, n, replace=True)
    if y_q15_test[idx].sum() < 5: continue
    pr_b = average_precision_score(y_q15_test[idx], p_base[idx])
    pr_e = average_precision_score(y_q15_test[idx], p_best[idx])
    prs_base.append(pr_b); prs_best.append(pr_e); deltas.append(pr_e - pr_b)
prs_base = np.array(prs_base); prs_best = np.array(prs_best); deltas = np.array(deltas)
print(f"  P_q15 only CI: [{np.quantile(prs_base, 0.025):.4f}, {np.quantile(prs_base, 0.975):.4f}]")
print(f"  {best_k} CI:   [{np.quantile(prs_best, 0.025):.4f}, {np.quantile(prs_best, 0.975):.4f}]")
print(f"  Delta CI:    [{np.quantile(deltas, 0.025):+.4f}, {np.quantile(deltas, 0.975):+.4f}]")
print(f"  P(ensemble > baseline) = {(deltas > 0).mean():.3f}")
print(f"  P(ensemble lift > 2x)   = {(prs_best > 2*base).mean():.3f}")
print(f"  P(P_q15 lift > 2x)     = {(prs_base > 2*base).mean():.3f}")

audit = {
    'cycle': '58DD_dual_label_ensemble',
    'n': int(n), 'base_q15': float(base),
    'pred_correlation': float(np.corrcoef(preds_q15, preds_dd)[0, 1]),
    'full_oos_vs_y_q15': results,
    'period_balanced': period_results,
    'best_ensemble': best_k,
    'paired_bootstrap_best_vs_baseline': {
        'base_ci': [float(np.quantile(prs_base, 0.025)), float(np.quantile(prs_base, 0.975))],
        'best_ci': [float(np.quantile(prs_best, 0.025)), float(np.quantile(prs_best, 0.975))],
        'delta_ci': [float(np.quantile(deltas, 0.025)), float(np.quantile(deltas, 0.975))],
        'p_best_gt_baseline': float((deltas > 0).mean()),
        'p_best_lift_gt_2x': float((prs_best > 2*base).mean()),
        'p_base_lift_gt_2x': float((prs_base > 2*base).mean()),
    },
}
OUT.write_text(json.dumps(audit, indent=2, ensure_ascii=False))
print(f"\nSaved: {OUT}")
