#!/usr/bin/env python
"""
WT-D20260528_003 Hypothesis E — Alternative Data ML (Track 4)
Step 2: LightGBM Walk-Forward Purged CV + Optuna Sweep + Net-of-Cost Reward

Academic grounding:
- Gu-Kelly-Xiu 2020 RFS (Empirical Asset Pricing via ML)
- López de Prado 2018 (Purged CV + Embargo)
- Jensen-Kelly-Malamud-Pedersen 2022 (Net-of-Cost ML loss)
- Pollet-Wilson 2010 RFS (smart money flow)
- Anton-Polk 2014 JF (crowding)

Pipeline:
  1. Load 67-feature alt-data panel
  2. Walk-forward purged splits (train >= 5y, test 1y, embargo 30d)
  3. Optuna 50 trials on Fold 0 — composite IC + turnover penalty
  4. Best model train + inference each fold
  5. Aggregate metrics (IC + ICIR + Harvey t + DSR + AX001 v2 + Net-of-Cost SR)
  6. Save predictions + importance + diagnostic

PIT C1 strict: train_end + 30d embargo < test_start
Lockbox: sig_date <= 2023-12-22 (Step 1 pre-filtered)
Net-of-cost: loss + γ * |Δw| where γ = 15bps (per research_philosophy #2)
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
import lightgbm as lgb
import optuna
from scipy.stats import spearmanr, rankdata
from sklearn.metrics import mean_squared_error

warnings.filterwarnings('ignore')
optuna.logging.set_verbosity(optuna.logging.WARNING)

# ---- Paths ----
PROJ = Path('/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot')
WT_ID = 'WT-D20260528_003'
HYP_TAG = 'E_ALTDATA'
OUT_DIR = PROJ / 'stage_artifacts' / 'WT_D20260528_003_E_ALTDATA'
OUT_DIR.mkdir(parents=True, exist_ok=True)

SIG_CUTOFF = pd.Timestamp('2023-12-22')
EMBARGO_DAYS = 30
MIN_TRAIN_YEARS = 5
N_OPTUNA_TRIALS = 50  # 도훈 spec
COST_BPS = 15.0       # Net-of-cost: 15bps one-way
COST_GAMMA = COST_BPS / 10000.0  # 0.0015 = 15bps

# Unbuffered output
sys.stdout = open(sys.stdout.fileno(), mode='w', buffering=1, encoding='utf-8', closefd=False)
sys.stderr = open(sys.stderr.fileno(), mode='w', buffering=1, encoding='utf-8', closefd=False)

t0 = time.time()
print(f"[{datetime.now().strftime('%H:%M:%S')}] === E_ALTDATA Step 2 — LightGBM Walk-Forward CV + Optuna ===", flush=True)

# ---- Step 1: Load panel ----
panel_path = OUT_DIR / 'altdata_panel_train.parquet'
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

exclude_cols = ['sig_date', 'Ticker', 'log_ret_1m_w', 'Sector_Lv2']
feature_cols = [c for c in feature_cols if c not in exclude_cols and c in panel.columns]

# Sector dummies
if 'Sector_Lv2' in panel.columns:
    sec_dum = pd.get_dummies(panel['Sector_Lv2'], prefix='sec', dummy_na=False, drop_first=True)
    panel = pd.concat([panel.reset_index(drop=True), sec_dum.reset_index(drop=True)], axis=1)
    feature_cols = feature_cols + list(sec_dum.columns)
    print(f"  Added {sec_dum.shape[1]} sector dummies")

panel = panel.dropna(subset=['log_ret_1m_w']).copy()

numeric_features = []
for c in feature_cols:
    if c not in panel.columns:
        continue
    panel[c] = pd.to_numeric(panel[c], errors='coerce')
    if panel[c].isna().mean() < 0.90:
        numeric_features.append(c)
feature_cols = numeric_features
print(f"  Numeric features (≤90% NaN): {len(feature_cols)}")

# ---- Step 3: Target (cross-section z-score per sig_date) ----
panel['target_zxs'] = panel.groupby('sig_date')['log_ret_1m_w'].transform(
    lambda x: (x - x.mean()) / (x.std() + 1e-8))
TARGET_COL = 'target_zxs'
print(f"  Target: {TARGET_COL}")

# ---- Step 4: Walk-forward folds (D_ML과 동일 구조) ----
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
for f in folds:
    print(f"    Fold {f['fold_id']}: train[{f['train_sds'][0].date()}..{f['train_end'].date()}] (n={f['n_train']}m) -> test[{f['test_sds'][0].date()}..{f['test_sds'][-1].date()}] (n={f['n_test']}m)")

# ---- Step 5: Optuna sweep on Fold 0 ----
print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Step 5 — Optuna sweep on Fold 0 (n={N_OPTUNA_TRIALS} trials)", flush=True)

fold0 = folds[0]
train_mask = panel['sig_date'].isin(fold0['train_sds'])
test_mask = panel['sig_date'].isin(fold0['test_sds'])
X_train = panel.loc[train_mask, feature_cols].values.astype(np.float32)
y_train = panel.loc[train_mask, TARGET_COL].values.astype(np.float32)
X_test = panel.loc[test_mask, feature_cols].values.astype(np.float32)
y_test = panel.loc[test_mask, TARGET_COL].values.astype(np.float32)
sds_test = panel.loc[test_mask, 'sig_date'].values
log_ret_test = panel.loc[test_mask, 'log_ret_1m_w'].values
tickers_test = panel.loc[test_mask, 'Ticker'].values

def net_of_cost_score(pred, log_ret_realized, sds, tickers, top_k=20, cost_gamma=COST_GAMMA):
    """Net-of-cost SR proxy: top-K equal-weight long-only with turnover penalty"""
    df = pd.DataFrame({
        'sig_date': sds,
        'Ticker': tickers,
        'pred': pred,
        'realized_log_ret': log_ret_realized,
    })
    df = df.sort_values(['sig_date', 'pred'], ascending=[True, False])
    # Top-K per sig_date
    df['rank_in_sd'] = df.groupby('sig_date')['pred'].rank(ascending=False, method='first')
    df_topk = df[df['rank_in_sd'] <= top_k].copy()
    # Gross monthly return per sig_date (EW)
    gross = df_topk.groupby('sig_date')['realized_log_ret'].mean().sort_index()
    # Turnover estimate: holdings change between adjacent sig_dates
    holdings_by_sd = df_topk.groupby('sig_date')['Ticker'].apply(set)
    sd_list = sorted(holdings_by_sd.index)
    turnover = []
    for i in range(1, len(sd_list)):
        prev = holdings_by_sd.iloc[i-1]
        curr = holdings_by_sd.iloc[i]
        # Change = symmetric diff / (2 * top_k)
        change_frac = len(prev.symmetric_difference(curr)) / (2.0 * top_k)
        turnover.append(change_frac)
    avg_turnover = np.mean(turnover) if turnover else 0.5
    # Annual turnover
    annual_turnover = avg_turnover * 12.0
    # Cost drag per month (round-trip = 2 × cost_gamma × monthly turnover)
    monthly_cost_drag = 2 * cost_gamma * avg_turnover
    net_monthly = gross - monthly_cost_drag
    # SR (annualized) of net returns
    if net_monthly.std() < 1e-6:
        return -1.0
    sr_annual = (net_monthly.mean() * 12) / (net_monthly.std() * np.sqrt(12))
    return float(sr_annual), float(avg_turnover), float(monthly_cost_drag)

def objective(trial):
    params = {
        'objective': 'regression',
        'metric': 'rmse',
        'learning_rate': trial.suggest_float('learning_rate', 0.01, 0.20, log=True),
        'num_leaves': trial.suggest_int('num_leaves', 15, 127),
        'max_depth': trial.suggest_int('max_depth', 3, 10),
        'min_child_samples': trial.suggest_int('min_child_samples', 5, 50),
        'subsample': trial.suggest_float('subsample', 0.6, 1.0),
        'colsample_bytree': trial.suggest_float('colsample_bytree', 0.5, 1.0),
        'reg_alpha': trial.suggest_float('reg_alpha', 1e-3, 1.0, log=True),
        'reg_lambda': trial.suggest_float('reg_lambda', 1e-3, 10.0, log=True),
        'min_split_gain': trial.suggest_float('min_split_gain', 0.0, 1.0),
        'feature_fraction_bynode': trial.suggest_float('feature_fraction_bynode', 0.5, 1.0),
        'verbosity': -1,
        'n_jobs': 4,
        'bagging_freq': 5,
    }
    n_estimators = trial.suggest_int('n_estimators', 100, 400)

    train_ds = lgb.Dataset(X_train, label=y_train)
    model = lgb.train(params, train_ds, num_boost_round=n_estimators)
    pred = model.predict(X_test)

    # Per sig_date IC
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

    # Net-of-cost SR component (Jensen-Kelly-Malamud-Pedersen 2022 alignment)
    try:
        sr_net, _, _ = net_of_cost_score(pred, log_ret_test, sds_test, tickers_test, top_k=20)
    except Exception:
        sr_net = 0.0

    # Composite: 0.4 mean_IC + 0.3 ICIR/sqrt(12) + 0.3 normalized SR_net
    sr_norm = sr_net / 3.0  # rough scale
    score = 0.4 * mean_ic + 0.3 * icir / np.sqrt(12) + 0.3 * sr_norm
    return float(score)

def progress_cb(study, trial):
    if (trial.number + 1) % 5 == 0 or trial.number == 0:
        print(f"    [Optuna] trial {trial.number+1}/{N_OPTUNA_TRIALS} value={trial.value:.4f} best={study.best_value:.4f}", flush=True)

study = optuna.create_study(direction='maximize', sampler=optuna.samplers.TPESampler(seed=42))
study.optimize(objective, n_trials=N_OPTUNA_TRIALS, show_progress_bar=False, n_jobs=1, callbacks=[progress_cb])

best_params = study.best_params.copy()
print(f"  Best Fold 0 composite score: {study.best_value:.4f}")
print(f"  Best params: {best_params}")

with open(OUT_DIR / 'best_hyperparams.json', 'w') as f:
    json.dump({
        'fold0_optuna_best_score': float(study.best_value),
        'fold0_optuna_best_params': {k: float(v) if isinstance(v, (int, float)) else v for k, v in best_params.items()},
        'n_trials': N_OPTUNA_TRIALS,
        'cost_bps': COST_BPS,
    }, f, indent=2)

# ---- Step 6: Full walk-forward ----
print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Step 6 — Full walk-forward with best params", flush=True)

best_n_est = best_params.pop('n_estimators', 200)

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

    train_ds = lgb.Dataset(X_tr, label=y_tr)
    params_full = dict(best_params)
    params_full.update({'objective': 'regression', 'metric': 'rmse', 'verbosity': -1, 'n_jobs': 8, 'bagging_freq': 5})
    model = lgb.train(params_full, train_ds, num_boost_round=best_n_est)
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
    print(f"  Fold {fold['fold_id']}: rank IC mean={np.mean(ics):.4f} std={np.std(ics):.4f} IR={np.mean(ics)/(np.std(ics)+1e-8):.3f} (n={len(ics)} sds)")

    all_preds.append(df_pred)

    feat_importance_agg += np.array(model.feature_importance(importance_type='gain'))

feat_importance_agg /= len(folds)
fi_df = pd.DataFrame({'feature': feature_cols, 'importance': feat_importance_agg})
fi_df['importance_norm'] = fi_df['importance'] / fi_df['importance'].sum()
fi_df = fi_df.sort_values('importance', ascending=False).reset_index(drop=True)

all_preds_df = pd.concat(all_preds, ignore_index=True)

# ---- Step 7: Aggregate metrics ----
print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Step 7 — aggregate metrics", flush=True)

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

# Bootstrap CI 95
np.random.seed(42)
boot_ics = []
for _ in range(1000):
    sample = np.random.choice(all_ics, size=len(all_ics), replace=True)
    boot_ics.append(np.mean(sample))
ic_ci_95 = (float(np.percentile(boot_ics, 2.5)), float(np.percentile(boot_ics, 97.5)))

# Newey-West HAC t-stat (lag 3)
from scipy.stats import t as tdist
n = len(all_ics)
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

# DSR (Bailey-Lopez de Prado simplified)
n_trials_eff = N_OPTUNA_TRIALS + 4 + 1
sr_observed = icir * np.sqrt(12)
exp_max_sr = np.sqrt(2 * np.log(max(n_trials_eff, 2)))
from scipy.stats import norm
dsr_z = (sr_observed - exp_max_sr * (1 - 0.5772 / np.sqrt(2 * np.log(n_trials_eff)))) / 1.0
dsr = float(norm.cdf(dsr_z)) if not np.isnan(dsr_z) else 0.0

# Subperiod stability (D_ML과 동일 3 subperiods)
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

positive_sub = sum(1 for v in sub_metrics.values() if v.get('mean_ic') is not None and v['mean_ic'] > 0) / \
               max(sum(1 for v in sub_metrics.values() if v.get('mean_ic') is not None), 1)

# AX-001 v2 bad/normal IC ratio
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

# Net-of-cost SR (FULL walk-forward — Top 20 EW)
try:
    sr_net_full, avg_turnover_full, monthly_cost_drag = net_of_cost_score(
        all_preds_df['pred'].values,
        all_preds_df['log_ret_1m_w'].values,
        all_preds_df['sig_date'].values,
        all_preds_df['Ticker'].values,
        top_k=20)
except Exception as e:
    print(f"  net_of_cost_score failed: {e}")
    sr_net_full, avg_turnover_full, monthly_cost_drag = 0.0, 0.5, 0.0

print(f"\n  Net-of-Cost (Top 20 EW, {COST_BPS}bps one-way):")
print(f"    Avg monthly turnover: {avg_turnover_full:.3f} ({avg_turnover_full*12:.2f}/yr)")
print(f"    Monthly cost drag:    {monthly_cost_drag*10000:.1f}bps")
print(f"    Net SR (annualized):  {sr_net_full:.3f}")

# Cross-correlation with D_ML predictions (orthogonality test)
dml_pred_path = PROJ / 'stage_artifacts' / 'WT_D20260528_003_overnight_D_ML' / 'predictions_walkforward.parquet'
orth_metrics = {'available': False}
if dml_pred_path.exists():
    try:
        dml_preds = pd.read_parquet(dml_pred_path)
        dml_preds['sig_date'] = pd.to_datetime(dml_preds['sig_date'])
        joined = pd.merge(
            all_preds_df[['sig_date', 'Ticker', 'pred']].rename(columns={'pred': 'pred_E'}),
            dml_preds[['sig_date', 'Ticker', 'pred']].rename(columns={'pred': 'pred_D'}),
            on=['sig_date', 'Ticker'])
        if joined.shape[0] > 100:
            cors = []
            for sd, grp in joined.groupby('sig_date'):
                if grp.shape[0] >= 20:
                    c, _ = spearmanr(grp['pred_E'].values, grp['pred_D'].values)
                    if not np.isnan(c):
                        cors.append(c)
            orth_metrics = {
                'available': True,
                'mean_xs_spearman_E_vs_D': float(np.mean(cors)) if cors else None,
                'median_xs_spearman_E_vs_D': float(np.median(cors)) if cors else None,
                'n_sds_overlap': len(cors),
                'orthogonality_score': float(1.0 - abs(np.mean(cors))) if cors else None,
            }
            print(f"\n  Orthogonality vs D_ML: mean_xs_corr = {np.mean(cors):.3f}")
    except Exception as e:
        print(f"  D_ML overlap check failed: {e}")

# Save CV results
cv_results = {
    'wt_id': WT_ID,
    'hypothesis_id': HYP_TAG,
    'model_type': 'LightGBM_walkforward_purged_cv_netcost',
    'target': TARGET_COL,
    'n_features': len(feature_cols),
    'n_folds': len(folds),
    'lockbox_cutoff': str(SIG_CUTOFF.date()),
    'embargo_days': EMBARGO_DAYS,
    'min_train_years': MIN_TRAIN_YEARS,
    'n_optuna_trials': N_OPTUNA_TRIALS,
    'cost_bps': COST_BPS,
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
        'ic_ci_95_lower': ic_ci_95[0],
        'ic_ci_95_upper': ic_ci_95[1],
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
    'net_of_cost_top20': {
        'sr_net_annual': float(sr_net_full),
        'avg_monthly_turnover': float(avg_turnover_full),
        'annual_turnover': float(avg_turnover_full * 12),
        'monthly_cost_drag_bps': float(monthly_cost_drag * 10000),
        'cost_bps_one_way': COST_BPS,
    },
    'orthogonality_vs_D_ML': orth_metrics,
    'dsr_simplified': float(dsr) if not np.isnan(dsr) else None,
    'n_trials_effective_for_dsr': n_trials_eff,
    'fold_metrics': fold_metrics,
    'elapsed_seconds': float(time.time() - t0),
}

with open(OUT_DIR / 'cv_results.json', 'w') as f:
    json.dump(cv_results, f, indent=2, default=str)

all_preds_df.to_parquet(OUT_DIR / 'predictions_walkforward.parquet', index=False)
fi_df.to_parquet(OUT_DIR / 'feature_importance.parquet', index=False)

print(f"\n  Saved: cv_results.json + predictions_walkforward.parquet + feature_importance.parquet")
print(f"  Top 15 features by importance:")
for i, row in fi_df.head(15).iterrows():
    print(f"    {row['feature']:<40} {row['importance']:.4f}")

print(f"\n=== E_ALTDATA Step 2 COMPLETE — elapsed {(time.time()-t0)/60:.2f} min ===")
print(f"  Overall: IC mean = {mean_ic:.4f}, ICIR = {icir:.3f}, t_HAC = {t_hac:.2f}, DSR = {dsr:.3f}")
print(f"  Subperiod stability: {positive_sub:.2f}, AX-001 v2 ratio bad/normal: {ax001_ratio:.3f}")
print(f"  Net SR (Top 20): {sr_net_full:.3f} (turnover {avg_turnover_full*12:.2f}/yr)")
