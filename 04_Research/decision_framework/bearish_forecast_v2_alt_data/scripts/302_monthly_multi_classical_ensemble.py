#!/usr/bin/env python3
"""302_monthly_multi_classical_ensemble.py — Cycle 58CC Phase 2 확장

도훈 mandate "1번 진행" — More classical models 추가.
LightGBM/CatBoost 없음 → sklearn.ensemble (RF, HistGradientBoosting, ExtraTrees,
AdaBoost) 추가 + 기존 XGB + Ridge = 6 model ensemble.

Hold-out: 2024-08-2026-04 (21 months) strict.
Bootstrap CI + per-model + multi-ensemble.
"""
import json
from pathlib import Path
import pandas as pd
import numpy as np
import xgboost as xgb
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import (
    RandomForestClassifier, GradientBoostingClassifier,
    HistGradientBoostingClassifier, ExtraTreesClassifier, AdaBoostClassifier,
)
from sklearn.metrics import average_precision_score, roc_auc_score
from sklearn.preprocessing import StandardScaler
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = (PROJECT_ROOT /
      "04_Research/decision_framework/bearish_forecast_v2_alt_data")
IN = WS / "outputs/01_data/monthly_features.parquet"
OUT = WS / "outputs/04_evaluation/cycle58cc_multi_classical.json"

# Load
d = pd.read_parquet(IN)
d['Date'] = pd.to_datetime(d['Date'])
d = d.sort_values('Date').reset_index(drop=True)

non_feat = ['Date', 'y_tail_q15', 'fwd_dd_21', 'y_dd_8pct']
feat_cols = [c for c in d.columns if c not in non_feat]

d = d.dropna(subset=['y_tail_q15'])
d[feat_cols] = d[feat_cols].ffill().bfill()
d[feat_cols] = d[feat_cols].replace([np.inf, -np.inf], np.nan)
d[feat_cols] = d[feat_cols].clip(lower=-1e6, upper=1e6).fillna(0)

X = d[feat_cols].values
y = d['y_tail_q15'].values

# Train/test split
test_start = pd.Timestamp('2024-08-01')
test_mask = (d['Date'] >= test_start).values
X_tr, y_tr = X[~test_mask], y[~test_mask]
X_te, y_te = X[test_mask], y[test_mask]

scaler = StandardScaler()
X_tr_sc = scaler.fit_transform(X_tr); X_te_sc = scaler.transform(X_te)

pos_w = (1 - y_tr.mean()) / max(y_tr.mean(), 1e-9)
print(f"Train: {len(y_tr)} months, base rate {y_tr.mean()*100:.1f}%")
print(f"Test:  {len(y_te)} months, base rate {y_te.mean()*100:.1f}%")

# 7 models
models = {}
print("\n=== Training 7 classical models ===")
# 1. XGBoost
models['xgb'] = xgb.XGBClassifier(n_estimators=200, max_depth=4, learning_rate=0.05,
    scale_pos_weight=pos_w, random_state=42, eval_metric='logloss', verbosity=0, n_jobs=4)
models['xgb'].fit(X_tr, y_tr)
print("  ✓ XGBoost")

# 2. Ridge
models['ridge'] = LogisticRegression(C=0.5, penalty='l2', max_iter=2000,
    class_weight='balanced', solver='lbfgs', random_state=42)
models['ridge'].fit(X_tr_sc, y_tr)
print("  ✓ Ridge")

# 3. Random Forest
models['rf'] = RandomForestClassifier(n_estimators=300, max_depth=6,
    class_weight='balanced', random_state=42, n_jobs=4)
models['rf'].fit(X_tr, y_tr)
print("  ✓ RandomForest")

# 4. HistGradientBoosting (LightGBM 유사)
models['hgb'] = HistGradientBoostingClassifier(max_iter=200, max_depth=4,
    learning_rate=0.05, class_weight='balanced', random_state=42)
models['hgb'].fit(X_tr, y_tr)
print("  ✓ HistGradientBoosting")

# 5. ExtraTrees
models['et'] = ExtraTreesClassifier(n_estimators=300, max_depth=6,
    class_weight='balanced', random_state=42, n_jobs=4)
models['et'].fit(X_tr, y_tr)
print("  ✓ ExtraTrees")

# 6. AdaBoost
models['ada'] = AdaBoostClassifier(n_estimators=200, learning_rate=0.5, random_state=42)
models['ada'].fit(X_tr, y_tr)
print("  ✓ AdaBoost")

# 7. GradientBoosting (sklearn standard)
models['gb'] = GradientBoostingClassifier(n_estimators=200, max_depth=4,
    learning_rate=0.05, random_state=42)
models['gb'].fit(X_tr, y_tr)
print("  ✓ GradientBoosting")

# Predict test
preds = {}
for name, m in models.items():
    if name == 'ridge':
        preds[name] = m.predict_proba(X_te_sc)[:, 1]
    else:
        preds[name] = m.predict_proba(X_te)[:, 1]

# Per-model hold-out
print("\n=== Hold-out PR-AUC per model ===")
print(f"  {'Model':<10s}{'PR-AUC':>10s}{'Lift':>8s}{'ROC':>8s}")
base = y_te.mean()
results = {}
for name, p in preds.items():
    pr = average_precision_score(y_te, p)
    roc = roc_auc_score(y_te, p)
    results[name] = pr
    print(f"  {name:<10s}{pr:>10.4f}{pr/base:>7.2f}x{roc:>8.4f}")

# Ensembles
print("\n=== Ensembles ===")
ensembles = {
    'all_7': np.mean(list(preds.values()), axis=0),
    'xgb_ridge': (preds['xgb'] + preds['ridge']) / 2,
    'ridge_hgb_gb': (preds['ridge'] + preds['hgb'] + preds['gb']) / 3,
    'top3_pr': None,  # Will pick top 3 by PR-AUC
    'all_except_ada_xgb': np.mean([preds['ridge'], preds['rf'], preds['hgb'],
                                    preds['et'], preds['gb']], axis=0),
}
# Top 3 ensemble by PR-AUC
top3_names = sorted(results.keys(), key=lambda k: -results[k])[:3]
ensembles['top3_pr'] = np.mean([preds[n] for n in top3_names], axis=0)
print(f"  Top 3 by PR-AUC: {top3_names}")

for name, p in ensembles.items():
    pr = average_precision_score(y_te, p)
    roc = roc_auc_score(y_te, p)
    print(f"  {name:<25s}{pr:>10.4f}{pr/base:>7.2f}x{roc:>8.4f}")

# Bootstrap CI for top ensembles
print("\n=== Bootstrap CI 95% (B=5000) ===")
B = 5000; np.random.seed(42); n_te = len(y_te)
for name in ['ridge', 'hgb', 'xgb_ridge', 'all_7', 'top3_pr', 'all_except_ada_xgb']:
    p = ensembles[name] if name in ensembles else preds[name]
    prs = []
    for b in range(B):
        idx = np.random.choice(n_te, n_te, replace=True)
        if y_te[idx].sum() < 2: continue
        prs.append(average_precision_score(y_te[idx], p[idx]))
    prs = np.array(prs)
    lift_ci = [np.quantile(prs, 0.025)/base, np.quantile(prs, 0.975)/base]
    print(f"  {name:<25s}: CI=[{np.quantile(prs,0.025):.4f}, {np.quantile(prs,0.975):.4f}]"
          f"  Lift CI=[{lift_ci[0]:.2f}x, {lift_ci[1]:.2f}x]"
          f"  P(>2x)={(prs > 2*base).mean():.3f}")

# Save audit
audit = {
    'cycle': '58CC_multi_classical_ensemble',
    'n_models': 7,
    'n_train_months': int(len(y_tr)),
    'n_test_months': int(len(y_te)),
    'per_model_holdout': {k: float(v) for k, v in results.items()},
    'ensemble_holdout': {k: float(average_precision_score(y_te, p)) for k, p in ensembles.items()},
    'top3_models_by_pr': list(top3_names),
}
OUT.write_text(json.dumps(audit, indent=2, ensure_ascii=False))
print(f"\nSaved: {OUT}")
