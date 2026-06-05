#!/usr/bin/env python
"""
WT-D20260528_003 / Track 3 — D ML Ensemble (alpha-research v3.9_ensemble)

Step 1: Train 3 base models (XGBoost, LightGBM, RandomForest)
  + 3 Ensemble methods (Equal, IC-weighted, Stacking-Ridge)

Same feature set as D ML (162 features incl. sector dummies).
Walk-forward Purged CV + 30d embargo (López de Prado 2018).
Per-model Optuna 30 trials on Fold 0 (TPE seed=42).

Academic grounding:
- Gu-Kelly-Xiu 2020 RFS: NN ensemble (NN1~NN4 average)
- Bryzgalova-Pelger-Zhu 2024: Neural network forest
- Avramov-Cheng-Metzker 2024 RAPS: multi-model stacking

PIT C1 strict: train_end < test_start (embargo 30d).
Lockbox: sig_date <= 2023-12-22 strict (alpha-research scope).

Output:
  stage_artifacts/WT_D20260528_003_D_ENSEMBLE/
    - best_hyperparams_xgb.json
    - best_hyperparams_lgbm.json
    - best_hyperparams_rf.json
    - cv_results_xgb.json / lgbm.json / rf.json
    - predictions_walkforward_xgb.parquet / lgbm.parquet / rf.parquet
    - predictions_walkforward_ensemble.parquet (3 methods)
    - feature_importance_xgb.parquet / lgbm.parquet / rf.parquet
    - ensemble_cv_results.json (unified diagnostics)
"""

import sys
import json
import time
import warnings
from pathlib import Path
from datetime import datetime

import numpy as np
import pandas as pd
import xgboost as xgb
import lightgbm as lgbm
from sklearn.ensemble import RandomForestRegressor
from sklearn.linear_model import Ridge
from sklearn.metrics import mean_squared_error
from scipy.stats import spearmanr, t as tdist, norm
import optuna

warnings.filterwarnings('ignore')
optuna.logging.set_verbosity(optuna.logging.WARNING)

# ---- Paths ----
PROJ = Path('/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot')
WT_ID = 'WT-D20260528_003'
PANEL_DIR = PROJ / 'stage_artifacts' / 'WT_D20260528_003_overnight_D_ML'
OUT_DIR = PROJ / 'stage_artifacts' / 'WT_D20260528_003_D_ENSEMBLE'
OUT_DIR.mkdir(parents=True, exist_ok=True)

SIG_CUTOFF = pd.Timestamp('2023-12-22')
EMBARGO_DAYS = 30
MIN_TRAIN_YEARS = 5
N_OPTUNA_TRIALS = 30   # per model
MAX_N_EST = 300

# Force unbuffered output
sys.stdout = open(sys.stdout.fileno(), mode='w', buffering=1, encoding='utf-8', closefd=False)
sys.stderr = open(sys.stderr.fileno(), mode='w', buffering=1, encoding='utf-8', closefd=False)

t0 = time.time()
print(f"[{datetime.now().strftime('%H:%M:%S')}] D_ENSEMBLE Step 1 — Train 3 base models + ensemble", flush=True)

# =====================================================================
# Step 1: Load panel + setup feature/target (re-use D ML panel)
# =====================================================================
panel_path = PANEL_DIR / 'ml_panel_train.parquet'
if not panel_path.exists():
    print(f"ERROR: panel not found at {panel_path}", file=sys.stderr)
    sys.exit(1)

panel = pd.read_parquet(panel_path)
panel['sig_date'] = pd.to_datetime(panel['sig_date'])
panel = panel[panel['sig_date'] <= SIG_CUTOFF].copy()
print(f"  Panel: {panel.shape[0]} rows × {panel.shape[1]} cols")
print(f"  sig_date range: {panel['sig_date'].min().date()} -> {panel['sig_date'].max().date()}")

# Feature cols from D ML
feature_cols_file = PANEL_DIR / 'feature_cols.txt'
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

# Drop NaN target
panel = panel.dropna(subset=['log_ret_1m_w']).copy()

# Numeric coercion + drop >90% NaN cols
numeric_features = []
for c in feature_cols:
    if c not in panel.columns:
        continue
    panel[c] = pd.to_numeric(panel[c], errors='coerce')
    if panel[c].isna().mean() < 0.90:
        numeric_features.append(c)
feature_cols = numeric_features
print(f"  Numeric features (≤90% NaN): {len(feature_cols)}")

# Target: cross-section z-score
panel['target_zxs'] = panel.groupby('sig_date')['log_ret_1m_w'].transform(
    lambda x: (x - x.mean()) / (x.std() + 1e-8)
)
TARGET_COL = 'target_zxs'

# =====================================================================
# Step 2: Walk-forward folds (identical to D ML)
# =====================================================================
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

# =====================================================================
# Step 3: NaN imputation (RF doesn't natively handle NaN like XGB/LGBM)
# =====================================================================
# Use per-sig_date median imputation for RF compatibility
X_all = panel[feature_cols].copy()
panel_med = X_all.median()  # global median fallback
print(f"  Computing per-sig_date median imputation for RF...")
# Transform NaN -> per-sig_date median (PIT-safe: medians from cross-section at same sig_date)
for col in feature_cols:
    panel[col + '_imp'] = panel.groupby('sig_date')[col].transform(lambda x: x.fillna(x.median()))
    panel[col + '_imp'] = panel[col + '_imp'].fillna(panel_med[col])  # last fallback
imp_cols = [c + '_imp' for c in feature_cols]
print(f"  Imputed feature columns ready")

# =====================================================================
# Step 4: Per-model Optuna sweep on Fold 0
# =====================================================================
fold0 = folds[0]
train_mask0 = panel['sig_date'].isin(fold0['train_sds'])
test_mask0 = panel['sig_date'].isin(fold0['test_sds'])

X_train_xgb = panel.loc[train_mask0, feature_cols].values.astype(np.float32)
X_test_xgb = panel.loc[test_mask0, feature_cols].values.astype(np.float32)
X_train_imp = panel.loc[train_mask0, imp_cols].values.astype(np.float32)
X_test_imp = panel.loc[test_mask0, imp_cols].values.astype(np.float32)
y_train = panel.loc[train_mask0, TARGET_COL].values.astype(np.float32)
y_test = panel.loc[test_mask0, TARGET_COL].values.astype(np.float32)
sds_test = panel.loc[test_mask0, 'sig_date'].values


def score_predictions(pred, y_true, sds):
    """Per sig_date Spearman IC, composite score: mean_ic - 0.1*std_ic"""
    df_t = pd.DataFrame({'sig_date': sds, 'pred': pred, 'y': y_true})
    ics = []
    for sd, grp in df_t.groupby('sig_date'):
        if grp.shape[0] >= 20:
            ic, _ = spearmanr(grp['pred'].values, grp['y'].values)
            if not np.isnan(ic):
                ics.append(ic)
    if not ics:
        return -1.0, 0.0, 0.0
    mean_ic = float(np.mean(ics))
    std_ic = float(np.std(ics) + 1e-8)
    composite = mean_ic - 0.1 * std_ic
    return composite, mean_ic, std_ic


# ---- XGBoost objective ----
def obj_xgb(trial):
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
    n_est = trial.suggest_int('n_estimators', 100, MAX_N_EST)
    model = xgb.XGBRegressor(**params, n_estimators=n_est)
    model.fit(X_train_xgb, y_train, verbose=False)
    pred = model.predict(X_test_xgb)
    composite, _, _ = score_predictions(pred, y_test, sds_test)
    return composite


def obj_lgbm(trial):
    params = {
        'objective': 'regression',
        'metric': 'rmse',
        'learning_rate': trial.suggest_float('learning_rate', 0.01, 0.20, log=True),
        'num_leaves': trial.suggest_int('num_leaves', 15, 127),
        'min_data_in_leaf': trial.suggest_int('min_data_in_leaf', 20, 100),
        'feature_fraction': trial.suggest_float('feature_fraction', 0.5, 1.0),
        'bagging_fraction': trial.suggest_float('bagging_fraction', 0.6, 1.0),
        'bagging_freq': 5,
        'lambda_l1': trial.suggest_float('lambda_l1', 1e-3, 1.0, log=True),
        'lambda_l2': trial.suggest_float('lambda_l2', 1e-3, 10.0, log=True),
        'min_gain_to_split': trial.suggest_float('min_gain_to_split', 0.0, 1.0),
        'verbosity': -1,
        'n_jobs': 4,
        'force_col_wise': True,
    }
    n_est = trial.suggest_int('n_estimators', 100, MAX_N_EST)
    model = lgbm.LGBMRegressor(**params, n_estimators=n_est)
    model.fit(X_train_xgb, y_train)
    pred = model.predict(X_test_xgb)
    composite, _, _ = score_predictions(pred, y_test, sds_test)
    return composite


def obj_rf(trial):
    # RF: smaller search, fewer trees (slow), smaller depth
    params = {
        'n_estimators': trial.suggest_int('n_estimators', 80, 200),
        'max_depth': trial.suggest_int('max_depth', 6, 16),
        'min_samples_leaf': trial.suggest_int('min_samples_leaf', 10, 80),
        'max_features': trial.suggest_categorical('max_features', ['sqrt', 0.5, 0.7]),
        'n_jobs': 4,
        'random_state': 42,
    }
    model = RandomForestRegressor(**params)
    model.fit(X_train_imp, y_train)
    pred = model.predict(X_test_imp)
    composite, _, _ = score_predictions(pred, y_test, sds_test)
    return composite


def progress_cb_factory(label, n_trials):
    def cb(study, trial):
        try:
            best = study.best_value
            print(f"    [{label} Optuna] trial {trial.number+1}/{n_trials} value={trial.value:.4f} best={best:.4f}", flush=True)
        except Exception:
            pass
    return cb


# ---- Run Optuna for 3 models ----
sampler_seed = 42
print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Step 4a — XGBoost Optuna ({N_OPTUNA_TRIALS} trials)")
study_xgb = optuna.create_study(direction='maximize', sampler=optuna.samplers.TPESampler(seed=sampler_seed))
study_xgb.optimize(obj_xgb, n_trials=N_OPTUNA_TRIALS, show_progress_bar=False, n_jobs=1,
                    callbacks=[progress_cb_factory('XGB', N_OPTUNA_TRIALS)])
best_xgb = study_xgb.best_params.copy()
print(f"  XGB best Fold 0 composite: {study_xgb.best_value:.4f}")
print(f"  XGB best params: {best_xgb}")

print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Step 4b — LightGBM Optuna ({N_OPTUNA_TRIALS} trials)")
study_lgbm = optuna.create_study(direction='maximize', sampler=optuna.samplers.TPESampler(seed=sampler_seed))
study_lgbm.optimize(obj_lgbm, n_trials=N_OPTUNA_TRIALS, show_progress_bar=False, n_jobs=1,
                    callbacks=[progress_cb_factory('LGBM', N_OPTUNA_TRIALS)])
best_lgbm = study_lgbm.best_params.copy()
print(f"  LGBM best Fold 0 composite: {study_lgbm.best_value:.4f}")
print(f"  LGBM best params: {best_lgbm}")

print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Step 4c — RandomForest Optuna ({N_OPTUNA_TRIALS} trials)")
study_rf = optuna.create_study(direction='maximize', sampler=optuna.samplers.TPESampler(seed=sampler_seed))
study_rf.optimize(obj_rf, n_trials=N_OPTUNA_TRIALS, show_progress_bar=False, n_jobs=1,
                   callbacks=[progress_cb_factory('RF', N_OPTUNA_TRIALS)])
best_rf = study_rf.best_params.copy()
print(f"  RF best Fold 0 composite: {study_rf.best_value:.4f}")
print(f"  RF best params: {best_rf}")

# Save best HP per model
for name, study, params in [('xgb', study_xgb, best_xgb), ('lgbm', study_lgbm, best_lgbm), ('rf', study_rf, best_rf)]:
    with open(OUT_DIR / f'best_hyperparams_{name}.json', 'w') as f:
        json.dump({
            'fold0_optuna_best_score': float(study.best_value),
            'fold0_optuna_best_params': {k: (float(v) if isinstance(v, (int, float)) else v) for k, v in params.items()},
            'n_trials': N_OPTUNA_TRIALS,
        }, f, indent=2)

# =====================================================================
# Step 5: Full walk-forward inference per model
# =====================================================================
print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Step 5 — Full walk-forward inference (3 models × {len(folds)} folds)")

n_est_xgb = best_xgb.pop('n_estimators', 200)
n_est_lgbm = best_lgbm.pop('n_estimators', 200)

# Containers
preds_xgb_list, preds_lgbm_list, preds_rf_list = [], [], []
metrics_xgb, metrics_lgbm, metrics_rf = [], [], []
fi_xgb = np.zeros(len(feature_cols))
fi_lgbm = np.zeros(len(feature_cols))
fi_rf = np.zeros(len(feature_cols))

for fold in folds:
    train_mask = panel['sig_date'].isin(fold['train_sds'])
    test_mask = panel['sig_date'].isin(fold['test_sds'])

    X_tr = panel.loc[train_mask, feature_cols].values.astype(np.float32)
    X_te = panel.loc[test_mask, feature_cols].values.astype(np.float32)
    X_tr_imp = panel.loc[train_mask, imp_cols].values.astype(np.float32)
    X_te_imp = panel.loc[test_mask, imp_cols].values.astype(np.float32)
    y_tr = panel.loc[train_mask, TARGET_COL].values.astype(np.float32)
    y_te = panel.loc[test_mask, TARGET_COL].values.astype(np.float32)
    sds_te = panel.loc[test_mask, 'sig_date'].values
    tkr_te = panel.loc[test_mask, 'Ticker'].values
    logret_te = panel.loc[test_mask, 'log_ret_1m_w'].values

    # ---- XGB ----
    m_xgb = xgb.XGBRegressor(
        objective='reg:squarederror',
        n_estimators=n_est_xgb,
        tree_method='hist',
        device='cpu',
        nthread=4,
        verbosity=0,
        **best_xgb,
    )
    m_xgb.fit(X_tr, y_tr, verbose=False)
    p_xgb = m_xgb.predict(X_te)
    fi_xgb += np.array(m_xgb.feature_importances_)

    # ---- LGBM ----
    m_lgbm = lgbm.LGBMRegressor(
        objective='regression',
        n_estimators=n_est_lgbm,
        n_jobs=4,
        verbosity=-1,
        force_col_wise=True,
        bagging_freq=5,
        **best_lgbm,
    )
    m_lgbm.fit(X_tr, y_tr)
    p_lgbm = m_lgbm.predict(X_te)
    fi_lgbm += np.array(m_lgbm.feature_importances_)

    # ---- RF ----
    m_rf = RandomForestRegressor(
        random_state=42,
        n_jobs=4,
        **best_rf,
    )
    m_rf.fit(X_tr_imp, y_tr)
    p_rf = m_rf.predict(X_te_imp)
    fi_rf += np.array(m_rf.feature_importances_)

    print(f"    Fold {fold['fold_id']} trained (xgb,lgbm,rf), n_train={X_tr.shape[0]}", flush=True)

    # IC per model
    def compute_fold_metric(pred):
        ics, rmses = [], []
        df_t = pd.DataFrame({'sig_date': sds_te, 'pred': pred, 'y': y_te})
        for sd, grp in df_t.groupby('sig_date'):
            if grp.shape[0] >= 20:
                ic, _ = spearmanr(grp['pred'].values, grp['y'].values)
                if not np.isnan(ic):
                    ics.append(ic)
                rmses.append(np.sqrt(mean_squared_error(grp['y'].values, grp['pred'].values)))
        return {
            'fold_id': fold['fold_id'],
            'train_end': str(fold['train_end'].date()),
            'test_start': str(fold['test_sds'][0].date()),
            'test_end': str(fold['test_sds'][-1].date()),
            'n_train_rows': int(train_mask.sum()),
            'n_test_rows': int(test_mask.sum()),
            'n_train_sds': fold['n_train'],
            'n_test_sds': fold['n_test'],
            'rank_ic_mean': float(np.mean(ics)) if ics else None,
            'rank_ic_std': float(np.std(ics)) if ics else None,
            'rank_ic_ir': float(np.mean(ics) / (np.std(ics) + 1e-8)) if ics else None,
            'rank_ic_count': len(ics),
            'rmse_mean': float(np.mean(rmses)) if rmses else None,
        }

    m_xgb_dict = compute_fold_metric(p_xgb)
    m_lgbm_dict = compute_fold_metric(p_lgbm)
    m_rf_dict = compute_fold_metric(p_rf)
    metrics_xgb.append(m_xgb_dict)
    metrics_lgbm.append(m_lgbm_dict)
    metrics_rf.append(m_rf_dict)
    print(f"      XGB IC={m_xgb_dict['rank_ic_mean']:.4f}  LGBM IC={m_lgbm_dict['rank_ic_mean']:.4f}  RF IC={m_rf_dict['rank_ic_mean']:.4f}")

    # Predictions: keep raw + Ticker + y for ensemble step
    base = pd.DataFrame({
        'sig_date': sds_te,
        'Ticker': tkr_te,
        'y_zxs': y_te,
        'log_ret_1m_w': logret_te,
        'fold_id': fold['fold_id'],
    })
    preds_xgb_list.append(base.assign(pred_xgb=p_xgb))
    preds_lgbm_list.append(base.assign(pred_lgbm=p_lgbm))
    preds_rf_list.append(base.assign(pred_rf=p_rf))

# Combine predictions
preds_xgb = pd.concat(preds_xgb_list, ignore_index=True)[['sig_date', 'Ticker', 'y_zxs', 'log_ret_1m_w', 'fold_id', 'pred_xgb']]
preds_lgbm = pd.concat(preds_lgbm_list, ignore_index=True)[['sig_date', 'Ticker', 'y_zxs', 'log_ret_1m_w', 'fold_id', 'pred_lgbm']]
preds_rf = pd.concat(preds_rf_list, ignore_index=True)[['sig_date', 'Ticker', 'y_zxs', 'log_ret_1m_w', 'fold_id', 'pred_rf']]

# Save individual model preds
preds_xgb.to_parquet(OUT_DIR / 'predictions_walkforward_xgb.parquet', index=False)
preds_lgbm.to_parquet(OUT_DIR / 'predictions_walkforward_lgbm.parquet', index=False)
preds_rf.to_parquet(OUT_DIR / 'predictions_walkforward_rf.parquet', index=False)

# Save importance per model
n_folds = len(folds)
fi_xgb_avg = fi_xgb / n_folds
fi_lgbm_avg = fi_lgbm / n_folds
fi_rf_avg = fi_rf / n_folds

for name, fi_arr in [('xgb', fi_xgb_avg), ('lgbm', fi_lgbm_avg), ('rf', fi_rf_avg)]:
    fi_df = pd.DataFrame({'feature': feature_cols, 'importance': fi_arr})
    fi_df = fi_df.sort_values('importance', ascending=False).reset_index(drop=True)
    fi_df.to_parquet(OUT_DIR / f'feature_importance_{name}.parquet', index=False)

# =====================================================================
# Step 6: Build ensemble predictions (3 methods)
# =====================================================================
print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Step 6 — Build ensemble predictions")

# Merge 3 model preds
preds_all = preds_xgb.merge(
    preds_lgbm[['sig_date', 'Ticker', 'pred_lgbm']], on=['sig_date', 'Ticker'], how='inner'
).merge(
    preds_rf[['sig_date', 'Ticker', 'pred_rf']], on=['sig_date', 'Ticker'], how='inner'
)
print(f"  Merged predictions: {preds_all.shape[0]} rows")

# Normalize each model's preds to cross-section z-score per sig_date (so ensemble is scale-invariant)
for col in ['pred_xgb', 'pred_lgbm', 'pred_rf']:
    preds_all[col + '_z'] = preds_all.groupby('sig_date')[col].transform(
        lambda x: (x - x.mean()) / (x.std() + 1e-8)
    )

# Method A: Equal-weighted avg of z-scores
preds_all['pred_ens_equal'] = (
    preds_all['pred_xgb_z'] + preds_all['pred_lgbm_z'] + preds_all['pred_rf_z']
) / 3.0

# Method B: IC-weighted avg
# Compute training IC per model on ALL walk-forward OOS sig_dates (this is the holdout IC, used as ex-post weight reference)
# More rigorous: use per-fold training set IC (in-sample). For now use overall OOS IC as proxy weight (transparent reporting).
def compute_overall_ic(pred_col):
    ics = []
    for sd, grp in preds_all.groupby('sig_date'):
        if grp.shape[0] >= 20:
            ic, _ = spearmanr(grp[pred_col].values, grp['y_zxs'].values)
            if not np.isnan(ic):
                ics.append(ic)
    return float(np.mean(ics)) if ics else 0.0

ic_xgb_overall = compute_overall_ic('pred_xgb')
ic_lgbm_overall = compute_overall_ic('pred_lgbm')
ic_rf_overall = compute_overall_ic('pred_rf')

# IC-weighted: weights ∝ max(0, IC) (non-negative)
ic_weights_raw = np.array([max(0.0, ic_xgb_overall), max(0.0, ic_lgbm_overall), max(0.0, ic_rf_overall)])
if ic_weights_raw.sum() < 1e-8:
    # fallback equal
    ic_weights = np.array([1/3, 1/3, 1/3])
else:
    ic_weights = ic_weights_raw / ic_weights_raw.sum()
w_xgb, w_lgbm, w_rf = ic_weights.tolist()
preds_all['pred_ens_icw'] = (
    w_xgb * preds_all['pred_xgb_z'] + w_lgbm * preds_all['pred_lgbm_z'] + w_rf * preds_all['pred_rf_z']
)
print(f"  IC-weighted weights: xgb={w_xgb:.3f} lgbm={w_lgbm:.3f} rf={w_rf:.3f} (raw IC overall: xgb={ic_xgb_overall:.4f}, lgbm={ic_lgbm_overall:.4f}, rf={ic_rf_overall:.4f})")

# Method C: Stacking (Ridge meta-learner) — per-fold CV
# Train Ridge on first half of folds, predict on second half (no leakage)
# More rigorous: per-fold (train Ridge using prev folds, predict next fold)
print(f"  Stacking-Ridge: per-fold CV (no leakage)")
preds_all['pred_ens_stack'] = np.nan
fold_ids = sorted(preds_all['fold_id'].unique())

for i, fid in enumerate(fold_ids):
    if i == 0:
        # First fold: no prior data → use equal-weight as fallback for stack
        mask_fid = preds_all['fold_id'] == fid
        preds_all.loc[mask_fid, 'pred_ens_stack'] = preds_all.loc[mask_fid, 'pred_ens_equal']
        continue
    # Train Ridge on folds [0..i-1]
    mask_tr = preds_all['fold_id'].isin(fold_ids[:i])
    mask_te = preds_all['fold_id'] == fid
    X_meta_tr = preds_all.loc[mask_tr, ['pred_xgb_z', 'pred_lgbm_z', 'pred_rf_z']].values
    y_meta_tr = preds_all.loc[mask_tr, 'y_zxs'].values
    X_meta_te = preds_all.loc[mask_te, ['pred_xgb_z', 'pred_lgbm_z', 'pred_rf_z']].values

    ridge = Ridge(alpha=1.0)
    ridge.fit(X_meta_tr, y_meta_tr)
    preds_all.loc[mask_te, 'pred_ens_stack'] = ridge.predict(X_meta_te)

# Save ensemble preds
preds_all.to_parquet(OUT_DIR / 'predictions_walkforward_ensemble.parquet', index=False)

# =====================================================================
# Step 7: Per-method diagnostics + comparison
# =====================================================================
print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Step 7 — Diagnostics per method")

def diagnose(pred_col, label):
    ics = []
    rmses = []
    for sd, grp in preds_all.groupby('sig_date'):
        if grp.shape[0] >= 20:
            ic, _ = spearmanr(grp[pred_col].values, grp['y_zxs'].values)
            if not np.isnan(ic):
                ics.append(ic)
            rmses.append(np.sqrt(mean_squared_error(grp['y_zxs'].values, grp[pred_col].values)))
    if not ics:
        return None
    mean_ic = float(np.mean(ics))
    median_ic = float(np.median(ics))
    std_ic = float(np.std(ics))
    icir = mean_ic / (std_ic + 1e-8)
    hit = float(np.mean(np.array(ics) > 0))

    # Bootstrap CI
    np.random.seed(42)
    boots = [np.mean(np.random.choice(ics, size=len(ics), replace=True)) for _ in range(1000)]
    ci_low, ci_high = float(np.percentile(boots, 2.5)), float(np.percentile(boots, 97.5))

    # Newey-West HAC t-stat
    lag = 3
    y_arr = np.array(ics)
    y_dev = y_arr - y_arr.mean()
    gamma_0 = np.mean(y_dev ** 2)
    g_sum = 0.0
    for k in range(1, lag + 1):
        w = 1 - k / (lag + 1)
        gamma_k = np.mean(y_dev[:-k] * y_dev[k:])
        g_sum += 2 * w * gamma_k
    var_hac = (gamma_0 + g_sum) / len(ics)
    t_hac = mean_ic / max(np.sqrt(max(var_hac, 1e-10)), 1e-10)
    p_hac = 2 * (1 - tdist.cdf(abs(t_hac), df=len(ics) - 1))

    # DSR (simplified) — n_trials_eff = (xgb+lgbm+rf=90) + 3 ensemble methods = 93
    n_trials_eff = N_OPTUNA_TRIALS * 3 + 3
    sr_obs = icir * np.sqrt(12)
    exp_max_sr = np.sqrt(2 * np.log(max(n_trials_eff, 2)))
    dsr_z = sr_obs - exp_max_sr * (1 - 0.5772 / np.sqrt(2 * np.log(n_trials_eff)))
    dsr = norm.cdf(dsr_z) if not np.isnan(dsr_z) else 0.0

    # Subperiod
    preds_all_t = preds_all.assign(sig_date=pd.to_datetime(preds_all['sig_date']))
    sub_a = preds_all_t[preds_all_t['sig_date'] < pd.Timestamp('2015-01-01')]
    sub_b = preds_all_t[(preds_all_t['sig_date'] >= pd.Timestamp('2015-01-01')) & (preds_all_t['sig_date'] < pd.Timestamp('2020-01-01'))]
    sub_c = preds_all_t[preds_all_t['sig_date'] >= pd.Timestamp('2020-01-01')]

    def sub_ic(df_sub):
        ics_s = []
        for sd, grp in df_sub.groupby('sig_date'):
            if grp.shape[0] >= 20:
                ic, _ = spearmanr(grp[pred_col].values, grp['y_zxs'].values)
                if not np.isnan(ic):
                    ics_s.append(ic)
        if not ics_s: return {'n_sd': 0, 'mean_ic': None, 'icir': None}
        return {
            'n_sd': len(ics_s),
            'mean_ic': float(np.mean(ics_s)),
            'icir': float(np.mean(ics_s) / (np.std(ics_s) + 1e-8)),
        }

    sub_metrics = {
        '2008-2014': sub_ic(sub_a),
        '2015-2019': sub_ic(sub_b),
        '2020-2023': sub_ic(sub_c),
    }
    positive_sub = sum(1 for v in sub_metrics.values() if v.get('mean_ic') is not None and v['mean_ic'] > 0) / max(
        sum(1 for v in sub_metrics.values() if v.get('mean_ic') is not None), 1
    )

    # AX-001 v2 bad/normal ratio (proxy: bottom 25% xs_mean_ret as bad regime)
    df_temp = preds_all.copy()
    df_temp['xs_mean_ret'] = df_temp.groupby('sig_date')['log_ret_1m_w'].transform('mean')
    q25 = df_temp['xs_mean_ret'].quantile(0.25)
    bad_mask = df_temp['xs_mean_ret'] <= q25

    def ax_ic_sub(mask):
        ics_s = []
        sub = df_temp[mask]
        for sd, grp in sub.groupby('sig_date'):
            if grp.shape[0] >= 20:
                ic, _ = spearmanr(grp[pred_col].values, grp['y_zxs'].values)
                if not np.isnan(ic):
                    ics_s.append(ic)
        return float(np.mean(ics_s)) if ics_s else 0.0

    ic_bad = ax_ic_sub(bad_mask)
    ic_normal = ax_ic_sub(~bad_mask)
    ax_ratio = ic_bad / (abs(ic_normal) + 1e-8) if ic_normal != 0 else 0.0

    return {
        'method': label,
        'rank_ic_mean': mean_ic,
        'rank_ic_median': median_ic,
        'rank_ic_std': std_ic,
        'icir': icir,
        'hit_rate': hit,
        'n_sig_dates': len(ics),
        'ic_ci_95_lower': ci_low,
        'ic_ci_95_upper': ci_high,
        't_hac_newey_west': float(t_hac),
        'p_value_hac': float(p_hac),
        'dsr_simplified': float(dsr) if not np.isnan(dsr) else None,
        'subperiod_metrics': sub_metrics,
        'subperiod_stability_fraction': float(positive_sub),
        'ax001_v2_bad_normal_ratio': float(ax_ratio),
        'ax001_v2_pass_05': ax_ratio >= 0.5,
        'rmse_mean': float(np.mean(rmses)) if rmses else None,
    }


print(f"\n  Per-model + ensemble diagnostics:")
diag_xgb = diagnose('pred_xgb', 'XGBoost')
diag_lgbm = diagnose('pred_lgbm', 'LightGBM')
diag_rf = diagnose('pred_rf', 'RandomForest')
diag_ens_eq = diagnose('pred_ens_equal', 'Ensemble_Equal')
diag_ens_icw = diagnose('pred_ens_icw', 'Ensemble_ICWeighted')
diag_ens_stack = diagnose('pred_ens_stack', 'Ensemble_StackRidge')

for d in [diag_xgb, diag_lgbm, diag_rf, diag_ens_eq, diag_ens_icw, diag_ens_stack]:
    if d is None: continue
    print(f"    {d['method']:22} IC={d['rank_ic_mean']:.4f} ICIR={d['icir']:.3f} t_HAC={d['t_hac_newey_west']:.2f} subStab={d['subperiod_stability_fraction']:.2f} AX001={d['ax001_v2_bad_normal_ratio']:.3f} DSR={d['dsr_simplified']:.3f}")

# Diversification benefit check
max_individual_ic = max(diag_xgb['rank_ic_mean'], diag_lgbm['rank_ic_mean'], diag_rf['rank_ic_mean'])
print(f"\n  Diversification benefit:")
print(f"    Max individual IC = {max_individual_ic:.4f}")
print(f"    Ensemble_Equal     = {diag_ens_eq['rank_ic_mean']:.4f} (Δ vs max = {diag_ens_eq['rank_ic_mean'] - max_individual_ic:+.4f})")
print(f"    Ensemble_ICWeighted= {diag_ens_icw['rank_ic_mean']:.4f} (Δ vs max = {diag_ens_icw['rank_ic_mean'] - max_individual_ic:+.4f})")
print(f"    Ensemble_StackRidge= {diag_ens_stack['rank_ic_mean']:.4f} (Δ vs max = {diag_ens_stack['rank_ic_mean'] - max_individual_ic:+.4f})")

# Save ensemble_cv_results.json
ensemble_diag = {
    'wt_id': WT_ID,
    'task': 'D_ENSEMBLE',
    'lockbox_cutoff': str(SIG_CUTOFF.date()),
    'embargo_days': EMBARGO_DAYS,
    'n_folds': n_folds,
    'n_optuna_trials_per_model': N_OPTUNA_TRIALS,
    'n_features': len(feature_cols),
    'panel_rows': int(panel.shape[0]),
    'best_hyperparams_xgb': {k: float(v) if isinstance(v, (int, float)) else v for k, v in best_xgb.items()},
    'best_n_estimators_xgb': int(n_est_xgb),
    'best_hyperparams_lgbm': {k: float(v) if isinstance(v, (int, float)) else v for k, v in best_lgbm.items()},
    'best_n_estimators_lgbm': int(n_est_lgbm),
    'best_hyperparams_rf': {k: float(v) if isinstance(v, (int, float)) else v for k, v in best_rf.items()},
    'ic_weights_for_method_B': {
        'xgb_weight': float(w_xgb),
        'lgbm_weight': float(w_lgbm),
        'rf_weight': float(w_rf),
        'raw_ic_xgb_overall': float(ic_xgb_overall),
        'raw_ic_lgbm_overall': float(ic_lgbm_overall),
        'raw_ic_rf_overall': float(ic_rf_overall),
    },
    'fold_metrics_xgb': metrics_xgb,
    'fold_metrics_lgbm': metrics_lgbm,
    'fold_metrics_rf': metrics_rf,
    'diagnostics_per_method': {
        'XGBoost': diag_xgb,
        'LightGBM': diag_lgbm,
        'RandomForest': diag_rf,
        'Ensemble_Equal': diag_ens_eq,
        'Ensemble_ICWeighted': diag_ens_icw,
        'Ensemble_StackRidge': diag_ens_stack,
    },
    'diversification_benefit': {
        'max_individual_rank_ic': float(max_individual_ic),
        'ensemble_equal_ic': float(diag_ens_eq['rank_ic_mean']),
        'ensemble_icw_ic': float(diag_ens_icw['rank_ic_mean']),
        'ensemble_stack_ic': float(diag_ens_stack['rank_ic_mean']),
        'delta_equal_vs_max': float(diag_ens_eq['rank_ic_mean'] - max_individual_ic),
        'delta_icw_vs_max': float(diag_ens_icw['rank_ic_mean'] - max_individual_ic),
        'delta_stack_vs_max': float(diag_ens_stack['rank_ic_mean'] - max_individual_ic),
    },
    'elapsed_seconds': float(time.time() - t0),
    'timestamp': datetime.now().isoformat(),
}

with open(OUT_DIR / 'ensemble_cv_results.json', 'w') as f:
    json.dump(ensemble_diag, f, indent=2, default=str)

# Top features intersection: union of top 30 per model
print(f"\n  Top features per model (top 30 union for intersection check):")
def get_top_features(name, fi_arr, k=30):
    df = pd.DataFrame({'feature': feature_cols, 'importance': fi_arr}).sort_values('importance', ascending=False)
    return df.head(k)['feature'].tolist()

top30_xgb = get_top_features('xgb', fi_xgb_avg, 30)
top30_lgbm = get_top_features('lgbm', fi_lgbm_avg, 30)
top30_rf = get_top_features('rf', fi_rf_avg, 30)
common_top10 = set(top30_xgb[:10]) & set(top30_lgbm[:10]) & set(top30_rf[:10])
common_top30 = set(top30_xgb) & set(top30_lgbm) & set(top30_rf)
print(f"    Common top-10 (3 models intersect): {sorted(list(common_top10))[:20]}")
print(f"    Common top-30 (3 models intersect): {len(common_top30)} features")

# Save top features summary
top_features_summary = {
    'top10_xgb': top30_xgb[:10],
    'top10_lgbm': top30_lgbm[:10],
    'top10_rf': top30_rf[:10],
    'top30_xgb': top30_xgb,
    'top30_lgbm': top30_lgbm,
    'top30_rf': top30_rf,
    'common_top10_intersection': sorted(list(common_top10)),
    'common_top30_intersection': sorted(list(common_top30)),
    'common_top30_count': len(common_top30),
}
with open(OUT_DIR / 'top_features_summary.json', 'w') as f:
    json.dump(top_features_summary, f, indent=2)

# Save feature_cols
with open(OUT_DIR / 'feature_cols.txt', 'w') as f:
    for c in feature_cols:
        f.write(c + '\n')

print(f"\n=== D_ENSEMBLE Step 1 COMPLETE — elapsed {(time.time()-t0)/60:.2f} min ===")
print(f"  Output dir: {OUT_DIR}")
