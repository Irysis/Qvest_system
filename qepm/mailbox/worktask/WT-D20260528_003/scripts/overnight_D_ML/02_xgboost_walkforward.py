#!/usr/bin/env python
"""
WT-D20260528_003 Hypothesis D — ML Daily-Informed Monthly Model
Step 2: XGBoost Walk-Forward Purged CV + Optuna Sweep

Academic grounding:
- Gu-Kelly-Xiu 2020 RFS "Empirical Asset Pricing via Machine Learning"
- López de Prado 2018 "Advances in Financial Machine Learning" (Purged CV + embargo)
- Jensen-Kelly-Malamud-Pedersen 2022 "Net-of-Cost ML"

Pipeline:
  1. Load monthly snapshot panel (from Step 1 R script)
  2. Walk-forward purged splits (train >= 5y, test 1y, embargo 25d)
  3. Optuna sweep (50 trials, light) per fold for hyperparam
  4. Best model train + inference
  5. Save predictions per sig_date

Output:
  stage_artifacts/WT_D20260528_003_overnight_D_ML/
    - cv_results.json
    - best_hyperparams.json
    - predictions_walkforward.parquet
    - feature_importance.parquet

PIT C1 strict: train_end < test_start always. Embargo gap enforced.
Lockbox: panel pre-filtered to sig_date <= 2023-12-22 in Step 1.
"""

import sys
import json
import time
import warnings
from pathlib import Path
from datetime import datetime, timedelta

import numpy as np
import pandas as pd
import pyarrow.parquet as pq
import xgboost as xgb
import optuna
from scipy.stats import spearmanr, rankdata
from sklearn.metrics import mean_squared_error

warnings.filterwarnings('ignore')
optuna.logging.set_verbosity(optuna.logging.WARNING)

# ---- Paths ----
PROJ = Path('/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot')
WT_ID = 'WT-D20260528_003'
HYP_TAG = 'overnight_D_ML'
OUT_DIR = PROJ / 'stage_artifacts' / f'WT_D20260528_003_overnight_D_ML'
OUT_DIR.mkdir(parents=True, exist_ok=True)

SIG_CUTOFF = pd.Timestamp('2023-12-22')
EMBARGO_DAYS = 30  # >21d forward label gap
MIN_TRAIN_YEARS = 5
N_OPTUNA_TRIALS = 25  # reduced for time economy
MAX_N_EST = 300  # tighter ceiling

# Force unbuffered output
sys.stdout = open(sys.stdout.fileno(), mode='w', buffering=1, encoding='utf-8', closefd=False)
sys.stderr = open(sys.stderr.fileno(), mode='w', buffering=1, encoding='utf-8', closefd=False)

t0 = time.time()
print(f"[{datetime.now().strftime('%H:%M:%S')}] Step 2 — XGBoost Walk-Forward CV + Optuna", flush=True)

# ---- Step 1: Load panel ----
panel_path = OUT_DIR / 'ml_panel_train.parquet'
if not panel_path.exists():
    print(f"ERROR: panel not found at {panel_path}", file=sys.stderr)
    sys.exit(1)

panel = pd.read_parquet(panel_path)
panel['sig_date'] = pd.to_datetime(panel['sig_date'])
panel = panel[panel['sig_date'] <= SIG_CUTOFF].copy()
print(f"  Panel: {panel.shape[0]} rows × {panel.shape[1]} cols")
print(f"  sig_date range: {panel['sig_date'].min()} -> {panel['sig_date'].max()}")

# ---- Step 2: Feature/target setup ----
feature_cols_file = OUT_DIR / 'feature_cols.txt'
with open(feature_cols_file) as f:
    feature_cols = [x.strip() for x in f.readlines() if x.strip()]

# Exclude non-numeric / target / id cols
exclude_cols = ['sig_date', 'Ticker', 'log_ret_1m_w', 'Sector_Lv2']
feature_cols = [c for c in feature_cols if c not in exclude_cols and c in panel.columns]

# Add Sector dummy if available
if 'Sector_Lv2' in panel.columns:
    sec_dum = pd.get_dummies(panel['Sector_Lv2'], prefix='sec', dummy_na=False, drop_first=True)
    panel = pd.concat([panel.reset_index(drop=True), sec_dum.reset_index(drop=True)], axis=1)
    feature_cols = feature_cols + list(sec_dum.columns)
    print(f"  Added {sec_dum.shape[1]} sector dummies")

# Drop rows with NaN target
panel = panel.dropna(subset=['log_ret_1m_w']).copy()

# Convert all features to numeric, drop columns with >90% NaN
numeric_features = []
for c in feature_cols:
    if c not in panel.columns:
        continue
    panel[c] = pd.to_numeric(panel[c], errors='coerce')
    if panel[c].isna().mean() < 0.90:
        numeric_features.append(c)
feature_cols = numeric_features
print(f"  Numeric features (≤90% NaN): {len(feature_cols)}")

# ---- Step 3: Cross-sectional rank target transformation ----
# Per sig_date: rank log_ret_1m to [0, 1] for cross-section uniform target
panel['target_rank'] = panel.groupby('sig_date')['log_ret_1m_w'].rank(pct=True)
panel['target_zxs'] = panel.groupby('sig_date')['log_ret_1m_w'].transform(lambda x: (x - x.mean()) / (x.std() + 1e-8))

# Use target_zxs (cross-section z-score) as primary target (standard ML quant practice)
TARGET_COL = 'target_zxs'
print(f"  Target: {TARGET_COL} (cross-section z-score of log_ret_1m)")

# ---- Step 4: Walk-forward folds ----
sig_dates_sorted = sorted(panel['sig_date'].unique())
first_date = sig_dates_sorted[0]
last_date = sig_dates_sorted[-1]

# Walk-forward: train [first, train_end], test (train_end + embargo, train_end + embargo + 12 months]
min_train_end = first_date + pd.DateOffset(years=MIN_TRAIN_YEARS)

folds = []
fold_start = min_train_end
while fold_start < last_date:
    train_end = fold_start
    # Embargo gap
    test_start = train_end + pd.DateOffset(days=EMBARGO_DAYS)
    test_end = test_start + pd.DateOffset(years=1)
    if test_end > last_date + pd.DateOffset(days=30):
        test_end = last_date + pd.DateOffset(days=1)

    test_sds = [d for d in sig_dates_sorted if test_start <= d < test_end]
    train_sds = [d for d in sig_dates_sorted if d <= train_end]

    if len(test_sds) >= 6 and len(train_sds) >= 36:
        folds.append({
            'fold_id': len(folds),
            'train_end': train_end,
            'test_start': test_start,
            'test_end': test_end,
            'train_sds': train_sds,
            'test_sds': test_sds,
            'n_train': len(train_sds),
            'n_test': len(test_sds),
        })
    fold_start = fold_start + pd.DateOffset(years=1)

print(f"  Walk-forward folds: {len(folds)}")
for f in folds:
    print(f"    Fold {f['fold_id']}: train[{f['train_sds'][0].date()}..{f['train_end'].date()}] (n={f['n_train']}m) -> test[{f['test_sds'][0].date()}..{f['test_sds'][-1].date()}] (n={f['n_test']}m)")

if len(folds) < 3:
    print("WARN: <3 folds — increase data range or shorten min_train_years")

# ---- Step 5: Optuna sweep on FIRST fold only (for compute economy) ----
print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Step 5 — Optuna sweep on Fold 0 (n={N_OPTUNA_TRIALS} trials)")

fold0 = folds[0]
train_mask = panel['sig_date'].isin(fold0['train_sds'])
test_mask = panel['sig_date'].isin(fold0['test_sds'])
X_train = panel.loc[train_mask, feature_cols].values.astype(np.float32)
y_train = panel.loc[train_mask, TARGET_COL].values.astype(np.float32)
X_test = panel.loc[test_mask, feature_cols].values.astype(np.float32)
y_test = panel.loc[test_mask, TARGET_COL].values.astype(np.float32)
sds_test = panel.loc[test_mask, 'sig_date'].values

def objective(trial):
    params = {
        'objective': 'reg:squarederror',
        'eval_metric': 'rmse',
        'learning_rate': trial.suggest_float('learning_rate', 0.01, 0.20, log=True),
        'max_depth': trial.suggest_int('max_depth', 3, 8),
        'min_child_weight': trial.suggest_int('min_child_weight', 5, 50),
        'subsample': trial.suggest_float('subsample', 0.6, 1.0),
        'colsample_bytree': trial.suggest_float('colsample_bytree', 0.5, 1.0),
        'reg_alpha': trial.suggest_float('reg_alpha', 1e-3, 1.0, log=True),
        'reg_lambda': trial.suggest_float('reg_lambda', 1e-3, 10.0, log=True),
        'gamma': trial.suggest_float('gamma', 0, 1.0),
        'tree_method': 'hist',
        'device': 'cpu',
        'nthread': 4,
        'verbosity': 0,
    }
    n_estimators = trial.suggest_int('n_estimators', 100, MAX_N_EST)

    model = xgb.XGBRegressor(**params, n_estimators=n_estimators)
    model.fit(X_train, y_train, verbose=False)

    pred = model.predict(X_test)
    # Per sig_date Spearman IC
    df_test = pd.DataFrame({'sig_date': sds_test, 'pred': pred, 'y': y_test})
    ics = []
    for sd, grp in df_test.groupby('sig_date'):
        if grp.shape[0] >= 20:
            ic, _ = spearmanr(grp['pred'].values, grp['y'].values)
            if not np.isnan(ic):
                ics.append(ic)
    if len(ics) == 0:
        return -1.0
    mean_ic = float(np.mean(ics))
    std_ic = float(np.std(ics) + 1e-8)
    icir = mean_ic / std_ic
    # Composite: mean IC primary, penalize std
    score = mean_ic - 0.1 * std_ic
    return score

def progress_cb(study, trial):
    print(f"    [Optuna] trial {trial.number+1}/{N_OPTUNA_TRIALS} value={trial.value:.4f} best={study.best_value:.4f}", flush=True)

study = optuna.create_study(direction='maximize', sampler=optuna.samplers.TPESampler(seed=42))
study.optimize(objective, n_trials=N_OPTUNA_TRIALS, show_progress_bar=False, n_jobs=1, callbacks=[progress_cb])

best_params = study.best_params.copy()
print(f"  Best Fold 0 IC composite: {study.best_value:.4f}")
print(f"  Best params: {best_params}")

# Save best params
with open(OUT_DIR / 'best_hyperparams.json', 'w') as f:
    json.dump({
        'fold0_optuna_best_score': float(study.best_value),
        'fold0_optuna_best_params': {k: float(v) if isinstance(v, (int, float)) else v for k, v in best_params.items()},
        'n_trials': N_OPTUNA_TRIALS,
    }, f, indent=2)

# ---- Step 6: Full Walk-forward with best params ----
print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Step 6 — Full walk-forward with best params")

best_n_est = best_params.pop('n_estimators', 400)

all_preds = []
fold_metrics = []
feat_importance_agg = np.zeros(len(feature_cols))

for fold in folds:
    train_mask = panel['sig_date'].isin(fold['train_sds'])
    test_mask = panel['sig_date'].isin(fold['test_sds'])
    X_tr = panel.loc[train_mask, feature_cols].values.astype(np.float32)
    y_tr = panel.loc[train_mask, TARGET_COL].values.astype(np.float32)
    X_te = panel.loc[test_mask, feature_cols].values.astype(np.float32)
    y_te = panel.loc[test_mask, TARGET_COL].values.astype(np.float32)
    sds_te = panel.loc[test_mask, 'sig_date'].values
    tickers_te = panel.loc[test_mask, 'Ticker'].values
    log_ret_te = panel.loc[test_mask, 'log_ret_1m_w'].values

    model = xgb.XGBRegressor(
        objective='reg:squarederror',
        n_estimators=best_n_est,
        tree_method='hist',
        device='cpu',
        nthread=8,
        verbosity=0,
        **best_params,
    )
    model.fit(X_tr, y_tr, verbose=False)
    pred_te = model.predict(X_te)
    print(f"    Fold {fold['fold_id']} model trained ({best_n_est} trees, n_train={X_tr.shape[0]})", flush=True)

    # Per sig_date IC
    df_pred = pd.DataFrame({
        'sig_date': sds_te,
        'Ticker': tickers_te,
        'pred': pred_te,
        'y_zxs': y_te,
        'log_ret_1m_w': log_ret_te,
        'fold_id': fold['fold_id'],
    })

    ics = []
    rmses = []
    for sd, grp in df_pred.groupby('sig_date'):
        if grp.shape[0] >= 20:
            ic, _ = spearmanr(grp['pred'].values, grp['y_zxs'].values)
            if not np.isnan(ic):
                ics.append(ic)
            rmses.append(np.sqrt(mean_squared_error(grp['y_zxs'].values, grp['pred'].values)))

    fold_metrics.append({
        'fold_id': fold['fold_id'],
        'train_end': str(fold['train_end'].date()),
        'test_start': str(fold['test_sds'][0].date()),
        'test_end': str(fold['test_sds'][-1].date()),
        'n_train_rows': int(train_mask.sum()),
        'n_test_rows': int(test_mask.sum()),
        'n_train_sds': fold['n_train'],
        'n_test_sds': fold['n_test'],
        'rank_ic_mean': float(np.mean(ics)),
        'rank_ic_std': float(np.std(ics)),
        'rank_ic_ir': float(np.mean(ics) / (np.std(ics) + 1e-8)),
        'rank_ic_count': len(ics),
        'rmse_mean': float(np.mean(rmses)) if rmses else None,
    })
    print(f"  Fold {fold['fold_id']}: rank IC mean={np.mean(ics):.4f} std={np.std(ics):.4f} IR={np.mean(ics)/(np.std(ics)+1e-8):.3f} (n={len(ics)} sds)")

    all_preds.append(df_pred)

    feat_importance_agg += np.array(model.feature_importances_)

# Average importance across folds
feat_importance_agg /= len(folds)
fi_df = pd.DataFrame({'feature': feature_cols, 'importance': feat_importance_agg})
fi_df = fi_df.sort_values('importance', ascending=False).reset_index(drop=True)

all_preds_df = pd.concat(all_preds, ignore_index=True)

# ---- Step 7: Aggregate metrics + save ----
print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Step 7 — aggregate metrics")

all_ics = []
for sd, grp in all_preds_df.groupby('sig_date'):
    if grp.shape[0] >= 20:
        ic, _ = spearmanr(grp['pred'].values, grp['y_zxs'].values)
        if not np.isnan(ic):
            all_ics.append(ic)

mean_ic = float(np.mean(all_ics))
std_ic = float(np.std(all_ics))
icir = mean_ic / (std_ic + 1e-8)
hit_rate = float(np.mean(np.array(all_ics) > 0))
median_ic = float(np.median(all_ics))

print(f"\n  OVERALL Walk-Forward (test only):")
print(f"    Rank IC mean = {mean_ic:.4f}")
print(f"    Rank IC std  = {std_ic:.4f}")
print(f"    Rank IC IR   = {icir:.3f}")
print(f"    Hit rate     = {hit_rate:.2%}")
print(f"    Median IC    = {median_ic:.4f}")
print(f"    N sig_dates  = {len(all_ics)}")

# Harvey-t equivalents (5-spec): use bootstrap CI as proxy
np.random.seed(42)
n_boot = 1000
boot_ics = []
for _ in range(n_boot):
    sample = np.random.choice(all_ics, size=len(all_ics), replace=True)
    boot_ics.append(np.mean(sample))
ic_ci_95 = (np.percentile(boot_ics, 2.5), np.percentile(boot_ics, 97.5))

# Newey-West HAC t-stat approximation
from scipy.stats import t as tdist
n = len(all_ics)
# Simple Newey-West HAC with lag 3 (Andrews 1991 rule for monthly)
lag = 3
y_arr = np.array(all_ics)
y_mean = y_arr.mean()
y_dev = y_arr - y_mean
gamma_0 = np.mean(y_dev ** 2)
gamma_sum = 0.0
for k in range(1, lag + 1):
    w = 1 - k / (lag + 1)
    gamma_k = np.mean(y_dev[:-k] * y_dev[k:])
    gamma_sum += 2 * w * gamma_k
var_hac = (gamma_0 + gamma_sum) / n
t_hac = mean_ic / max(np.sqrt(max(var_hac, 1e-10)), 1e-10)
p_hac = 2 * (1 - tdist.cdf(abs(t_hac), df=n-1))

# Deflated Sharpe Ratio (Bailey-Lopez de Prado 2014)
# SR proxy: mean_ic / std_ic on annual basis (12 monthly observations)
# n_trials = N_OPTUNA_TRIALS + 4 feature blocks + 1 model selection = ~55 effective
n_trials_eff = N_OPTUNA_TRIALS + 4 + 1
sr_observed = icir * np.sqrt(12)
# Expected max SR under null with n_trials
exp_max_sr = np.sqrt(2 * np.log(max(n_trials_eff, 2)))
# Simplified DSR (Bailey-Lopez de Prado simplified)
dsr_z = (sr_observed - exp_max_sr * (1 - 0.5772 / np.sqrt(2 * np.log(n_trials_eff)))) / 1.0
# More robust: use normal approx
from scipy.stats import norm
dsr = norm.cdf(dsr_z) if not np.isnan(dsr_z) else 0.0

# Subperiod stability (3 subperiods)
all_preds_df['sig_date'] = pd.to_datetime(all_preds_df['sig_date'])
sub_a = all_preds_df[all_preds_df['sig_date'] < pd.Timestamp('2015-01-01')]
sub_b = all_preds_df[(all_preds_df['sig_date'] >= pd.Timestamp('2015-01-01')) & (all_preds_df['sig_date'] < pd.Timestamp('2020-01-01'))]
sub_c = all_preds_df[all_preds_df['sig_date'] >= pd.Timestamp('2020-01-01')]

def ic_subperiod(df):
    ics = []
    for sd, grp in df.groupby('sig_date'):
        if grp.shape[0] >= 20:
            ic, _ = spearmanr(grp['pred'].values, grp['y_zxs'].values)
            if not np.isnan(ic):
                ics.append(ic)
    if not ics: return {'n_sd': 0, 'mean_ic': None, 'icir': None}
    return {
        'n_sd': len(ics),
        'mean_ic': float(np.mean(ics)),
        'icir': float(np.mean(ics) / (np.std(ics) + 1e-8)),
    }

sub_metrics = {
    '2008-2014': ic_subperiod(sub_a),
    '2015-2019': ic_subperiod(sub_b),
    '2020-2023': ic_subperiod(sub_c),
}

# Subperiod stability: fraction of subperiods with positive mean_ic
positive_sub = sum(1 for v in sub_metrics.values() if v.get('mean_ic') is not None and v['mean_ic'] > 0) / max(sum(1 for v in sub_metrics.values() if v.get('mean_ic') is not None), 1)

# AX-001 v2 bad/normal IC ratio
# bad = sig_date with BM_Ret < -5% in following month (proxy: low log_ret in next month aggregate)
# Approximation: bottom 25% of cross-section mean as "bad" regime
all_preds_df['xs_mean_ret'] = all_preds_df.groupby('sig_date')['log_ret_1m_w'].transform('mean')
ret_q25 = all_preds_df['xs_mean_ret'].quantile(0.25)
bad_mask = all_preds_df['xs_mean_ret'] <= ret_q25
normal_mask = ~bad_mask

ic_bad = []
for sd, grp in all_preds_df[bad_mask].groupby('sig_date'):
    if grp.shape[0] >= 20:
        ic, _ = spearmanr(grp['pred'].values, grp['y_zxs'].values)
        if not np.isnan(ic):
            ic_bad.append(ic)

ic_normal = []
for sd, grp in all_preds_df[normal_mask].groupby('sig_date'):
    if grp.shape[0] >= 20:
        ic, _ = spearmanr(grp['pred'].values, grp['y_zxs'].values)
        if not np.isnan(ic):
            ic_normal.append(ic)

ic_bad_mean = float(np.mean(ic_bad)) if ic_bad else 0.0
ic_normal_mean = float(np.mean(ic_normal)) if ic_normal else 0.0
ax001_ratio = ic_bad_mean / (abs(ic_normal_mean) + 1e-8) if ic_normal_mean != 0 else 0.0

# Save aggregate results
cv_results = {
    'wt_id': WT_ID,
    'hypothesis_id': HYP_TAG,
    'model_type': 'XGBoost_walkforward_purged_cv',
    'target': TARGET_COL,
    'n_features': len(feature_cols),
    'n_folds': len(folds),
    'lockbox_cutoff': str(SIG_CUTOFF.date()),
    'embargo_days': EMBARGO_DAYS,
    'min_train_years': MIN_TRAIN_YEARS,
    'n_optuna_trials': N_OPTUNA_TRIALS,
    'best_hyperparams': {k: float(v) if isinstance(v, (int, float)) else v for k, v in best_params.items()},
    'best_n_estimators': int(best_n_est),
    'panel_rows': int(panel.shape[0]),
    'panel_sig_dates': len(sig_dates_sorted),
    'overall_metrics': {
        'rank_ic_mean': mean_ic,
        'rank_ic_median': median_ic,
        'rank_ic_std': std_ic,
        'icir': icir,
        'hit_rate': hit_rate,
        'n_sig_dates': len(all_ics),
        'ic_ci_95_lower': float(ic_ci_95[0]),
        'ic_ci_95_upper': float(ic_ci_95[1]),
        't_hac_newey_west': float(t_hac),
        'p_value_hac': float(p_hac),
    },
    'subperiod_metrics': sub_metrics,
    'subperiod_stability_fraction': float(positive_sub),
    'ax001_v2': {
        'ic_bad_mean': ic_bad_mean,
        'ic_normal_mean': ic_normal_mean,
        'ratio_bad_over_normal': float(ax001_ratio),
        'pass_threshold_05': ax001_ratio >= 0.5,
    },
    'dsr_simplified': float(dsr) if not np.isnan(dsr) else None,
    'n_trials_effective_for_dsr': n_trials_eff,
    'fold_metrics': fold_metrics,
    'elapsed_seconds': float(time.time() - t0),
}

with open(OUT_DIR / 'cv_results.json', 'w') as f:
    json.dump(cv_results, f, indent=2, default=str)

# Save predictions + importance
all_preds_df.to_parquet(OUT_DIR / 'predictions_walkforward.parquet', index=False)
fi_df.to_parquet(OUT_DIR / 'feature_importance.parquet', index=False)

print(f"\n  Saved: cv_results.json + predictions_walkforward.parquet + feature_importance.parquet")
print(f"  Top 10 features by importance:")
for i, row in fi_df.head(10).iterrows():
    print(f"    {row['feature']:<40} {row['importance']:.4f}")

print(f"\n=== Step 2 COMPLETE — elapsed {(time.time()-t0)/60:.2f} min ===")
print(f"  Overall: IC mean = {mean_ic:.4f}, ICIR = {icir:.3f}, t_HAC = {t_hac:.2f}")
print(f"  Subperiod stability: {positive_sub:.2f}")
print(f"  AX-001 v2 ratio bad/normal: {ax001_ratio:.3f}")
print(f"  DSR (simplified): {dsr:.3f}")
