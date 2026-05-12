#!/usr/bin/env python
"""
WT-D20260508_011 — VRP cross-section signal 4 sub-variants

Inputs:
  - stage_artifacts/WT_D20260508_011/vrp_signals_monthly.parquet (VRP 4 모형 monthly)
  - stage_artifacts/WT_D20260508_011/vkospi_reconstruction.parquet (daily)
  - .cache/rawdata.parquet (full panel)
  - .cache/factor_db/ — factor cache for vol, beta, momentum

Cross-section signals:
  S1 (BKM-Skew Diff): 종목별 realized skewness - KOSPI200 BKM skew (bkm_skew_30d)
                      cross-section: 보수적 종목 ranking
  S2 (VRP-Beta): 종목별 r_i ~ VRP_t (rolling 36m) → 종목별 VRP-beta
                  Hypothesis: 낮은 VRP-beta = 위기 시 우월 (hedge property)
  S3 (Conditional Vol penalty): VRP_t (high) × σ_i,t-1 (negative)
                                 = high VRP 시점 high-vol 종목 underperform
  S4 (VKOSPI-Conditional Momentum): VKOSPI > median 시 momentum reverse
                                     (low momentum 종목 outperform when VKOSPI high)

Output:
  - stage_artifacts/WT_D20260508_011/cs_signals_monthly.parquet
  - stage_artifacts/WT_D20260508_011/predictor_autocor_diagnosis.json
"""

import os
import json
import math
import warnings
import numpy as np
import pandas as pd
from datetime import datetime

warnings.filterwarnings('ignore')

ROOT = '/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot'
OUT = f'{ROOT}/stage_artifacts/WT_D20260508_011'

# ================== Load VRP monthly ==================
print('Loading VRP monthly signals...')
vrp = pd.read_parquet(f'{OUT}/vrp_signals_monthly.parquet')
vrp['sig_date'] = pd.to_datetime(vrp['sig_date'])
vrp['ym_str'] = vrp['sig_date'].dt.strftime('%Y%m')
print(f'  vrp shape: {vrp.shape}, range: {vrp["sig_date"].min()} ~ {vrp["sig_date"].max()}')

# ================== Load RAWDATA (panel) ==================
print('Loading RAWDATA panel...')
raw = pd.read_parquet(f'{ROOT}/.cache/rawdata.parquet')
raw['Date'] = pd.to_datetime(raw['Date'])
print(f'  raw shape: {raw.shape}, dates: {raw["Date"].min()} ~ {raw["Date"].max()}')

# Universe filter: KOSPI200 ∪ KOSDAQ150 (PIT, t-1 K200/KQ150 = 1)
# Liquidity: 20-day avg trading value ≥ 5e7 KRW (request.json mandate)
raw = raw.sort_values(['Ticker','Date']).reset_index(drop=True)

# 20-day avg trading value (Vol * Close)
raw['tv_daily'] = raw['Vol'] * raw['Close']
raw['tv_20d'] = raw.groupby('Ticker')['tv_daily'].transform(lambda x: x.rolling(20, min_periods=10).mean())

# t-1 lag for universe / liquidity (PIT)
raw['K200_lag1'] = raw.groupby('Ticker')['K200'].shift(1)
raw['KQ150_lag1'] = raw.groupby('Ticker')['KQ150'].shift(1)
raw['tv_20d_lag1'] = raw.groupby('Ticker')['tv_20d'].shift(1)

# Universe membership (per row)
raw['universe'] = ((raw['K200_lag1'] == 1) | (raw['KQ150_lag1'] == 1)) & (raw['tv_20d_lag1'] >= 5e7)

# ================== Daily features ==================
# log returns
raw['log_ret'] = np.log1p(raw['Ret'].fillna(0))

# rolling features: 20-day vol, 252-day vol
raw['vol_20d'] = raw.groupby('Ticker')['log_ret'].transform(lambda x: x.rolling(20, min_periods=10).std()) * math.sqrt(252)
raw['vol_60d'] = raw.groupby('Ticker')['log_ret'].transform(lambda x: x.rolling(60, min_periods=30).std()) * math.sqrt(252)
# 252-day skewness
raw['skew_252d'] = raw.groupby('Ticker')['log_ret'].transform(lambda x: x.rolling(252, min_periods=120).skew())
# 12-1 momentum (252-day return excl last 22)
raw['ret_252d'] = raw.groupby('Ticker')['Close'].transform(lambda x: x.pct_change(252))
raw['ret_22d'] = raw.groupby('Ticker')['Close'].transform(lambda x: x.pct_change(22))
raw['mom_12_1'] = raw['ret_252d'] - raw['ret_22d']

# t-1 lag for predictors
for c in ['vol_20d', 'vol_60d', 'skew_252d', 'mom_12_1', 'Close']:
    raw[f'{c}_lag1'] = raw.groupby('Ticker')[c].shift(1)

# Month-end snapshot (last business day per (Ticker, ym))
raw['ym'] = raw['Date'].dt.to_period('M')
me_idx = raw.groupby(['Ticker','ym'])['Date'].idxmax()
me = raw.loc[me_idx].reset_index(drop=True).copy()

# Forward 1m return (per Ticker, sig_date → t+1 close vs t close)
me_sorted = me.sort_values(['Ticker','Date']).reset_index(drop=True)
me_sorted['Close_fwd1m'] = me_sorted.groupby('Ticker')['Close'].shift(-1)
me_sorted['fwd_1m_ret'] = (me_sorted['Close_fwd1m'] / me_sorted['Close']) - 1.0

print(f'\nMonth-end panel: {me_sorted.shape}, unique tickers: {me_sorted["Ticker"].nunique()}')

# ================== VRP-Beta (S2) — rolling 36m ==================
print('Computing VRP-beta (rolling 36m)...')

# Use vrp_cw as canonical (highest mean coherence) — could test all 4
# Actually compute beta for each VRP variant separately
vrp_vars = ['vrp_cw', 'vrp_bkm', 'vrp_vkospi', 'vrp_atm']

# For each ticker, monthly return
me_sorted['mom_1m'] = me_sorted.groupby('Ticker')['Close'].pct_change()

# Merge VRP into me_sorted by ym
me_sorted['ym_str'] = me_sorted['Date'].dt.strftime('%Y%m')
vrp_merge = vrp[['ym_str','vrp_cw','vrp_bkm','vrp_vkospi','vrp_atm','vkospi','bkm_skew_30d']].copy()
me_sorted = me_sorted.merge(vrp_merge, on='ym_str', how='left')

# ================== Cross-section signals at sig_date ==================
# At each sig_date (ym), need:
#   - S1: skew_252d_lag1 - bkm_skew_30d (VRP-month skew context); rank within universe
#   - S2: VRP-beta (need rolling 36m past data)
#   - S3: vrp × vol_60d_lag1 (high VRP × high vol = negative ranking)
#   - S4: VKOSPI > median × mom_12_1_lag1 (high VKOSPI flip momentum)

# S1: BKM-Skew Diff (PIT t-1)
me_sorted['s1_skew_diff'] = me_sorted['skew_252d_lag1'] - me_sorted['bkm_skew_30d']

# S2: VRP-beta — rolling regression r_it ~ VRP_t over 36m window
# Compute per ticker
print('  S2 VRP-beta rolling regression...')
def rolling_beta(g, window=36):
    out = pd.Series(index=g.index, dtype='float64')
    rets = g['mom_1m'].values
    vrp_v = g['vrp_cw'].values
    for i in range(len(g)):
        if i < window: continue
        y = rets[i-window:i]
        x = vrp_v[i-window:i]
        m_y = np.isnan(y) | np.isnan(x)
        if m_y.sum() > window/2: continue
        y2 = y[~m_y]; x2 = x[~m_y]
        if len(x2) < 10: continue
        cov = np.cov(y2, x2, ddof=1)[0,1]
        v = np.var(x2, ddof=1)
        if v < 1e-10: continue
        out.iloc[i] = cov / v
    return out

# Apply per ticker (computationally heavy but straightforward)
me_sorted = me_sorted.sort_values(['Ticker','Date']).reset_index(drop=True)
me_sorted['s2_vrp_beta'] = me_sorted.groupby('Ticker', group_keys=False).apply(rolling_beta)

# S3: VRP × vol_60d (high VRP regime + high vol stock = penalty)
# Use vrp_bkm (cleanest, no MFIV outlier)
me_sorted['s3_vrp_vol'] = me_sorted['vrp_bkm'] * me_sorted['vol_60d_lag1']

# S4: VKOSPI > median * (-momentum) reversal
# We compute median expanding to avoid look-ahead
# Use month-end VKOSPI (already at sig_date)
# Expanding median up to sig_date
vrp_sorted = vrp.sort_values('sig_date').reset_index(drop=True)
vrp_sorted['vkospi_expand_med'] = vrp_sorted['vkospi'].expanding(min_periods=24).median()
vrp_sorted['vkospi_high'] = (vrp_sorted['vkospi'] > vrp_sorted['vkospi_expand_med']).astype(float)

me_sorted = me_sorted.merge(vrp_sorted[['ym_str','vkospi_high','vkospi_expand_med']], on='ym_str', how='left')
me_sorted['s4_vkospi_mom_reversal'] = (-me_sorted['mom_12_1_lag1']) * me_sorted['vkospi_high']

# ================== Compute IC per signal × sig_date ==================
print('\nComputing cross-section IC per signal × sig_date...')

# Filter to universe
panel = me_sorted[me_sorted['universe']].copy()
print(f'Universe panel: {panel.shape}')

# Restrict to sig_date >= 2010-12 (after VRP signals + vol_60d burn-in)
panel = panel[panel['Date'] >= '2010-12-01'].copy()
panel = panel.dropna(subset=['fwd_1m_ret'])
print(f'After fwd_ret + 2010-12: {panel.shape}')

def compute_ic(g, sig_col):
    # Spearman rank IC (sig_col vs fwd_1m_ret)
    x = g[sig_col].values
    y = g['fwd_1m_ret'].values
    m = np.isnan(x) | np.isnan(y)
    if m.sum() > 0.5 * len(x):
        return np.nan
    if (~m).sum() < 30:
        return np.nan
    return pd.Series(x[~m]).rank().corr(pd.Series(y[~m]).rank())

ic_history = []
for sig_col in ['s1_skew_diff', 's2_vrp_beta', 's3_vrp_vol', 's4_vkospi_mom_reversal']:
    ic_per_date = panel.groupby('Date').apply(lambda g: compute_ic(g, sig_col))
    ic_per_date = ic_per_date.dropna()
    ic_history.append(pd.DataFrame({'sig_date': ic_per_date.index, 'signal': sig_col, 'ic': ic_per_date.values}))

ic_df = pd.concat(ic_history, ignore_index=True)
ic_df.to_parquet(f'{OUT}/cs_ic_history.parquet', index=False)

# Summary stats
print('\nIC summary per signal:')
for sig_col in ['s1_skew_diff', 's2_vrp_beta', 's3_vrp_vol', 's4_vkospi_mom_reversal']:
    sub = ic_df[ic_df['signal'] == sig_col]['ic']
    if len(sub) > 0:
        ic_mean = sub.mean()
        ic_std = sub.std()
        ic_ir = ic_mean / ic_std if ic_std > 0 else np.nan
        # Newey-West 4 lag t-stat (HAC)
        from scipy.stats import t as t_dist
        n = len(sub)
        ic_t = ic_mean / (ic_std / math.sqrt(n)) if ic_std > 0 else np.nan
        print(f'  {sig_col}: n={n}, IC mean={ic_mean:.4f}, std={ic_std:.4f}, ICIR={ic_ir:.4f}, t={ic_t:.3f}')

# ================== Predictor autocor diagnosis ==================
# At sig_date level — autocor of each signal's average value over time (not per-ticker)
print('\nPredictor autocor diagnosis (lag-1 autocor of cross-sectional mean signal):')
diagn = {}
for sig_col in ['s1_skew_diff', 's2_vrp_beta', 's3_vrp_vol', 's4_vkospi_mom_reversal']:
    daily_mean = panel.groupby('Date')[sig_col].mean()
    autocor1 = daily_mean.autocorr(lag=1)
    autocor3 = daily_mean.autocorr(lag=3)
    diagn[sig_col] = {'autocor_lag1': float(autocor1) if not np.isnan(autocor1) else None,
                      'autocor_lag3': float(autocor3) if not np.isnan(autocor3) else None,
                      'n_dates': int(len(daily_mean))}
    print(f'  {sig_col}: lag-1 autocor={autocor1:.4f}, lag-3={autocor3:.4f}, n_dates={len(daily_mean)}')

with open(f'{OUT}/predictor_autocor_diagnosis.json', 'w') as f:
    json.dump(diagn, f, indent=2)

# Save panel snapshot
panel_save = panel[['Date','Ticker','Sector','Sector_Lv2','universe','fwd_1m_ret',
                     's1_skew_diff','s2_vrp_beta','s3_vrp_vol','s4_vkospi_mom_reversal',
                     'vol_60d_lag1','mom_12_1_lag1','skew_252d_lag1',
                     'vrp_cw','vrp_bkm','vrp_vkospi','vrp_atm','vkospi','bkm_skew_30d']].copy()
panel_save.to_parquet(f'{OUT}/cs_panel_monthly.parquet', index=False)
print(f'\nSaved cs_panel_monthly.parquet: {panel_save.shape}')

print('\n=== Summary ===')
print(f'4 signals × {len(ic_df["sig_date"].unique())} sig_dates × ~{panel_save.groupby("Date").size().median():.0f} cross-section names')
print(f'Universe: KOSPI200 ∪ KOSDAQ150 (t-1 K200/KQ150) + 20d avg TV ≥ 5e7 KRW')
