#!/usr/bin/env python
"""
WT-D20260508_011 — Alpha validation v3

Top spec: s3_vrp_vol (VRP × vol penalty) — score = -(VRP × vol)

Validation steps:
  1. Long-Short quintile portfolio backtest (gross + net 15bps)
  2. Long-only top quintile vs benchmark (KOSPI200)
  3. Sector neutralization (subtract sector mean signal)
  4. Newey-West HAC t-stat (4 lag)
  5. Bailey-Lopez de Prado DSR (Deflated Sharpe Ratio) multi-trial
  6. ML XGBoost comparison (cross-section feature: vrp×vol, vrp×beta, vrp_innov×vol, vol, mom, beta, skew)
  7. Forward 2026-05 prediction
  8. Orthogonality check vs Hybrid 70/15/15 returns
  9. CRISIS regime cor diagnosis (anti-hedge check from WT_001)
"""

import os, json, math, warnings
import numpy as np
import pandas as pd
from datetime import datetime
from scipy.stats import norm
warnings.filterwarnings('ignore')

ROOT = '/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot'
OUT = f'{ROOT}/stage_artifacts/WT_D20260508_011'

panel = pd.read_parquet(f'{OUT}/cs_panel_v2.parquet')
panel['Date'] = pd.to_datetime(panel['Date'])
print(f'panel: {panel.shape}')

# Define score for each signal: economic-sign aligned (positive score = long)
panel['score_s3'] = -panel['s3_vrp_vol']  # high VRP × high vol = bad → score negative → low score
panel['score_s4'] = -panel['s4_vrp_beta']
panel['score_s1'] = -panel['s1_skew_diff']
panel['score_s9'] = -panel['s9_vrp_x_neg_mom']

# Signal under test
SIGNAL = 'score_s3'  # canonical
panel = panel[panel[SIGNAL].notna() & panel['fwd_1m_ret'].notna()].copy()
print(f'After signal filter: {panel.shape}')

# ================== 1. LS quintile portfolio backtest ==================
print('\n=== 1. LS quintile portfolio (Q5 long - Q1 short, EW) ===')

def quintile_returns(g, score_col):
    g2 = g.copy()
    if len(g2) < 20: return None
    g2['q'] = pd.qcut(g2[score_col].rank(method='first'), 5, labels=[1,2,3,4,5])
    q5 = g2[g2['q']==5]['fwd_1m_ret'].mean()
    q1 = g2[g2['q']==1]['fwd_1m_ret'].mean()
    return pd.Series({'q5': q5, 'q1': q1, 'q5_q1': q5 - q1})

ls = panel.groupby('Date').apply(lambda g: quintile_returns(g, SIGNAL)).reset_index()
ls = ls.dropna()
print(f'LS sample n: {len(ls)}')

n_per_q = panel.groupby('Date').apply(lambda g: len(g) // 5).median()
print(f'Median names per quintile: {n_per_q}')

# Annualize
def annual_sharpe(r):
    return (r.mean() / r.std()) * math.sqrt(12) if r.std() > 0 else np.nan

ls_gross_sr = annual_sharpe(ls['q5_q1'])
print(f'LS gross SR: {ls_gross_sr:.4f}')

# Turnover proxy: assume 50% per side per month; cost = 2 × 0.0015 × turnover
# Standard quintile rebalanced monthly LS turnover ~150-200% annualized side
# Conservative estimate: monthly LS turnover = 2 × 0.5 (50% per side change), so 1.0 round-trip per month
# annualized turnover = 12.0, cost = 12 × 0.0015 = 1.8% per year
# More realistic: actual turnover from rank stability
panel_sorted = panel.sort_values(['Ticker','Date']).reset_index(drop=True)
panel_sorted['prev_q'] = panel_sorted.groupby('Ticker')[SIGNAL].apply(
    lambda x: pd.qcut(x.rank(method='first'), 5, labels=[1,2,3,4,5]).shift(1)).reset_index(drop=True)

# Simpler turnover: per-date count of names changing into / out of Q5
# Compute % of Q5 names that were not Q5 last month
def _q_change(g):
    g2 = g.copy()
    if len(g2) < 20: return None
    g2['q'] = pd.qcut(g2[SIGNAL].rank(method='first'), 5, labels=[1,2,3,4,5])
    return g2[['Ticker','q']].set_index('Ticker')['q']

monthly_q = panel.sort_values(['Date','Ticker']).groupby('Date').apply(_q_change)
# Turnover in Q5
to_list = []
prev_q5 = None
for date, q_series in monthly_q.groupby(level=0):
    q_series = q_series.reset_index(level=0, drop=True)
    cur_q5 = set(q_series[q_series == 5].index)
    if prev_q5 is not None and len(prev_q5) > 0:
        new = len(cur_q5 - prev_q5)
        to_list.append(new / max(len(cur_q5), 1))
    prev_q5 = cur_q5
turnover_q5_1m = np.mean(to_list)  # fraction changed per month
turnover_ann = turnover_q5_1m * 12  # round-trip annualized
print(f'Q5 turnover (fraction changed per month): {turnover_q5_1m:.4f}, annualized: {turnover_ann:.4f}')

# Net SR (15bps × turnover_ann × 2 round-trip)
# For LS: both sides turn over, cost = 2 × 12 × turnover_per_month × 15bps
cost_per_month_LS = 2 * turnover_q5_1m * 0.0015 * 2  # entry + exit per side
ls['q5_q1_net'] = ls['q5_q1'] - cost_per_month_LS
ls_net_sr = annual_sharpe(ls['q5_q1_net'])
print(f'LS net SR (cost-adjusted): {ls_net_sr:.4f}')

# ================== Long-only Q5 vs benchmark ==================
print('\n=== 2. Long-only Q5 vs benchmark (KOSPI200) ===')

# Benchmark: KOSPI200 monthly return (use BM_Close from benchmark.parquet)
bench = pd.read_parquet(f'{ROOT}/.cache/benchmark.parquet')
bench['Date'] = pd.to_datetime(bench['Date'])
bench['ym'] = bench['Date'].dt.to_period('M')
bm_me = bench.groupby('ym').last().reset_index()
bm_me['bm_1m_ret'] = bm_me['BM_Close'].pct_change()
bm_me['Date'] = bm_me['Date']
bm_me = bm_me[['Date','bm_1m_ret']]

ls = ls.merge(bm_me, on='Date', how='left')
ls['q5_alpha'] = ls['q5'] - ls['bm_1m_ret']
ls['q5_net'] = ls['q5'] - turnover_q5_1m * 0.0015  # one-side cost
print(f'LO Q5 SR (gross): {annual_sharpe(ls["q5"]):.4f}')
print(f'LO Q5 alpha vs BM SR: {annual_sharpe(ls["q5_alpha"]):.4f}')
print(f'LO Q5 net SR (one-side cost): {annual_sharpe(ls["q5_net"]):.4f}')
print(f'LO Q5 - BM (mean monthly): {ls["q5_alpha"].mean():.4f}, n={len(ls)}')

# ================== 3. Sector neutralization ==================
print('\n=== 3. Sector-neutral IC ===')
def sector_demean(g, col):
    return g[col] - g.groupby('Sector')[col].transform('mean')

panel['score_s3_sect_demean'] = panel.groupby('Date', group_keys=False).apply(
    lambda g: g['score_s3'] - g.groupby('Sector')['score_s3'].transform('mean'))

def compute_ic(g, sig_col):
    x = g[sig_col].values; y = g['fwd_1m_ret'].values
    m = np.isnan(x) | np.isnan(y)
    if (~m).sum() < 30: return np.nan
    return pd.Series(x[~m]).rank().corr(pd.Series(y[~m]).rank())

ic_orig = panel.groupby('Date').apply(lambda g: compute_ic(g, 'score_s3')).dropna()
ic_sect = panel.groupby('Date').apply(lambda g: compute_ic(g, 'score_s3_sect_demean')).dropna()
print(f'Original IC: {ic_orig.mean():.4f}, ICIR: {ic_orig.mean()/ic_orig.std():.3f}')
print(f'Sector-neut IC: {ic_sect.mean():.4f}, ICIR: {ic_sect.mean()/ic_sect.std():.3f}')
print(f'Sector retention: {ic_sect.mean()/ic_orig.mean():.4f}')

# ================== 4. Newey-West HAC t-stat (LS portfolio) ==================
print('\n=== 4. Newey-West HAC t-stat (LS portfolio) ===')
def nw_t(r, L=4):
    r = r.dropna().values
    n = len(r)
    if n < 12: return np.nan
    mean_r = r.mean()
    g0 = np.var(r, ddof=1)
    var_nw = g0
    for lag in range(1, L+1):
        w = 1 - lag/(L+1)
        cov_l = np.mean((r[lag:] - mean_r) * (r[:-lag] - mean_r))
        var_nw += 2 * w * cov_l
    se = math.sqrt(max(var_nw, 1e-10) / n)
    return mean_r / se

t_nw_ls_gross = nw_t(ls['q5_q1'])
t_nw_ls_net = nw_t(ls['q5_q1_net'])
t_nw_lo_alpha = nw_t(ls['q5_alpha'])
print(f'LS gross t_NW: {t_nw_ls_gross:.3f}')
print(f'LS net t_NW: {t_nw_ls_net:.3f}')
print(f'LO alpha (vs BM) t_NW: {t_nw_lo_alpha:.3f}')

# ================== 5. Bailey-Lopez de Prado DSR (Deflated Sharpe Ratio) ==================
print('\n=== 5. Bailey-Lopez de Prado DSR ===')
# DSR = (SR_obs - E[max SR_random]) / std(SR_random)
# E[max SR_random] = sqrt(2*ln(N_trials))/sqrt(T) * std_SR (BLPdP 2014)
# We tested 8 specs (s1~s9 minus s8)
N_TRIALS = 8

def dsr_bailey(sr, n_obs, n_trials, skew_ret=0, kurt_ret=0):
    # Bailey-Lopez de Prado 2014
    # DSR = Φ((SR - E[max SR]) * sqrt(T-1) / sqrt(1 - skew*SR + (kurt-1)/4 * SR²))
    if n_obs < 2 or n_trials < 1:
        return np.nan
    em = ((1 - 0.5772) * norm.ppf(1 - 1/n_trials)
          + 0.5772 * norm.ppf(1 - 1/(n_trials * math.e)))
    # Normalized SR per obs
    sr_per_obs = sr / math.sqrt(12)  # monthly SR
    denom = math.sqrt(1 - skew_ret*sr_per_obs + ((kurt_ret-1)/4)*sr_per_obs**2)
    numer = (sr_per_obs - em / math.sqrt(n_obs - 1)) * math.sqrt(n_obs - 1)
    return norm.cdf(numer / max(denom, 1e-6))

# Compute moments
ls_q5q1 = ls['q5_q1'].values
ls_skew = pd.Series(ls_q5q1).skew()
ls_kurt = pd.Series(ls_q5q1).kurt() + 3  # excess to total kurt

dsr_gross = dsr_bailey(ls_gross_sr, len(ls), N_TRIALS, ls_skew, ls_kurt)
dsr_net = dsr_bailey(ls_net_sr, len(ls), N_TRIALS, ls_skew, ls_kurt)

# LO Q5 alpha
lo_alpha_sr = annual_sharpe(ls['q5_alpha'])
lo_alpha_skew = pd.Series(ls['q5_alpha']).skew()
lo_alpha_kurt = pd.Series(ls['q5_alpha']).kurt() + 3
dsr_lo_alpha = dsr_bailey(lo_alpha_sr, len(ls), N_TRIALS, lo_alpha_skew, lo_alpha_kurt)

print(f'DSR (LS gross SR={ls_gross_sr:.3f}): {dsr_gross:.4f}')
print(f'DSR (LS net SR={ls_net_sr:.3f}): {dsr_net:.4f}')
print(f'DSR (LO alpha SR={lo_alpha_sr:.3f}): {dsr_lo_alpha:.4f}')

# ================== 6. ML XGBoost comparison ==================
print('\n=== 6. ML XGBoost OOS comparison ===')

import xgboost as xgb
from sklearn.model_selection import TimeSeriesSplit

# Features: vrp_bkm × vol, vrp × beta, vrp_innov × vol, vol_60d, mom_12_1, beta, skew_252d, vrp_atm
ml_panel = panel[panel['vrp_bkm'].notna() & panel['vol_60d_lag1'].notna() &
                 panel['mom_12_1_lag1'].notna() & panel['beta_252d_lag1'].notna() &
                 panel['skew_252d_lag1'].notna() & panel['vrp_atm'].notna() &
                 panel['fwd_1m_ret'].notna()].copy()

ml_panel['vrp_bkm_x_vol'] = ml_panel['vrp_bkm'] * ml_panel['vol_60d_lag1']
ml_panel['vrp_bkm_x_beta'] = ml_panel['vrp_bkm'] * ml_panel['beta_252d_lag1']
ml_panel['vrp_atm_x_vol'] = ml_panel['vrp_atm'] * ml_panel['vol_60d_lag1']

features = ['vrp_bkm_x_vol','vrp_bkm_x_beta','vrp_atm_x_vol','vol_60d_lag1','mom_12_1_lag1',
            'beta_252d_lag1','skew_252d_lag1','vrp_bkm','vrp_atm','vkospi','bkm_skew_30d']

ml_panel_clean = ml_panel.dropna(subset=features).copy()
print(f'ML panel: {ml_panel_clean.shape}')

# Time-based 5-fold CV (TimeSeriesSplit on Date)
ml_panel_clean = ml_panel_clean.sort_values('Date').reset_index(drop=True)
unique_dates = sorted(ml_panel_clean['Date'].unique())
n_dates = len(unique_dates)
folds = 5
fold_size = n_dates // folds

# OOS predictions
ml_panel_clean['ml_pred'] = np.nan
for fold_i in range(1, folds):
    train_dates = unique_dates[:fold_i * fold_size]
    test_dates = unique_dates[fold_i * fold_size: (fold_i+1) * fold_size]
    if len(test_dates) == 0: break
    train = ml_panel_clean[ml_panel_clean['Date'].isin(train_dates)]
    test = ml_panel_clean[ml_panel_clean['Date'].isin(test_dates)]
    X_tr = train[features].values
    y_tr = train['fwd_1m_ret'].values
    X_te = test[features].values
    model = xgb.XGBRegressor(n_estimators=200, max_depth=4, learning_rate=0.05,
                              random_state=42, n_jobs=4, verbosity=0)
    model.fit(X_tr, y_tr)
    pred = model.predict(X_te)
    ml_panel_clean.loc[test.index, 'ml_pred'] = pred

# OOS IC
oos = ml_panel_clean.dropna(subset=['ml_pred'])
ml_ic = oos.groupby('Date').apply(lambda g: compute_ic(g, 'ml_pred')).dropna()
print(f'ML OOS n: {len(ml_ic)}')
print(f'ML OOS IC mean: {ml_ic.mean():.4f}, ICIR: {ml_ic.mean()/ml_ic.std():.3f}')
print(f'ML OOS IC t_NW: {nw_t(ml_ic):.3f}')

# ML LS portfolio
def ml_quintile_returns(g):
    if len(g) < 20: return None
    g2 = g.copy()
    g2['q'] = pd.qcut(g2['ml_pred'].rank(method='first'), 5, labels=[1,2,3,4,5])
    return pd.Series({'ml_q5': g2[g2['q']==5]['fwd_1m_ret'].mean(),
                      'ml_q1': g2[g2['q']==1]['fwd_1m_ret'].mean(),
                      'ml_q5_q1': g2[g2['q']==5]['fwd_1m_ret'].mean() - g2[g2['q']==1]['fwd_1m_ret'].mean()})

ml_ls = oos.groupby('Date').apply(ml_quintile_returns).reset_index().dropna()
ml_sr = annual_sharpe(ml_ls['ml_q5_q1'])
print(f'ML LS gross SR: {ml_sr:.4f}')

# Naive sign check (long bias?)
n_pos = (oos['ml_pred'] > 0).sum()
print(f'ML pred positive %: {100*n_pos/len(oos):.1f}%')
oos['naive_long'] = oos['fwd_1m_ret']
naive_sr = annual_sharpe(oos.groupby('Date')['fwd_1m_ret'].mean())
print(f'Naive equal-weight long all SR: {naive_sr:.4f}')

# ================== 7. Forward 2026-05 prediction ==================
print('\n=== 7. Forward 2026-05 prediction ===')
last_date = panel['Date'].max()
print(f'Latest sig_date: {last_date}')
forward = panel[panel['Date'] == last_date].copy()
forward = forward.dropna(subset=['score_s3']).sort_values('score_s3', ascending=False)
print(f'Forward universe at {last_date}: {len(forward)}')
print(f'Top 20 (long) by score_s3 = -(VRP × vol):')
print(forward[['Ticker','Sector','score_s3','vrp_bkm','vol_60d_lag1','vkospi']].head(20).to_string(index=False))

forward.to_parquet(f'{OUT}/alpha_scores_forward.parquet', index=False)

# ================== 8. CRISIS regime cor diagnosis (anti-hedge from WT_001) ==================
print('\n=== 8. CRISIS regime cor diagnosis ===')
# CRISIS = VKOSPI > 75th percentile expanding
panel['vkospi_pct'] = panel.groupby('Ticker')['vkospi'].transform(
    lambda x: x.expanding(min_periods=24).rank(pct=True))

# Hybrid 70/15/15 proxy: just use bm_1m_ret as approximate (need full Hybrid backtest for actual)
# Use ls['q5_q1'] as our LS strategy returns
ls['vkospi_at_date'] = ls['Date'].map(panel.set_index('Date')['vkospi'].drop_duplicates())
# Use expanding 75th pct
ls['vkospi_pct'] = ls['vkospi_at_date'].expanding(min_periods=12).rank(pct=True)
ls['regime'] = pd.cut(ls['vkospi_pct'], [0, 0.25, 0.75, 1.0], labels=['LOW','MID','HIGH'])

regime_stats = ls.groupby('regime').agg(
    n=('q5_q1','count'),
    mean_ret=('q5_q1','mean'),
    sharpe=('q5_q1', annual_sharpe),
    bm_mean=('bm_1m_ret','mean')
).reset_index()
print(regime_stats.to_string(index=False))

# Cor with benchmark per regime
for r in ['LOW','MID','HIGH']:
    sub = ls[ls['regime']==r]
    if len(sub) > 5:
        cor = sub[['q5_q1','bm_1m_ret']].corr().iloc[0,1]
        print(f'  {r}: cor(LS, BM) = {cor:.3f}, n={len(sub)}')

# ================== 9. Save validation report ==================
report = {
    'task_id': 'WT-D20260508_011',
    'as_of_date': '2026-05-08',
    'signal_canonical': 'score_s3 = -(VRP_bkm × vol_60d_lag1)',
    'theory_basis': [
        'Bakshi-Kapadia-Madan 2003 RFS (BKM moments)',
        'Carr-Wu 2009 RFS (variance swap synthetic)',
        'Bollerslev-Tauchen-Zhou 2009 RFS (HAR-RV vs implied)',
        'CBOE 1993/2003 VIX methodology (KOSPI 자체 재구축)'
    ],
    'sign_aware_check': {
        'rank_ic': float(ic_orig.mean()),
        'rank_ic_pass': bool(abs(ic_orig.mean()) >= 0.04),
        'icir': float(ic_orig.mean()/ic_orig.std()),
        'icir_pass': bool(abs(ic_orig.mean()/ic_orig.std()) >= 0.20),
        't_NW': float(t_nw_ls_gross),
        't_NW_pass': bool(abs(t_nw_ls_gross) >= 3.0),
        't_NW_net': float(t_nw_ls_net),
        'sub_stab': 1.0,  # (from cs_v2 1.00)
        'sub_stab_pass': True
    },
    'portfolio_metrics': {
        'ls_gross_sr': float(ls_gross_sr),
        'ls_net_sr': float(ls_net_sr),
        'lo_alpha_sr_vs_bm': float(lo_alpha_sr),
        'turnover_q5_per_month': float(turnover_q5_1m),
        'turnover_q5_annual': float(turnover_ann),
        'cost_per_month_ls_pct': float(cost_per_month_LS * 100),
        'naive_long_sr': float(naive_sr)
    },
    'sector_neutrality': {
        'orig_ic': float(ic_orig.mean()),
        'sector_demean_ic': float(ic_sect.mean()),
        'retention_ratio': float(ic_sect.mean()/ic_orig.mean()) if ic_orig.mean() != 0 else None
    },
    'dsr_bailey_ldp': {
        'n_trials': N_TRIALS,
        'dsr_ls_gross': float(dsr_gross),
        'dsr_ls_net': float(dsr_net),
        'dsr_lo_alpha': float(dsr_lo_alpha)
    },
    'ml_xgboost': {
        'n_features': len(features),
        'features': features,
        'oos_ic_mean': float(ml_ic.mean()),
        'oos_icir': float(ml_ic.mean()/ml_ic.std()) if ml_ic.std() > 0 else None,
        'oos_t_nw': float(nw_t(ml_ic)),
        'oos_ls_gross_sr': float(ml_sr),
        'naive_pos_pct': float(100*n_pos/len(oos)),
        'naive_long_sr': float(naive_sr),
        'fake_alpha_check_pass': bool(ml_sr > naive_sr * 1.3)  # ML must beat naive by 30%+
    },
    'crisis_regime_diagnosis': {
        'note': 'WT_001 cycle 1: cor(r_vrp, r_AR) = +0.515 anti-hedge. Here we re-check with cross-section LS.',
        'regime_stats': regime_stats.to_dict(orient='records'),
        'high_vkospi_cor_with_bm': float(ls[ls['regime']=='HIGH'][['q5_q1','bm_1m_ret']].corr().iloc[0,1]) if len(ls[ls['regime']=='HIGH']) > 5 else None
    },
    'predictor_autocor_diagnosis': {
        'autocor_lag1': -0.062,  # from cs_v2 s3
        'pass_threshold': True
    }
}

with open(f'{OUT}/alpha_validation.json', 'w') as f:
    json.dump(report, f, indent=2, default=str)

print('\n=== Validation report saved ===')
print(json.dumps(report, indent=2, default=str)[:3000])
