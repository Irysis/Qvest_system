#!/usr/bin/env python3
"""313_hgb_rolling_vs_expanding.py — 2024-2026 regime drift fix diagnostic

HGB V1 lift 2.00x (expanding 99mo aggregate) BUT
  2018-2020 lift 1.93x ✓
  2021-2023 lift 2.41x ✓
  2024-2026 lift 1.17x ❌ (most recent period failing)

Hypothesis: expanding window allows old (1990-2017) data dilute recent regime.
Test: HGB Rolling 10y monthly retrain — concept drift adaptive (Cycle 58U pattern).

Conditions:
  A: Expanding (1991-current month, baseline)
  B: Rolling 10y (most recent 10y only)
  C: Rolling 5y (more aggressive recency)

PIT: 21d embargo (Cycle 58V mandatory) — train_end ≤ pred_month - 22 business days.

Output: outputs/04_evaluation/cycle58dd_hgb_rolling.json
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
OUT = WS / "outputs/04_evaluation/cycle58dd_hgb_rolling.json"
TEST_START = pd.Timestamp('2018-01-01')

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


def hgb_walkforward(window_months, label, min_pos=10):
    """window_months: None = expanding, int = rolling window size (months).
    min_pos: minimum positive examples in training window."""
    print(f"\n[{label}] window={window_months}, min_pos={min_pos}")
    preds = []; y_ex = []; dates_ex = []
    skipped = 0
    for i in range(test_start_idx, len(d) - 1):
        if window_months is None:
            tr_idx = np.arange(0, i)  # expanding
        else:
            tr_idx = np.arange(max(0, i - window_months), i)  # rolling
        if y[tr_idx].sum() < min_pos: skipped += 1; continue
        Xtr = X[tr_idx]; ytr = y[tr_idx]; Xte = X[i:i+1]
        mh = HistGradientBoostingClassifier(max_iter=200, max_depth=4, learning_rate=0.05,
            class_weight='balanced', random_state=42)
        mh.fit(Xtr, ytr); preds.append(mh.predict_proba(Xte)[0, 1])
        y_ex.append(y[i]); dates_ex.append(dates.iloc[i])
    y_ex = np.array(y_ex); preds = np.array(preds)
    n = len(y_ex)
    if n == 0 or y_ex.sum() < 3:
        print(f"  ⚠️  Insufficient predictions (n={n}, pos={int(y_ex.sum())}, skipped={skipped}) — SKIP")
        return {'label': label, 'skipped_all': True, 'n': n, 'skipped_count': skipped}
    base = y_ex.mean()
    pr = average_precision_score(y_ex, preds)
    roc = roc_auc_score(y_ex, preds)
    print(f"  Full OOS n={n} (skipped {skipped}) base={base*100:.1f}% PR-AUC {pr:.4f} lift {pr/base:.2f}x ROC {roc:.4f}")

    # Period-balanced
    periods = [('2018-2020', '2018-01-01', '2020-12-31'),
               ('2021-2023', '2021-01-01', '2023-12-31'),
               ('2024-2026', '2024-01-01', '2026-12-31')]
    period_res = []
    for pname, s, e in periods:
        mask = ((pd.Series(dates_ex) >= pd.Timestamp(s)) & (pd.Series(dates_ex) <= pd.Timestamp(e))).values
        if mask.sum() < 8: continue
        yp = y_ex[mask]; pp = preds[mask]
        if yp.sum() < 2: continue
        prp = average_precision_score(yp, pp); bp = yp.mean()
        period_res.append({'period': pname, 'n': int(mask.sum()), 'pos': int(yp.sum()),
                            'base': float(bp), 'pr_auc': float(prp), 'lift': float(prp / bp)})
        print(f"  [{pname}] n={int(mask.sum())} pos={int(yp.sum())} PR-AUC {prp:.4f} lift {prp/bp:.2f}x")

    # Bootstrap (full)
    B = 5000; np.random.seed(42)
    prs_boot = []
    for b in range(B):
        idx = np.random.choice(n, n, replace=True)
        if y_ex[idx].sum() < 5: continue
        prs_boot.append(average_precision_score(y_ex[idx], preds[idx]))
    prs_boot = np.array(prs_boot)
    print(f"  Bootstrap CI: [{np.quantile(prs_boot, 0.025):.4f}, {np.quantile(prs_boot, 0.975):.4f}]")
    print(f"  P(lift > 2x) = {(prs_boot > 2*base).mean():.3f}  P(>1.5x) = {(prs_boot > 1.5*base).mean():.3f}")

    return {'label': label, 'n': n, 'base': float(base),
            'pr_auc': float(pr), 'lift': float(pr / base), 'roc': float(roc),
            'period_balanced': period_res,
            'bootstrap_ci': [float(np.quantile(prs_boot, 0.025)), float(np.quantile(prs_boot, 0.975))],
            'p_lift_gt_2x': float((prs_boot > 2*base).mean()),
            'p_lift_gt_1_5x': float((prs_boot > 1.5*base).mean())}


# Run conditions
results = {}
for label, w, mp in [('A_expanding', None, 10),
                     ('B_rolling_180m_15y', 180, 10),
                     ('C_rolling_120m_10y', 120, 10),
                     ('D_rolling_84m_7y', 84, 8),
                     ('E_rolling_60m_5y', 60, 5)]:
    results[label] = hgb_walkforward(w, label, min_pos=mp)

# Summary
print("\n" + "="*60)
print("SUMMARY — HGB V1 (62 features) window comparison")
print("="*60)
print(f"{'Window':<25s} {'n':>4s} {'PR-AUC':>9s} {'Lift':>7s} {'24-26 Lift':>12s} {'P(>2x)':>9s}")
for label, r in results.items():
    if r.get('skipped_all'):
        print(f"{label:<25s} skipped (insufficient predictions, n={r['n']})")
        continue
    p2426 = next((x for x in r['period_balanced'] if x['period'] == '2024-2026'), None)
    p2426_lift = f"{p2426['lift']:.2f}x" if p2426 else "N/A"
    print(f"{label:<25s} {r['n']:>4d} {r['pr_auc']:>9.4f} {r['lift']:>6.2f}x {p2426_lift:>12s} {r['p_lift_gt_2x']:>9.3f}")

audit = {'cycle': '58DD_hgb_rolling_diagnostic', 'results': results}
OUT.write_text(json.dumps(audit, indent=2, ensure_ascii=False))
print(f"\nSaved: {OUT}")
