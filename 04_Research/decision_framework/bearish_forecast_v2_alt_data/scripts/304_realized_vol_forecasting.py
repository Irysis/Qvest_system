#!/usr/bin/env python3
"""304_realized_vol_forecasting.py — Cycle 58DD

진정 different paradigm: realized vol regression instead of binary classification.
가설: vol forecasting 더 stable signal (return direction보다 easier).
Convert vol prediction → bear probability via empirical mapping.

Path:
  Target: future 21d realized vol (continuous)
  Model: XGBoost regressor on monthly features
  Conversion: P(y_tail_q15 = 1 | vol_pred) via train empirical mapping
  Evaluation: monthly hold-out PR-AUC vs daily baseline
"""
import json
from pathlib import Path
import pandas as pd
import numpy as np
import xgboost as xgb
from sklearn.metrics import average_precision_score, roc_auc_score, r2_score
from sklearn.linear_model import Ridge
from sklearn.preprocessing import StandardScaler
import warnings
warnings.filterwarnings('ignore')

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = (PROJECT_ROOT /
      "04_Research/decision_framework/bearish_forecast_v2_alt_data")
IN = WS / "outputs/01_data/monthly_features.parquet"
OUT = WS / "outputs/04_evaluation/cycle58dd_realized_vol.json"

# Load monthly features + add realized vol target
d = pd.read_parquet(IN)
d['Date'] = pd.to_datetime(d['Date'])
d = d.sort_values('Date').reset_index(drop=True)

# Build realized vol target — forward 21d realized vol
bm = pd.read_parquet(PROJECT_ROOT / ".cache/benchmark.parquet")
bm['Date'] = pd.to_datetime(bm['Date'])
bm = bm.sort_values('Date').reset_index(drop=True)
bm['ret_1d'] = bm['BM_Close'].pct_change()

# Forward 21d realized vol per date
def fwd_vol(rets, h=21):
    n = len(rets); out = np.full(n, np.nan)
    for i in range(n - h):
        win = rets.iloc[i+1:i+h+1].values  # forward, exclude today
        if len(win) >= h and np.isfinite(win).all():
            out[i] = win.std() * np.sqrt(252)  # annualized
    return out
bm['fwd_vol_21'] = fwd_vol(bm['ret_1d'], 21)

# Merge with monthly features
d_m = d.merge(bm[['Date', 'fwd_vol_21']], on='Date', how='left')

# Features + targets
non_feat = ['Date', 'y_tail_q15', 'fwd_dd_21', 'y_dd_8pct', 'fwd_vol_21']
feat_cols = [c for c in d_m.columns if c not in non_feat]
d_m = d_m.dropna(subset=['y_tail_q15', 'fwd_vol_21'])
d_m[feat_cols] = d_m[feat_cols].ffill().bfill().replace([np.inf, -np.inf], np.nan).clip(-1e6, 1e6).fillna(0)

X = d_m[feat_cols].values
y_cls = d_m['y_tail_q15'].values  # binary target
y_reg = d_m['fwd_vol_21'].values  # continuous target (annualized vol)
dates = pd.to_datetime(d_m['Date'])
print(f"Monthly: {len(d_m)} rows × {len(feat_cols)} features")
print(f"  y_tail_q15 base rate: {y_cls.mean()*100:.1f}%")
print(f"  fwd_vol_21 range: [{y_reg.min():.3f}, {y_reg.max():.3f}], mean={y_reg.mean():.3f}")

# Split
test_mask = (dates >= pd.Timestamp('2024-08-01')).values
X_tr, y_cls_tr, y_reg_tr = X[~test_mask], y_cls[~test_mask], y_reg[~test_mask]
X_te, y_cls_te, y_reg_te = X[test_mask], y_cls[test_mask], y_reg[test_mask]
print(f"\nTrain: {len(y_cls_tr)} months, Test: {len(y_cls_te)} months")

# ============================================================
# Vol regression: XGBoost + Ridge
# ============================================================
print("\n=== Vol regression ===")
sc = StandardScaler()
X_tr_sc = sc.fit_transform(X_tr); X_te_sc = sc.transform(X_te)

xgb_reg = xgb.XGBRegressor(n_estimators=200, max_depth=4, learning_rate=0.05,
    random_state=42, verbosity=0, n_jobs=4)
xgb_reg.fit(X_tr, y_reg_tr)
vol_pred_xgb = xgb_reg.predict(X_te)

ridge_reg = Ridge(alpha=1.0, random_state=42)
ridge_reg.fit(X_tr_sc, y_reg_tr)
vol_pred_ridge = ridge_reg.predict(X_te_sc)

r2_xgb = r2_score(y_reg_te, vol_pred_xgb)
r2_ridge = r2_score(y_reg_te, vol_pred_ridge)
print(f"  XGB vol R²:   {r2_xgb:.4f}")
print(f"  Ridge vol R²: {r2_ridge:.4f}")
# Correlation
from scipy.stats import spearmanr
sp_xgb, _ = spearmanr(vol_pred_xgb, y_reg_te)
sp_ridge, _ = spearmanr(vol_pred_ridge, y_reg_te)
print(f"  XGB Spearman ρ:   {sp_xgb:.4f}")
print(f"  Ridge Spearman ρ: {sp_ridge:.4f}")

# ============================================================
# Conversion: vol_pred → bear probability
# Empirical mapping from train: P(y_tail_q15=1 | vol_pred quantile)
# ============================================================
print("\n=== Conversion vol → bear probability ===")
# Use train data to estimate P(y=1 | vol_pred decile)
vol_pred_tr_xgb = xgb_reg.predict(X_tr)
vol_pred_tr_ridge = ridge_reg.predict(X_tr_sc)

# Method 1: Rank-based — vol_pred rank → bear prob
# Higher predicted vol → higher bear prob
def vol_to_bear_prob(vol_pred_te, vol_pred_tr, y_cls_tr):
    """Use train empirical: P(y=1 | vol_pred decile)."""
    n_bins = 10
    quantiles = np.quantile(vol_pred_tr, np.linspace(0, 1, n_bins+1))
    quantiles[0] = -np.inf; quantiles[-1] = np.inf
    # Train: per bin, P(y=1)
    bin_probs = np.zeros(n_bins)
    for b in range(n_bins):
        mask = (vol_pred_tr >= quantiles[b]) & (vol_pred_tr < quantiles[b+1])
        if mask.sum() > 5:
            bin_probs[b] = y_cls_tr[mask].mean()
        else:
            bin_probs[b] = y_cls_tr.mean()
    # Test: map to bin → prob
    test_bin = np.digitize(vol_pred_te, quantiles[1:-1])
    return bin_probs[test_bin]

# Also direct: P(y=1) ~ logistic(vol_pred)
# Or: just use vol_pred as score (high vol → high bear)
print("\n=== Direct comparison ===")
print("  Method 1: vol_pred raw as score (high vol → high bear)")
pr_xgb_raw = average_precision_score(y_cls_te, vol_pred_xgb)
pr_ridge_raw = average_precision_score(y_cls_te, vol_pred_ridge)
print(f"    XGB:   PR-AUC={pr_xgb_raw:.4f}  lift={pr_xgb_raw/y_cls_te.mean():.2f}x")
print(f"    Ridge: PR-AUC={pr_ridge_raw:.4f}  lift={pr_ridge_raw/y_cls_te.mean():.2f}x")

print("\n  Method 2: vol_pred → bear prob via empirical mapping")
bear_xgb = vol_to_bear_prob(vol_pred_xgb, vol_pred_tr_xgb, y_cls_tr)
bear_ridge = vol_to_bear_prob(vol_pred_ridge, vol_pred_tr_ridge, y_cls_tr)
pr_xgb_map = average_precision_score(y_cls_te, bear_xgb)
pr_ridge_map = average_precision_score(y_cls_te, bear_ridge)
print(f"    XGB → bear:   PR-AUC={pr_xgb_map:.4f}  lift={pr_xgb_map/y_cls_te.mean():.2f}x")
print(f"    Ridge → bear: PR-AUC={pr_ridge_map:.4f}  lift={pr_ridge_map/y_cls_te.mean():.2f}x")

# ============================================================
# Compare to direct classification (previous Cycle 58CC)
# ============================================================
print("\n=== Compare to direct classification (Cycle 58CC) ===")
print(f"  Direct binary Ridge:    PR-AUC 0.2159 (lift 2.27x)")
print(f"  Direct binary top3 ens: PR-AUC 0.2250 (lift 2.36x)")
print(f"  Vol→bear XGB:           PR-AUC {pr_xgb_map:.4f}")
print(f"  Vol→bear Ridge:         PR-AUC {pr_ridge_map:.4f}")
print(f"  Vol→bear ensemble:      PR-AUC {average_precision_score(y_cls_te, (bear_xgb+bear_ridge)/2):.4f}")

# Bootstrap on best vol→bear
print("\n=== Bootstrap CI (best vol→bear) ===")
B=5000; np.random.seed(42); n=len(y_cls_te)
best_p = (bear_xgb + bear_ridge) / 2
prs=[]
for b in range(B):
    idx = np.random.choice(n, n, replace=True)
    if y_cls_te[idx].sum() < 2: continue
    prs.append(average_precision_score(y_cls_te[idx], best_p[idx]))
prs=np.array(prs)
base = y_cls_te.mean()
print(f"  vol→bear ensemble CI 95%: [{np.quantile(prs,0.025):.4f}, {np.quantile(prs,0.975):.4f}]")
print(f"  Lift CI: [{np.quantile(prs,0.025)/base:.2f}x, {np.quantile(prs,0.975)/base:.2f}x]")
print(f"  P(lift > 2x) = {(prs > 2*base).mean():.3f}")

# Walk-forward expanding vol→bear
print("\n=== Walk-forward expanding vol→bear (99 months) ===")
test_start_idx = (dates >= pd.Timestamp('2018-01-01')).idxmax()
all_pred_xgb = []; all_pred_ridge = []; all_y = []
for i in range(test_start_idx, len(d_m) - 1):
    tr_idx = np.arange(0, i)
    if y_cls[tr_idx].sum() < 30: continue
    sc_e = StandardScaler(); Xtr_e_sc = sc_e.fit_transform(X[tr_idx]); Xte_e_sc = sc_e.transform(X[i:i+1])

    xb = xgb.XGBRegressor(n_estimators=200, max_depth=4, learning_rate=0.05, random_state=42, verbosity=0, n_jobs=4)
    xb.fit(X[tr_idx], y_reg[tr_idx])
    vol_te = xb.predict(X[i:i+1])
    vol_tr = xb.predict(X[tr_idx])
    p_x = vol_to_bear_prob(vol_te, vol_tr, y_cls[tr_idx])[0]

    rr = Ridge(alpha=1.0, random_state=42); rr.fit(Xtr_e_sc, y_reg[tr_idx])
    vol_te_r = rr.predict(Xte_e_sc); vol_tr_r = rr.predict(Xtr_e_sc)
    p_r = vol_to_bear_prob(vol_te_r, vol_tr_r, y_cls[tr_idx])[0]

    all_pred_xgb.append(p_x); all_pred_ridge.append(p_r); all_y.append(y_cls[i])

all_y = np.array(all_y); all_pred_xgb = np.array(all_pred_xgb); all_pred_ridge = np.array(all_pred_ridge)
all_ens = (all_pred_xgb + all_pred_ridge) / 2
print(f"  Expanding OOS n={len(all_y)} months, base={all_y.mean()*100:.1f}%")
print(f"    Vol→bear XGB:   {average_precision_score(all_y, all_pred_xgb):.4f}  lift={average_precision_score(all_y, all_pred_xgb)/all_y.mean():.2f}x")
print(f"    Vol→bear Ridge: {average_precision_score(all_y, all_pred_ridge):.4f}  lift={average_precision_score(all_y, all_pred_ridge)/all_y.mean():.2f}x")
print(f"    Vol→bear ens:   {average_precision_score(all_y, all_ens):.4f}  lift={average_precision_score(all_y, all_ens)/all_y.mean():.2f}x")

audit = {
    'cycle': '58DD_realized_vol_forecasting',
    'vol_r2_xgb': float(r2_xgb), 'vol_r2_ridge': float(r2_ridge),
    'holdout_vol_to_bear': {
        'xgb_pr_auc': float(pr_xgb_map), 'ridge_pr_auc': float(pr_ridge_map),
        'ensemble_pr_auc': float(average_precision_score(y_cls_te, (bear_xgb+bear_ridge)/2)),
    },
    'expanding_99mo': {
        'xgb_pr_auc': float(average_precision_score(all_y, all_pred_xgb)),
        'ridge_pr_auc': float(average_precision_score(all_y, all_pred_ridge)),
        'ensemble_pr_auc': float(average_precision_score(all_y, all_ens)),
    },
}
OUT.write_text(json.dumps(audit, indent=2, ensure_ascii=False))
print(f"\nSaved: {OUT}")
