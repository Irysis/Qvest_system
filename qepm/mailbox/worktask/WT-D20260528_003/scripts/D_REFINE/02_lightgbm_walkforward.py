#!/usr/bin/env python
"""
WT-D20260528_003 Track 2 D REFINE — Step 2: LightGBM Walk-Forward with Optuna Full Sweep

Improvements vs D ML:
  - Algorithm: LightGBM (faster sparsity-aware) replacing XGBoost
  - Features: top 30 (pruned, curse-of-dim mitigation)
  - Optuna: 100 trials (full sweep) with composite objective:
      score = IC_mean - 0.2 * IC_std - 0.05 * turnover_proxy
    (turnover-penalty integrated)
  - Pruner: MedianPruner
  - Walk-forward: same as D ML (5y train + 30d embargo + 1y test, 10 folds)

PIT C1 strict: train_end < test_start always, embargo enforced.
Lockbox: panel pre-filtered to sig_date <= 2023-12-22.

Output:
  stage_artifacts/WT_D20260528_003_D_REFINE/
    - cv_results.json
    - best_hyperparams.json
    - predictions_walkforward.parquet
    - feature_importance.parquet
    - optuna_trial_log.json
"""

import sys
import json
import time
import warnings
from pathlib import Path
from datetime import datetime

import numpy as np
import pandas as pd
import lightgbm as lgb
import optuna
from optuna.pruners import MedianPruner
from scipy.stats import spearmanr
from sklearn.metrics import mean_squared_error

warnings.filterwarnings('ignore')
optuna.logging.set_verbosity(optuna.logging.WARNING)

PROJ = Path('/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot')
OUT_DIR = PROJ / 'stage_artifacts' / 'WT_D20260528_003_D_REFINE'
OUT_DIR.mkdir(parents=True, exist_ok=True)

SIG_CUTOFF = pd.Timestamp('2023-12-22')
EMBARGO_DAYS = 30
MIN_TRAIN_YEARS = 5
N_OPTUNA_TRIALS = 100  # full sweep
TURNOVER_PENALTY_LAMBDA = 0.05

sys.stdout = open(sys.stdout.fileno(), mode='w', buffering=1, encoding='utf-8', closefd=False)
sys.stderr = open(sys.stderr.fileno(), mode='w', buffering=1, encoding='utf-8', closefd=False)

t0 = time.time()
print(f"[{datetime.now().strftime('%H:%M:%S')}] D REFINE Step 2 — LightGBM Walk-Forward (Optuna {N_OPTUNA_TRIALS} trials)", flush=True)

# ---- Step 1: Load pruned panel ----
panel = pd.read_parquet(OUT_DIR / 'ml_panel_pruned.parquet')
panel['sig_date'] = pd.to_datetime(panel['sig_date'])
panel = panel[panel['sig_date'] <= SIG_CUTOFF].copy()
print(f"  Panel: {panel.shape[0]} rows × {panel.shape[1]} cols")
print(f"  sig_date range: {panel['sig_date'].min()} -> {panel['sig_date'].max()}")

# Feature cols
with open(OUT_DIR / 'feature_cols_top30.txt') as f:
    feature_cols = [x.strip() for x in f.readlines() if x.strip()]

# Add sector dummies
if 'Sector_Lv2' in panel.columns:
    sec_dum = pd.get_dummies(panel['Sector_Lv2'], prefix='sec', dummy_na=False, drop_first=True)
    panel = pd.concat([panel.reset_index(drop=True), sec_dum.reset_index(drop=True)], axis=1)
    feature_cols = feature_cols + list(sec_dum.columns)
    print(f"  Added {sec_dum.shape[1]} sector dummies (total features: {len(feature_cols)})")

# Drop NaN target
panel = panel.dropna(subset=['log_ret_1m_w']).copy()

# Numeric filter
numeric_features = []
for c in feature_cols:
    if c not in panel.columns:
        continue
    panel[c] = pd.to_numeric(panel[c], errors='coerce')
    if panel[c].isna().mean() < 0.90:
        numeric_features.append(c)
feature_cols = numeric_features
print(f"  Numeric features (≤90% NaN): {len(feature_cols)}")

# Cross-section z-score target
panel['target_zxs'] = panel.groupby('sig_date')['log_ret_1m_w'].transform(lambda x: (x - x.mean()) / (x.std() + 1e-8))
TARGET_COL = 'target_zxs'

# ---- Step 2: Walk-forward folds ----
sig_dates_sorted = sorted(panel['sig_date'].unique())
first_date = sig_dates_sorted[0]
last_date = sig_dates_sorted[-1]
min_train_end = first_date + pd.DateOffset(years=MIN_TRAIN_YEARS)

folds = []
fold_start = min_train_end
while fold_start < last_date:
    train_end = fold_start
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

# ---- Step 3: Optuna Full Sweep on Fold 0 (turnover-aware composite objective) ----
print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Step 3 — Optuna Full Sweep ({N_OPTUNA_TRIALS} trials, MedianPruner)", flush=True)

fold0 = folds[0]
train_mask = panel['sig_date'].isin(fold0['train_sds'])
test_mask = panel['sig_date'].isin(fold0['test_sds'])
X_train = panel.loc[train_mask, feature_cols].values.astype(np.float32)
y_train = panel.loc[train_mask, TARGET_COL].values.astype(np.float32)
X_test = panel.loc[test_mask, feature_cols].values.astype(np.float32)
y_test = panel.loc[test_mask, TARGET_COL].values.astype(np.float32)
sds_test = panel.loc[test_mask, 'sig_date'].values
tickers_test = panel.loc[test_mask, 'Ticker'].values

# Compute turnover proxy: top20 set churn between consecutive sig_dates
def compute_turnover_proxy(df_pred):
    """
    Top 20 by predicted score per sig_date, compute set churn between consecutive sig_dates.
    Annual turnover = avg(churn per month) * 12 * 2 (2-way: exit+entry)
    """
    df_pred = df_pred.copy().sort_values(['sig_date', 'pred'], ascending=[True, False])
    top20_per_date = df_pred.groupby('sig_date').head(20)
    dates_sorted = sorted(top20_per_date['sig_date'].unique())
    if len(dates_sorted) < 2:
        return 0.0
    churns = []
    prev_set = None
    for d in dates_sorted:
        cur_set = set(top20_per_date[top20_per_date['sig_date'] == d]['Ticker'])
        if prev_set is not None:
            # Churn = exits / 20 (one-way), annualized 2-way = * 24
            exits = len(prev_set - cur_set)
            churns.append(exits / 20.0)
        prev_set = cur_set
    if len(churns) == 0:
        return 0.0
    monthly_churn = np.mean(churns)
    return monthly_churn * 24.0  # 2-way annualized turnover proxy

optuna_trial_log = []

def objective(trial):
    params = {
        'objective': 'regression',
        'metric': 'rmse',
        'learning_rate': trial.suggest_float('learning_rate', 0.005, 0.20, log=True),
        'num_leaves': trial.suggest_int('num_leaves', 15, 127),
        'max_depth': trial.suggest_int('max_depth', 3, 10),
        'min_data_in_leaf': trial.suggest_int('min_data_in_leaf', 20, 200),
        'lambda_l1': trial.suggest_float('lambda_l1', 1e-3, 10.0, log=True),
        'lambda_l2': trial.suggest_float('lambda_l2', 1e-3, 10.0, log=True),
        'feature_fraction': trial.suggest_float('feature_fraction', 0.5, 1.0),
        'bagging_fraction': trial.suggest_float('bagging_fraction', 0.5, 1.0),
        'bagging_freq': trial.suggest_int('bagging_freq', 1, 7),
        'min_gain_to_split': trial.suggest_float('min_gain_to_split', 0, 1.0),
        'verbosity': -1,
        'n_jobs': 4,
    }
    n_estimators = trial.suggest_int('n_estimators', 100, 500)

    train_set = lgb.Dataset(X_train, label=y_train)
    test_set = lgb.Dataset(X_test, label=y_test, reference=train_set)

    model = lgb.train(
        params, train_set, num_boost_round=n_estimators,
        valid_sets=[test_set],
        callbacks=[lgb.early_stopping(stopping_rounds=30, verbose=False)],
    )
    pred = model.predict(X_test)

    df_test = pd.DataFrame({'sig_date': sds_test, 'Ticker': tickers_test, 'pred': pred, 'y': y_test})
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

    # Turnover proxy on test fold (annual 2-way)
    turnover_proxy = compute_turnover_proxy(df_test)

    # Composite objective: high IC + low IC vol + low turnover
    score = mean_ic - 0.2 * std_ic - TURNOVER_PENALTY_LAMBDA * (turnover_proxy / 10.0)

    optuna_trial_log.append({
        'trial': trial.number,
        'mean_ic': mean_ic,
        'std_ic': std_ic,
        'turnover_proxy_annual': turnover_proxy,
        'score': score,
        'n_estimators': model.best_iteration if model.best_iteration else n_estimators,
    })

    # Report intermediate value for pruning
    trial.report(score, step=0)
    if trial.should_prune():
        raise optuna.TrialPruned()

    return score

def progress_cb(study, trial):
    if (trial.number + 1) % 10 == 0:
        print(f"    [Optuna] trial {trial.number+1}/{N_OPTUNA_TRIALS} value={trial.value if trial.value else 'PRUNED':<10} best={study.best_value:.4f}", flush=True)

study = optuna.create_study(
    direction='maximize',
    sampler=optuna.samplers.TPESampler(seed=42),
    pruner=MedianPruner(n_startup_trials=10, n_warmup_steps=0),
)
study.optimize(objective, n_trials=N_OPTUNA_TRIALS, show_progress_bar=False, n_jobs=1, callbacks=[progress_cb])

best_params = study.best_params.copy()
print(f"\n  Best Fold 0 composite score: {study.best_value:.4f}")
print(f"  Best params: {best_params}")

# Save trial log
with open(OUT_DIR / 'optuna_trial_log.json', 'w') as f:
    json.dump(optuna_trial_log, f, indent=2)

# Save best params
with open(OUT_DIR / 'best_hyperparams.json', 'w') as f:
    json.dump({
        'fold0_optuna_best_score': float(study.best_value),
        'fold0_optuna_best_params': {k: float(v) if isinstance(v, (int, float)) else v for k, v in best_params.items()},
        'n_trials': N_OPTUNA_TRIALS,
        'pruner': 'MedianPruner',
        'composite_objective': 'mean_ic - 0.2*std_ic - 0.05*(turnover_proxy/10)',
    }, f, indent=2)

# ---- Step 4: Full Walk-Forward with best params ----
print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Step 4 — Full walk-forward with best params", flush=True)

best_n_est = best_params.pop('n_estimators', 300)

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

    train_set = lgb.Dataset(X_tr, label=y_tr)
    model = lgb.train(
        {**best_params, 'objective': 'regression', 'metric': 'rmse', 'verbosity': -1, 'n_jobs': 8},
        train_set, num_boost_round=best_n_est,
    )
    pred_te = model.predict(X_te)
    print(f"    Fold {fold['fold_id']} model trained ({best_n_est} trees, n_train={X_tr.shape[0]})", flush=True)

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
    print(f"  Fold {fold['fold_id']}: rank IC mean={np.mean(ics):.4f} std={np.std(ics):.4f} IR={np.mean(ics)/(np.std(ics)+1e-8):.3f} (n={len(ics)} sds)", flush=True)

    all_preds.append(df_pred)
    feat_importance_agg += np.array(model.feature_importance(importance_type='gain'))

feat_importance_agg /= len(folds)
fi_df = pd.DataFrame({'feature': feature_cols, 'importance': feat_importance_agg})
fi_df = fi_df.sort_values('importance', ascending=False).reset_index(drop=True)
fi_df.to_parquet(OUT_DIR / 'feature_importance.parquet', index=False)

all_preds_df = pd.concat(all_preds, ignore_index=True)

# ---- Step 5: Aggregate metrics ----
print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Step 5 — aggregate metrics", flush=True)

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

# Newey-West HAC t-stat
from scipy.stats import t as tdist
n = len(all_ics)
lag = 3
y_arr = np.array(all_ics)
y_mean_arr = y_arr.mean()
y_dev = y_arr - y_mean_arr
gamma_0 = np.mean(y_dev ** 2)
gamma_sum = 0.0
for k in range(1, lag + 1):
    w = 1 - k / (lag + 1)
    gamma_k = np.mean(y_dev[:-k] * y_dev[k:])
    gamma_sum += 2 * w * gamma_k
var_hac = (gamma_0 + gamma_sum) / n
t_hac = mean_ic / max(np.sqrt(max(var_hac, 1e-10)), 1e-10)
p_hac = 2 * (1 - tdist.cdf(abs(t_hac), df=n-1))

# Bootstrap CI
np.random.seed(42)
n_boot = 1000
boot_ics = []
for _ in range(n_boot):
    sample = np.random.choice(all_ics, size=len(all_ics), replace=True)
    boot_ics.append(np.mean(sample))
ic_ci_95 = (np.percentile(boot_ics, 2.5), np.percentile(boot_ics, 97.5))

# DSR proper (n_trials_eff = D ML 269 + Phase 3 38 + Optuna 100 + parallel hyp = ~407)
n_trials_eff_proper = 269 + 38 + N_OPTUNA_TRIALS + 4
sr_observed = icir * np.sqrt(12)
exp_max_sr = np.sqrt(2 * np.log(max(n_trials_eff_proper, 2)))
dsr_z = (sr_observed - exp_max_sr * (1 - 0.5772 / np.sqrt(2 * np.log(n_trials_eff_proper)))) / 1.0
from scipy.stats import norm
dsr_proper = norm.cdf(dsr_z) if not np.isnan(dsr_z) else 0.0

# Subperiod stability
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
    return {'n_sd': len(ics), 'mean_ic': float(np.mean(ics)), 'icir': float(np.mean(ics) / (np.std(ics) + 1e-8))}

sub_metrics = {
    '2008-2014': ic_subperiod(sub_a),
    '2015-2019': ic_subperiod(sub_b),
    '2020-2023': ic_subperiod(sub_c),
}
positive_sub = sum(1 for v in sub_metrics.values() if v.get('mean_ic') is not None and v['mean_ic'] > 0) / max(sum(1 for v in sub_metrics.values() if v.get('mean_ic') is not None), 1)

# AX-001 v2 soft proxy (bottom 25% xs mean as bad)
all_preds_df['xs_mean_ret'] = all_preds_df.groupby('sig_date')['log_ret_1m_w'].transform('mean')
ret_q25 = all_preds_df['xs_mean_ret'].quantile(0.25)
bad_mask = all_preds_df['xs_mean_ret'] <= ret_q25
ic_bad = []
ic_normal = []
for sd, grp in all_preds_df[bad_mask].groupby('sig_date'):
    if grp.shape[0] >= 20:
        ic, _ = spearmanr(grp['pred'].values, grp['y_zxs'].values)
        if not np.isnan(ic): ic_bad.append(ic)
for sd, grp in all_preds_df[~bad_mask].groupby('sig_date'):
    if grp.shape[0] >= 20:
        ic, _ = spearmanr(grp['pred'].values, grp['y_zxs'].values)
        if not np.isnan(ic): ic_normal.append(ic)
ic_bad_mean = float(np.mean(ic_bad)) if ic_bad else 0.0
ic_normal_mean = float(np.mean(ic_normal)) if ic_normal else 0.0
ax001_ratio = ic_bad_mean / (abs(ic_normal_mean) + 1e-8) if ic_normal_mean != 0 else 0.0

# Save cv_results
cv_results = {
    'wt_id': 'WT-D20260528_003',
    'hypothesis_id': 'D_REFINE',
    'model_type': 'LightGBM_walkforward_purged_cv_top30',
    'target': TARGET_COL,
    'n_features': len(feature_cols),
    'n_folds': len(folds),
    'lockbox_cutoff': str(SIG_CUTOFF.date()),
    'embargo_days': EMBARGO_DAYS,
    'min_train_years': MIN_TRAIN_YEARS,
    'n_optuna_trials': N_OPTUNA_TRIALS,
    'composite_objective': f'mean_ic - 0.2*std_ic - {TURNOVER_PENALTY_LAMBDA}*(turnover_proxy/10)',
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
    'dsr_proper': float(dsr_proper) if not np.isnan(dsr_proper) else None,
    'n_trials_effective_for_dsr_proper': n_trials_eff_proper,
    'fold_metrics': fold_metrics,
    'elapsed_seconds': float(time.time() - t0),
}

with open(OUT_DIR / 'cv_results.json', 'w') as f:
    json.dump(cv_results, f, indent=2, default=str)

all_preds_df.to_parquet(OUT_DIR / 'predictions_walkforward.parquet', index=False)

print(f"\n  Saved: cv_results.json + predictions_walkforward.parquet + feature_importance.parquet")
print(f"  Top 10 features by importance (LightGBM gain):")
for i, row in fi_df.head(10).iterrows():
    print(f"    {row['feature']:<40} {row['importance']:.4f}")

print(f"\n=== Step 2 COMPLETE — elapsed {(time.time()-t0)/60:.2f} min ===")
print(f"  Overall: IC mean = {mean_ic:.4f}, ICIR = {icir:.3f}, t_HAC = {t_hac:.2f}")
print(f"  Subperiod stability: {positive_sub:.2f}")
print(f"  AX-001 v2 ratio bad/normal: {ax001_ratio:.3f}")
print(f"  DSR proper (n_trials={n_trials_eff_proper}): {dsr_proper:.3f}")
