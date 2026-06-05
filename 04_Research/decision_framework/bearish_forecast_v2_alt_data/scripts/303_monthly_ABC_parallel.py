#!/usr/bin/env python3
"""303_monthly_ABC_parallel.py — Cycle 58CC Phase 3 (A+B+C 병렬)

A: Multi-bootstrap Ridge (variance + stability)
B: Top 15 features focus (feature selection)
C: Walk-forward expanding monthly (100+ months OOS)
"""
import json
from pathlib import Path
import pandas as pd
import numpy as np
import xgboost as xgb
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.metrics import average_precision_score, roc_auc_score
from sklearn.preprocessing import StandardScaler
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = (PROJECT_ROOT /
      "04_Research/decision_framework/bearish_forecast_v2_alt_data")
IN = WS / "outputs/01_data/monthly_features.parquet"
OUT = WS / "outputs/04_evaluation/cycle58cc_ABC.json"

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

# ============================================================
# A: Multi-bootstrap Ridge (variance check)
# ============================================================
print("\n" + "="*60)
print("A: Multi-bootstrap Ridge (variance check)")
print("="*60)
test_mask = (dates >= pd.Timestamp('2024-08-01')).values
X_tr, y_tr = X[~test_mask], y[~test_mask]
X_te, y_te = X[test_mask], y[test_mask]
sc = StandardScaler()
X_tr_sc = sc.fit_transform(X_tr); X_te_sc = sc.transform(X_te)

N_BOOT = 50
np.random.seed(42)
preds_boot = []
for b in range(N_BOOT):
    idx = np.random.choice(len(X_tr_sc), len(X_tr_sc), replace=True)
    if y_tr[idx].sum() < 5: continue
    r = LogisticRegression(C=0.5, penalty='l2', max_iter=2000, class_weight='balanced',
                            solver='lbfgs', random_state=b)
    r.fit(X_tr_sc[idx], y_tr[idx])
    preds_boot.append(r.predict_proba(X_te_sc)[:, 1])
preds_boot = np.array(preds_boot)
p_mean = preds_boot.mean(axis=0)
p_std = preds_boot.std(axis=0)
pr_boot_ens = average_precision_score(y_te, p_mean)
print(f"  Bootstrap N={len(preds_boot)} Ridge ensemble:")
print(f"    Mean prediction PR-AUC: {pr_boot_ens:.4f}")
print(f"    Mean per-sample std: {p_std.mean():.4f}  max: {p_std.max():.4f}")
# Per-bootstrap PR-AUC distribution
prs_per_boot = [average_precision_score(y_te, p) for p in preds_boot]
prs_per_boot = np.array(prs_per_boot)
print(f"    Per-bootstrap PR-AUC: mean={prs_per_boot.mean():.4f}  std={prs_per_boot.std():.4f}")
print(f"    Per-bootstrap range: [{prs_per_boot.min():.4f}, {prs_per_boot.max():.4f}]")

# ============================================================
# B: Top 15 features focus (XGB importance based)
# ============================================================
print("\n" + "="*60)
print("B: Top 15 features focus")
print("="*60)
pos_w = (1 - y_tr.mean()) / max(y_tr.mean(), 1e-9)
xgb_imp = xgb.XGBClassifier(n_estimators=200, max_depth=4, learning_rate=0.05,
    scale_pos_weight=pos_w, random_state=42, eval_metric='logloss', verbosity=0, n_jobs=4)
xgb_imp.fit(X_tr, y_tr)
imp = xgb_imp.feature_importances_
top15_idx = np.argsort(imp)[-15:][::-1]
top15_names = [feat_cols[i] for i in top15_idx]
print(f"  Top 15 features:")
for i, name in enumerate(top15_names, 1):
    print(f"    {i:>2}. {name:<45s} {imp[top15_idx[i-1]]:.4f}")

X_tr_15 = X_tr[:, top15_idx]; X_te_15 = X_te[:, top15_idx]
sc15 = StandardScaler()
X_tr_15_sc = sc15.fit_transform(X_tr_15); X_te_15_sc = sc15.transform(X_te_15)

# Re-train models on top 15 features
models15 = {
    'ridge15': LogisticRegression(C=0.5, penalty='l2', max_iter=2000, class_weight='balanced',
                                   solver='lbfgs', random_state=42),
    'xgb15': xgb.XGBClassifier(n_estimators=200, max_depth=4, learning_rate=0.05,
        scale_pos_weight=pos_w, random_state=42, eval_metric='logloss', verbosity=0, n_jobs=4),
    'gb15': GradientBoostingClassifier(n_estimators=200, max_depth=4, learning_rate=0.05, random_state=42),
}
preds15 = {}
for name, m in models15.items():
    if 'ridge' in name:
        m.fit(X_tr_15_sc, y_tr); preds15[name] = m.predict_proba(X_te_15_sc)[:, 1]
    else:
        m.fit(X_tr_15, y_tr); preds15[name] = m.predict_proba(X_te_15)[:, 1]

print(f"\n  Top 15 features results (vs full 49 features):")
print(f"    {'Model':<15s}{'Top15 PR':>10s}{'Full PR':>10s}{'Δ':>10s}")
full_prev = {'ridge15': 0.2159, 'xgb15': 0.1222, 'gb15': 0.1484}
for name, p in preds15.items():
    pr15 = average_precision_score(y_te, p)
    print(f"    {name:<15s}{pr15:>10.4f}{full_prev[name]:>10.4f}{pr15-full_prev[name]:>+10.4f}")

# Ensemble top15
ens15 = (preds15['ridge15'] + preds15['xgb15'] + preds15['gb15']) / 3
pr_ens15 = average_precision_score(y_te, ens15)
print(f"    top3 ens15:       {pr_ens15:.4f}  (vs full 0.2250)")

# ============================================================
# C: Walk-forward expanding monthly (longer OOS)
# ============================================================
print("\n" + "="*60)
print("C: Walk-forward expanding monthly (longer OOS)")
print("="*60)
# Expanding: each month retrain on past, predict next month
# Start from month 100 (need enough training data)
start_idx = 100  # ~8 years initial train
test_start_idx = (dates >= pd.Timestamp('2018-01-01')).idxmax()
test_start_idx = max(test_start_idx, start_idx)
print(f"  Expanding OOS start: {dates.iloc[test_start_idx].date()} (~{len(d) - test_start_idx} months)")

ridge_preds_ex = []
ens_preds_ex = []
y_ex = []
dates_ex = []
for i in range(test_start_idx, len(d) - 1):  # -1 for safety
    tr_idx = np.arange(0, i)  # all past
    if y[tr_idx].sum() < 30: continue
    Xtr_e = X[tr_idx]; ytr_e = y[tr_idx]
    Xte_e = X[i:i+1]
    # Ridge
    sce = StandardScaler()
    Xtr_e_sc = sce.fit_transform(Xtr_e); Xte_e_sc = sce.transform(Xte_e)
    r = LogisticRegression(C=0.5, penalty='l2', max_iter=2000, class_weight='balanced',
                            solver='lbfgs', random_state=42)
    r.fit(Xtr_e_sc, ytr_e)
    p_r = r.predict_proba(Xte_e_sc)[0, 1]
    # XGB
    pos_w_e = (1 - ytr_e.mean()) / max(ytr_e.mean(), 1e-9)
    xb = xgb.XGBClassifier(n_estimators=200, max_depth=4, learning_rate=0.05,
        scale_pos_weight=pos_w_e, random_state=42, eval_metric='logloss', verbosity=0, n_jobs=4)
    xb.fit(Xtr_e, ytr_e)
    p_x = xb.predict_proba(Xte_e)[0, 1]
    # GB
    gb = GradientBoostingClassifier(n_estimators=200, max_depth=4, learning_rate=0.05, random_state=42)
    gb.fit(Xtr_e, ytr_e)
    p_g = gb.predict_proba(Xte_e)[0, 1]
    ridge_preds_ex.append(p_r)
    ens_preds_ex.append((p_r + p_x + p_g) / 3)
    y_ex.append(y[i])
    dates_ex.append(dates.iloc[i])

y_ex = np.array(y_ex)
ridge_preds_ex = np.array(ridge_preds_ex)
ens_preds_ex = np.array(ens_preds_ex)
print(f"  Expanding OOS n={len(y_ex)} months, base rate {y_ex.mean()*100:.1f}%")
print(f"    Ridge PR-AUC: {average_precision_score(y_ex, ridge_preds_ex):.4f}  lift={average_precision_score(y_ex, ridge_preds_ex)/y_ex.mean():.2f}x")
print(f"    top3 ensemble PR-AUC: {average_precision_score(y_ex, ens_preds_ex):.4f}  lift={average_precision_score(y_ex, ens_preds_ex)/y_ex.mean():.2f}x")
print(f"    Ridge ROC-AUC: {roc_auc_score(y_ex, ridge_preds_ex):.4f}")
print(f"    top3 ROC-AUC: {roc_auc_score(y_ex, ens_preds_ex):.4f}")

# Hold-out subset (2024-08+)
ho_mask = pd.Series(dates_ex) >= pd.Timestamp('2024-08-01')
ho_mask = ho_mask.values
if ho_mask.sum() > 5:
    print(f"\n  Hold-out subset (2024-08+, n={ho_mask.sum()}):")
    print(f"    Ridge: {average_precision_score(y_ex[ho_mask], ridge_preds_ex[ho_mask]):.4f}")
    print(f"    top3:  {average_precision_score(y_ex[ho_mask], ens_preds_ex[ho_mask]):.4f}")

# Bootstrap CI on full expanding OOS
B = 5000; np.random.seed(42); n = len(y_ex)
prs_ens = []
for b in range(B):
    idx = np.random.choice(n, n, replace=True)
    if y_ex[idx].sum() < 5: continue
    prs_ens.append(average_precision_score(y_ex[idx], ens_preds_ex[idx]))
prs_ens = np.array(prs_ens)
print(f"\n  top3 ensemble bootstrap CI 95% (full expanding): "
      f"[{np.quantile(prs_ens, 0.025):.4f}, {np.quantile(prs_ens, 0.975):.4f}]  "
      f"P(>2x)={(prs_ens > 2*y_ex.mean()).mean():.3f}")

audit = {
    'cycle': '58CC_ABC',
    'A_bootstrap_ridge': {
        'n_boot': len(preds_boot),
        'ensemble_pr_auc': float(pr_boot_ens),
        'per_boot_mean_pr_auc': float(prs_per_boot.mean()),
        'per_boot_std_pr_auc': float(prs_per_boot.std()),
        'per_boot_range': [float(prs_per_boot.min()), float(prs_per_boot.max())],
    },
    'B_top15_features': {
        'top15': top15_names,
        'top15_ridge_pr_auc': float(average_precision_score(y_te, preds15['ridge15'])),
        'top15_ensemble_pr_auc': float(pr_ens15),
    },
    'C_expanding_oos': {
        'n_months': int(len(y_ex)),
        'base_rate': float(y_ex.mean()),
        'ridge_pr_auc': float(average_precision_score(y_ex, ridge_preds_ex)),
        'ens_pr_auc': float(average_precision_score(y_ex, ens_preds_ex)),
        'ridge_roc_auc': float(roc_auc_score(y_ex, ridge_preds_ex)),
        'ens_roc_auc': float(roc_auc_score(y_ex, ens_preds_ex)),
        'bootstrap_ci': [float(np.quantile(prs_ens, 0.025)), float(np.quantile(prs_ens, 0.975))],
        'p_lift_gt_2x': float((prs_ens > 2*y_ex.mean()).mean()),
    },
}
OUT.write_text(json.dumps(audit, indent=2, ensure_ascii=False))
print(f"\nSaved: {OUT}")
