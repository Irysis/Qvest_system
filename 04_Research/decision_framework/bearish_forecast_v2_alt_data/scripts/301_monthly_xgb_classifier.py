#!/usr/bin/env python3
"""301_monthly_xgb_classifier.py — Cycle 58CC Phase 2

도훈 mandate "성능 증명된 모델 (창의력 X)" — XGBoost + Ridge + LightGBM ensemble.
Monthly aggregate features (300 + monthly obs) → y_tail_q15 monthly prediction.

Walk-forward CV with 1-month embargo (monthly granularity natural purge).
Hold-out: 2024-08-2026-04 = 20 months strict.
"""
import os
import json
from pathlib import Path
import pandas as pd
import numpy as np
import xgboost as xgb
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import average_precision_score, roc_auc_score, brier_score_loss
from sklearn.preprocessing import StandardScaler
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = (PROJECT_ROOT /
      "04_Research/decision_framework/bearish_forecast_v2_alt_data")
IN = WS / "outputs/01_data/monthly_features.parquet"
OUT = WS / "outputs/04_evaluation/cycle58cc_monthly_classifier.json"

# Load
d = pd.read_parquet(IN)
d['Date'] = pd.to_datetime(d['Date'])
d = d.sort_values('Date').reset_index(drop=True)

# Drop rows with NaN in y or features
non_feat = ['Date', 'y_tail_q15', 'fwd_dd_21', 'y_dd_8pct']
feat_cols = [c for c in d.columns if c not in non_feat]
print(f"Features: {len(feat_cols)}, total rows: {len(d)}")

# Filter for valid y (forward 21d resolved)
d = d.dropna(subset=['y_tail_q15'])
print(f"After dropping unresolved y: {len(d)} rows")

# Forward fill features then drop remaining NaN
d[feat_cols] = d[feat_cols].ffill().bfill()
# Replace inf with NaN then clip extreme outliers
d[feat_cols] = d[feat_cols].replace([np.inf, -np.inf], np.nan)
d[feat_cols] = d[feat_cols].clip(lower=-1e6, upper=1e6)
d[feat_cols] = d[feat_cols].fillna(0)
# Drop remaining NaN (should be none after fill)
d = d.dropna(subset=feat_cols)
print(f"After ffill+inf-clip+fill: {len(d)} rows")

X = d[feat_cols].values
y = d['y_tail_q15'].values
dates = d['Date'].values
print(f"  base rate: {y.mean()*100:.1f}%, positives: {int(y.sum())}")

# Chronological train/test split — 80/20 (hold-out: 2024-08+)
test_start = pd.Timestamp('2024-08-01')
test_mask = (d['Date'] >= test_start).values
train_mask = ~test_mask
print(f"\nTrain: {train_mask.sum()} monthly, test: {test_mask.sum()} monthly")
print(f"  train pos rate: {y[train_mask].mean()*100:.1f}%, test pos rate: {y[test_mask].mean()*100:.1f}%")

X_tr, y_tr = X[train_mask], y[train_mask]
X_te, y_te = X[test_mask], y[test_mask]

# Models
def make_xgb(seed=42):
    pos_w = (1 - y_tr.mean()) / max(y_tr.mean(), 1e-9)
    return xgb.XGBClassifier(
        n_estimators=200, max_depth=4, learning_rate=0.05,
        scale_pos_weight=pos_w, random_state=seed,
        eval_metric='logloss', verbosity=0, n_jobs=4
    )

def make_ridge():
    return LogisticRegression(
        C=0.5, penalty='l2', max_iter=2000, class_weight='balanced',
        solver='lbfgs', random_state=42
    )

# Walk-forward CV (5 folds chronological + monthly purge = 1 month gap)
def walkforward_cv(X, y, n_folds=5):
    n = len(X)
    fold_size = n // (n_folds + 1)
    preds = np.full(n, np.nan)
    for fi in range(n_folds):
        tr_end = (fi + 1) * fold_size
        va_start = tr_end + 1  # 1 month gap (monthly granularity)
        va_end = min((fi + 2) * fold_size, n)
        if va_end <= va_start: continue
        tr_idx = np.arange(0, tr_end)
        va_idx = np.arange(va_start, va_end)

        mdl = make_xgb(seed=42)
        mdl.fit(X[tr_idx], y[tr_idx])
        preds[va_idx] = mdl.predict_proba(X[va_idx])[:, 1]
    return preds

# CV on train
print("\n=== Walk-forward CV (5-fold, 1-month embargo) on TRAIN ===")
oof_train = walkforward_cv(X_tr, y_tr, n_folds=5)
valid_oof = ~np.isnan(oof_train)
pr_oof = average_precision_score(y_tr[valid_oof], oof_train[valid_oof])
roc_oof = roc_auc_score(y_tr[valid_oof], oof_train[valid_oof])
brier_oof = brier_score_loss(y_tr[valid_oof], oof_train[valid_oof])
print(f"  OOF PR-AUC: {pr_oof:.4f}  (lift={pr_oof/y_tr[valid_oof].mean():.2f}x base {y_tr[valid_oof].mean()*100:.1f}%)")
print(f"  OOF ROC-AUC: {roc_oof:.4f}")
print(f"  OOF Brier: {brier_oof:.4f}")

# Final XGB on full train
print("\n=== Final model: train on full train, predict hold-out ===")
xgb_final = make_xgb(seed=42)
xgb_final.fit(X_tr, y_tr)
p_te_xgb = xgb_final.predict_proba(X_te)[:, 1]
pr_xgb = average_precision_score(y_te, p_te_xgb)
roc_xgb = roc_auc_score(y_te, p_te_xgb)
print(f"  XGBoost hold-out: PR-AUC={pr_xgb:.4f} (lift={pr_xgb/y_te.mean():.2f}x), ROC={roc_xgb:.4f}")

# Ridge baseline
scaler = StandardScaler()
X_tr_sc = scaler.fit_transform(X_tr); X_te_sc = scaler.transform(X_te)
ridge = make_ridge(); ridge.fit(X_tr_sc, y_tr)
p_te_ridge = ridge.predict_proba(X_te_sc)[:, 1]
pr_ridge = average_precision_score(y_te, p_te_ridge)
roc_ridge = roc_auc_score(y_te, p_te_ridge)
print(f"  Ridge hold-out:   PR-AUC={pr_ridge:.4f} (lift={pr_ridge/y_te.mean():.2f}x), ROC={roc_ridge:.4f}")

# Ensemble
p_te_ens = (p_te_xgb + p_te_ridge) / 2
pr_ens = average_precision_score(y_te, p_te_ens)
roc_ens = roc_auc_score(y_te, p_te_ens)
print(f"  Ensemble (XGB+Ridge): PR-AUC={pr_ens:.4f} (lift={pr_ens/y_te.mean():.2f}x), ROC={roc_ens:.4f}")

# Bootstrap CI
B = 5000; np.random.seed(42); n_te = len(y_te)
for name, p in [('XGB', p_te_xgb), ('Ridge', p_te_ridge), ('Ensemble', p_te_ens)]:
    prs = []
    for b in range(B):
        idx = np.random.choice(n_te, n_te, replace=True)
        if y_te[idx].sum() < 3: continue
        prs.append(average_precision_score(y_te[idx], p[idx]))
    prs = np.array(prs)
    print(f"  {name} bootstrap CI 95%: [{np.quantile(prs,0.025):.4f}, {np.quantile(prs,0.975):.4f}] "
          f"P(lift>2x)={(prs > 2*y_te.mean()).mean():.3f}")

# XGBoost feature importance
importance = xgb_final.feature_importances_
imp_df = pd.DataFrame({'feature': feat_cols, 'importance': importance}).sort_values('importance', ascending=False)
print(f"\n=== Top 15 XGBoost feature importance ===")
for _, row in imp_df.head(15).iterrows():
    bar = '█' * int(row['importance'] * 40)
    print(f"  {row['feature']:<45s}: {row['importance']:.4f} {bar}")

# Save
audit = {
    'cycle': '58CC_monthly_classifier',
    'task': 'y_tail_q15 monthly endpoint prediction',
    'n_train_months': int(train_mask.sum()),
    'n_test_months': int(test_mask.sum()),
    'n_features': len(feat_cols),
    'train_base_rate': float(y_tr.mean()),
    'test_base_rate': float(y_te.mean()),
    'oof_train_pr_auc': float(pr_oof),
    'oof_train_roc_auc': float(roc_oof),
    'holdout': {
        'xgb_pr_auc': float(pr_xgb), 'xgb_roc_auc': float(roc_xgb),
        'ridge_pr_auc': float(pr_ridge), 'ridge_roc_auc': float(roc_ridge),
        'ensemble_pr_auc': float(pr_ens), 'ensemble_roc_auc': float(roc_ens),
        'xgb_lift': float(pr_xgb/y_te.mean()),
        'ensemble_lift': float(pr_ens/y_te.mean()),
    },
    'top_features': imp_df.head(15)[['feature','importance']].to_dict('records')
}
OUT.write_text(json.dumps(audit, indent=2, ensure_ascii=False))
print(f"\nSaved: {OUT}")
