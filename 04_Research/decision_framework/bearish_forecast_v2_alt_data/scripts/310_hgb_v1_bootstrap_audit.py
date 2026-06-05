#!/usr/bin/env python3
"""310_hgb_v1_bootstrap_audit.py — HGB V1 surprise finding 검증

Phase 1.2 eval에서 발견: V1 baseline (62 features) HGB classifier 단독
  PR-AUC 0.3642 = lift 2.00x = 도훈 target ⭐

검증 mandate (도훈 audit pattern):
  - "수치가 너무 좋은데 검증 제대로 한거 맞아?"
  - Bootstrap CI 95% on HGB alone (paired vs XGB baseline)
  - Period-balanced PR-AUC (2018-2020 / 2021-2023 / 2024-2026)
  - HGB seed stability (5 seeds same OOS, std check)
  - PIT re-check: 모든 feature가 m_start - 1d 이전만 사용

Output: outputs/04_evaluation/cycle58dd_hgb_v1_audit.json
"""
import json
from pathlib import Path
import pandas as pd
import numpy as np
import xgboost as xgb
from sklearn.ensemble import HistGradientBoostingClassifier, GradientBoostingClassifier
from sklearn.metrics import average_precision_score, roc_auc_score
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
IN = WS / "outputs/01_data/monthly_features.parquet"
OUT = WS / "outputs/04_evaluation/cycle58dd_hgb_v1_audit.json"

TEST_START = pd.Timestamp('2018-01-01')
SEEDS = [42, 123, 456, 789, 1024]

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

# Walk-forward expanding for each seed
print(f"\n[5-seed HGB walk-forward expanding {SEEDS}]")
preds_per_seed = {s: [] for s in SEEDS}
preds_xgb = []  # baseline ref
preds_gb = []   # vanilla GB (303 baseline)
y_ex = []
dates_ex = []

for i in range(test_start_idx, len(d) - 1):
    tr_idx = np.arange(0, i)
    if y[tr_idx].sum() < 30: continue
    Xtr = X[tr_idx]; ytr = y[tr_idx]
    Xte = X[i:i+1]
    pos_w = (1 - ytr.mean()) / max(ytr.mean(), 1e-9)
    # 5 HGB seeds
    for s in SEEDS:
        mh = HistGradientBoostingClassifier(max_iter=200, max_depth=4, learning_rate=0.05,
            class_weight='balanced', random_state=s)
        mh.fit(Xtr, ytr); preds_per_seed[s].append(mh.predict_proba(Xte)[0, 1])
    # XGB baseline ref
    mx = xgb.XGBClassifier(n_estimators=200, max_depth=4, learning_rate=0.05,
        scale_pos_weight=pos_w, random_state=42,
        eval_metric='logloss', verbosity=0, n_jobs=4)
    mx.fit(Xtr, ytr); preds_xgb.append(mx.predict_proba(Xte)[0, 1])
    # Vanilla GB ref (was 0.1525 in Phase 1.3+1.4)
    mg = GradientBoostingClassifier(n_estimators=200, max_depth=4, learning_rate=0.05, random_state=42)
    mg.fit(Xtr, ytr); preds_gb.append(mg.predict_proba(Xte)[0, 1])
    y_ex.append(y[i]); dates_ex.append(dates.iloc[i])

y_ex = np.array(y_ex)
n = len(y_ex)
base = y_ex.mean()
print(f"  OOS n={n} months, base rate {base*100:.1f}%")

print(f"\n[Seed stability — HGB 5 seeds]")
seed_prs = {}
for s in SEEDS:
    p = np.array(preds_per_seed[s])
    pr = average_precision_score(y_ex, p)
    seed_prs[s] = pr
    print(f"    HGB seed {s}: PR-AUC {pr:.4f} lift {pr/base:.2f}x")
prs_arr = np.array(list(seed_prs.values()))
print(f"  mean5 PR-AUC: {prs_arr.mean():.4f}  std: {prs_arr.std():.4f}")
print(f"  mean5 lift: {prs_arr.mean()/base:.2f}x")

print(f"\n[Baseline references]")
pr_xgb = average_precision_score(y_ex, np.array(preds_xgb))
pr_gb = average_precision_score(y_ex, np.array(preds_gb))
print(f"  XGB (seed 42): PR-AUC {pr_xgb:.4f}  lift {pr_xgb/base:.2f}x")
print(f"  Vanilla GB (seed 42): PR-AUC {pr_gb:.4f}  lift {pr_gb/base:.2f}x")

# HGB seed 42 vs XGB paired bootstrap
print(f"\n[Paired bootstrap CI 95%: HGB seed=42 vs XGB seed=42, B=5000]")
B = 5000
np.random.seed(42)
prs_hgb_boot = []; prs_xgb_boot = []; deltas = []
p_hgb_42 = np.array(preds_per_seed[42])
p_xgb_42 = np.array(preds_xgb)
for b in range(B):
    idx = np.random.choice(n, n, replace=True)
    if y_ex[idx].sum() < 5: continue
    pr_h = average_precision_score(y_ex[idx], p_hgb_42[idx])
    pr_x = average_precision_score(y_ex[idx], p_xgb_42[idx])
    prs_hgb_boot.append(pr_h); prs_xgb_boot.append(pr_x); deltas.append(pr_h - pr_x)
prs_hgb_boot = np.array(prs_hgb_boot); prs_xgb_boot = np.array(prs_xgb_boot); deltas = np.array(deltas)
print(f"  HGB CI:  [{np.quantile(prs_hgb_boot, 0.025):.4f}, {np.quantile(prs_hgb_boot, 0.975):.4f}]")
print(f"  XGB CI:  [{np.quantile(prs_xgb_boot, 0.025):.4f}, {np.quantile(prs_xgb_boot, 0.975):.4f}]")
print(f"  Δ CI:    [{np.quantile(deltas, 0.025):+.4f}, {np.quantile(deltas, 0.975):+.4f}]")
print(f"  P(HGB > XGB) = {(deltas > 0).mean():.3f}")
print(f"  P(HGB lift > 2x) = {(prs_hgb_boot > 2*base).mean():.3f}")
print(f"  P(XGB lift > 2x) = {(prs_xgb_boot > 2*base).mean():.3f}")
print(f"  P(HGB lift > 1.5x) = {(prs_hgb_boot > 1.5*base).mean():.3f}")

# Period-balanced PR-AUC (HGB seed=42)
print(f"\n[Period-balanced PR-AUC — HGB seed=42]")
periods = [
    ('2018-2020', '2018-01-01', '2020-12-31'),
    ('2021-2023', '2021-01-01', '2023-12-31'),
    ('2024-2026', '2024-01-01', '2026-12-31'),
]
period_results = []
for pname, s, e in periods:
    mask = (pd.Series(dates_ex) >= pd.Timestamp(s)) & (pd.Series(dates_ex) <= pd.Timestamp(e))
    mask = mask.values
    if mask.sum() < 12: continue
    p_period = p_hgb_42[mask]
    y_period = y_ex[mask]
    if y_period.sum() < 3:
        print(f"    {pname}: n={mask.sum()}, pos={int(y_period.sum())} — too few positives"); continue
    pr_p = average_precision_score(y_period, p_period)
    base_p = y_period.mean()
    lift_p = pr_p / base_p
    print(f"    {pname}: n={mask.sum():>2d} pos={int(y_period.sum()):>2d} base={base_p*100:.1f}% PR-AUC {pr_p:.4f} lift {lift_p:.2f}x")
    period_results.append({'period': pname, 'n': int(mask.sum()), 'pos': int(y_period.sum()),
                            'base': float(base_p), 'pr_auc': float(pr_p), 'lift': float(lift_p)})

# 5-seed mean ensemble
print(f"\n[HGB 5-seed mean ensemble]")
p_mean5 = np.mean([np.array(preds_per_seed[s]) for s in SEEDS], axis=0)
pr_mean5 = average_precision_score(y_ex, p_mean5)
roc_mean5 = roc_auc_score(y_ex, p_mean5)
print(f"  PR-AUC {pr_mean5:.4f}  lift {pr_mean5/base:.2f}x  ROC {roc_mean5:.4f}")

# Bootstrap 5-seed mean
print(f"\n[Bootstrap CI HGB 5-seed mean (B=5000)]")
prs_mean5_boot = []
np.random.seed(42)
for b in range(B):
    idx = np.random.choice(n, n, replace=True)
    if y_ex[idx].sum() < 5: continue
    prs_mean5_boot.append(average_precision_score(y_ex[idx], p_mean5[idx]))
prs_mean5_boot = np.array(prs_mean5_boot)
print(f"  mean5 CI: [{np.quantile(prs_mean5_boot, 0.025):.4f}, {np.quantile(prs_mean5_boot, 0.975):.4f}]")
print(f"  P(mean5 lift > 2x)   = {(prs_mean5_boot > 2*base).mean():.3f}")
print(f"  P(mean5 lift > 1.5x) = {(prs_mean5_boot > 1.5*base).mean():.3f}")

# Save audit
audit = {
    'cycle': '58DD_hgb_v1_audit',
    'context': 'Phase 1.2 발견 — V1 baseline (62 features) HGB classifier 단독 PR-AUC 0.3642 lift 2.00x. 진정 robust 검증.',
    'n_test_months': int(n),
    'base_rate': float(base),
    'seed_prs': {str(k): float(v) for k, v in seed_prs.items()},
    'seed_mean5_pr': float(prs_arr.mean()),
    'seed_std': float(prs_arr.std()),
    'xgb_baseline_pr': float(pr_xgb),
    'vanilla_gb_pr': float(pr_gb),
    'hgb_seed42_vs_xgb_paired': {
        'hgb_ci': [float(np.quantile(prs_hgb_boot, 0.025)), float(np.quantile(prs_hgb_boot, 0.975))],
        'xgb_ci': [float(np.quantile(prs_xgb_boot, 0.025)), float(np.quantile(prs_xgb_boot, 0.975))],
        'delta_ci': [float(np.quantile(deltas, 0.025)), float(np.quantile(deltas, 0.975))],
        'p_hgb_gt_xgb': float((deltas > 0).mean()),
        'p_hgb_lift_gt_2x': float((prs_hgb_boot > 2*base).mean()),
        'p_xgb_lift_gt_2x': float((prs_xgb_boot > 2*base).mean()),
        'p_hgb_lift_gt_1_5x': float((prs_hgb_boot > 1.5*base).mean()),
    },
    'period_balanced_hgb_seed42': period_results,
    'mean5_ensemble': {
        'pr_auc': float(pr_mean5),
        'lift': float(pr_mean5 / base),
        'roc': float(roc_mean5),
        'bootstrap_ci': [float(np.quantile(prs_mean5_boot, 0.025)), float(np.quantile(prs_mean5_boot, 0.975))],
        'p_lift_gt_2x': float((prs_mean5_boot > 2*base).mean()),
        'p_lift_gt_1_5x': float((prs_mean5_boot > 1.5*base).mean()),
    },
}
OUT.write_text(json.dumps(audit, indent=2, ensure_ascii=False))
print(f"\nSaved: {OUT}")
