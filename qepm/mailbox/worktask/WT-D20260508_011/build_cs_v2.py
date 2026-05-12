#!/usr/bin/env python
"""
WT-D20260508_011 — VRP cross-section signals v2

Tries 8 specifications + composite. Composite avoidance principle (WT_004/006 lesson).
Single best selection.
"""

import os, json, math, warnings
import numpy as np
import pandas as pd
from datetime import datetime
warnings.filterwarnings('ignore')

ROOT = '/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot'
OUT = f'{ROOT}/stage_artifacts/WT_D20260508_011'

# Load panel snapshot
panel = pd.read_parquet(f'{OUT}/cs_panel_monthly.parquet')
panel['Date'] = pd.to_datetime(panel['Date'])
print(f'panel: {panel.shape}')

vrp = pd.read_parquet(f'{OUT}/vrp_signals_monthly.parquet')
vrp['sig_date'] = pd.to_datetime(vrp['sig_date'])
vrp['ym_str'] = vrp['sig_date'].dt.strftime('%Y%m')

# Compute VRP innovation (Δ vrp 12m sum) — same as WT_001 vrp_innov_z definition
vrp = vrp.sort_values('sig_date').reset_index(drop=True)
for c in ['vrp_cw','vrp_bkm','vrp_vkospi','vrp_atm']:
    vrp[f'{c}_12m_sum'] = vrp[c].rolling(12, min_periods=6).sum()
    vrp[f'{c}_innov'] = vrp[f'{c}_12m_sum'].diff(1)
    # 48m expanding z-score (PIT)
    rolling_mean = vrp[f'{c}_innov'].expanding(min_periods=24).mean()
    rolling_std = vrp[f'{c}_innov'].expanding(min_periods=24).std()
    vrp[f'{c}_innov_z'] = (vrp[f'{c}_innov'] - rolling_mean) / rolling_std

# Re-merge
panel = panel.drop(columns=[c for c in panel.columns if c.startswith('vrp_') or c == 'vkospi' or c == 'bkm_skew_30d'], errors='ignore')
vrp_keep = ['ym_str','vrp_cw','vrp_bkm','vrp_vkospi','vrp_atm','vkospi','bkm_skew_30d',
            'vrp_cw_innov_z','vrp_bkm_innov_z','vrp_vkospi_innov_z','vrp_atm_innov_z']
panel['ym_str'] = panel['Date'].dt.strftime('%Y%m')
panel = panel.merge(vrp[vrp_keep], on='ym_str', how='left')

# Add 252d beta to KOSPI200
# Compute it from rawdata
print('Computing 252d market beta...')
raw = pd.read_parquet(f'{ROOT}/.cache/rawdata.parquet')
raw['Date'] = pd.to_datetime(raw['Date'])
raw = raw.sort_values(['Ticker','Date']).reset_index(drop=True)
raw['log_ret'] = np.log1p(raw['Ret'].fillna(0))

# Market: BM_Ret unique per Date
mkt = raw[['Date','BM_Ret']].drop_duplicates().sort_values('Date').reset_index(drop=True)
mkt['log_mkt'] = np.log1p(mkt['BM_Ret'].fillna(0))

# Merge market into raw
raw_m = raw.merge(mkt[['Date','log_mkt']], on='Date', how='left')

# 252d rolling beta (per ticker)
def rolling_beta_market(g, window=252, minp=180):
    s_y = g['log_ret'].values
    s_x = g['log_mkt'].values
    n = len(s_y)
    out = np.full(n, np.nan)
    for i in range(window, n):
        y = s_y[i-window:i]
        x = s_x[i-window:i]
        m = np.isnan(y) | np.isnan(x)
        if (~m).sum() < minp: continue
        y2 = y[~m]; x2 = x[~m]
        v = np.var(x2, ddof=1)
        if v < 1e-12: continue
        out[i] = np.cov(y2, x2, ddof=1)[0,1] / v
    return pd.Series(out, index=g.index)

print('  rolling beta...')
raw_m['beta_252d'] = raw_m.groupby('Ticker', group_keys=False).apply(rolling_beta_market)
raw_m['beta_252d_lag1'] = raw_m.groupby('Ticker')['beta_252d'].shift(1)

# Daily beta is huge; reduce to month-end via merge
raw_m['ym'] = raw_m['Date'].dt.to_period('M')
beta_me = raw_m.groupby(['Ticker','ym'])['beta_252d_lag1'].last().reset_index()
beta_me['ym_str'] = beta_me['ym'].astype(str).str.replace('-','')
panel = panel.merge(beta_me[['Ticker','ym_str','beta_252d_lag1']], on=['Ticker','ym_str'], how='left')

print(f'After beta merge: {panel.shape}, beta_252d_lag1 non-null: {panel["beta_252d_lag1"].notna().sum()}')

# Restrict to fwd_ret + universe
panel = panel[(panel['universe']) & panel['fwd_1m_ret'].notna() & (panel['Date'] >= '2010-12-01')].copy()
print(f'Filtered panel: {panel.shape}')

# ================== Signal definitions ==================
# Based on theory:
# H1: high VRP × high vol = penalty (s3 baseline)
# H2: VRP innovation cross-section (autocor cleaner)
# H3: bkm_skew × low-beta (skew aversion premium)
# H4: VRP × beta (high VRP regime, market-sensitive stocks penalty)
# H5: VKOSPI innovation × vol penalty (volatility-of-volatility risk)

panel['s1_skew_diff'] = panel['skew_252d_lag1'] - panel['bkm_skew_30d']  # baseline
panel['s2_vrp_innov_z_x_vol'] = panel['vrp_bkm_innov_z'] * panel['vol_60d_lag1']  # cleaner autocor
panel['s3_vrp_vol'] = panel['vrp_bkm'] * panel['vol_60d_lag1']
panel['s4_vrp_beta'] = panel['vrp_bkm'] * panel['beta_252d_lag1']
panel['s5_skew_x_lowbeta'] = panel['bkm_skew_30d'] * (-panel['beta_252d_lag1'])  # negative bkm × low beta = neg sign of low-beta when neg skew
panel['s6_vkospi_innov_x_vol'] = (panel['vkospi'] - panel.groupby('Date')['vkospi'].transform('first').rolling(12).mean()) * panel['vol_60d_lag1']
# vkospi 단기 변화 × vol → 변동성 충격 시 high vol 종목 추가 penalty
panel['s7_vrp_atm_innov_z'] = panel['vrp_atm_innov_z']
panel['s8_bkm_skew_only'] = panel['bkm_skew_30d']  # cross-section uniform; tests only TS direction (limited)
panel['s9_vrp_x_neg_mom'] = panel['vrp_bkm'] * (-panel['mom_12_1_lag1'])  # high VRP regime + low momentum (defensive)

signals = ['s1_skew_diff','s2_vrp_innov_z_x_vol','s3_vrp_vol','s4_vrp_beta','s5_skew_x_lowbeta',
           's6_vkospi_innov_x_vol','s7_vrp_atm_innov_z','s9_vrp_x_neg_mom']
# s8 cross-section uniform 제외

def compute_ic(g, sig_col):
    x = g[sig_col].values; y = g['fwd_1m_ret'].values
    m = np.isnan(x) | np.isnan(y)
    if (~m).sum() < 30: return np.nan
    return pd.Series(x[~m]).rank().corr(pd.Series(y[~m]).rank())

print('\n--- IC per signal ---')
ic_results = {}
for s in signals:
    ic_per_date = panel.groupby('Date').apply(lambda g: compute_ic(g, s)).dropna()
    if len(ic_per_date) < 50:
        print(f'  {s}: <50 dates, skip')
        continue
    ic_mean = ic_per_date.mean()
    ic_std = ic_per_date.std()
    icir = ic_mean / ic_std
    n = len(ic_per_date)
    t_simple = ic_mean / (ic_std / math.sqrt(n))

    # Newey-West HAC t-stat (4 lag)
    ic_arr = ic_per_date.values
    L = 4
    g0 = np.var(ic_arr, ddof=1)
    nw_var = g0
    for lag in range(1, L+1):
        w = 1 - lag/(L+1)
        cov_l = np.mean((ic_arr[lag:] - ic_mean) * (ic_arr[:-lag] - ic_mean))
        nw_var += 2 * w * cov_l
    nw_se = math.sqrt(max(nw_var, 1e-10) / n)
    t_nw = ic_mean / nw_se

    # Predictor autocor (cross-sectional mean per Date)
    ts_mean = panel.groupby('Date')[s].mean()
    ac = ts_mean.autocorr(lag=1)

    ic_results[s] = {'n': n, 'ic_mean': float(ic_mean), 'ic_std': float(ic_std),
                     'icir': float(icir), 't_simple': float(t_simple), 't_nw': float(t_nw),
                     'autocor_lag1': float(ac) if not np.isnan(ac) else None}
    print(f'  {s}: n={n}, IC={ic_mean:+.4f}, ICIR={icir:+.3f}, t_NW={t_nw:+.2f}, ac1={ac:+.3f}')

# ================== Subperiod stability ==================
print('\n--- Subperiod stability (sign of IC mean per period) ---')
periods = [('2010-12','2014-12'),('2015-01','2019-12'),('2020-01','2026-05')]
for s, res in ic_results.items():
    ic_per_date = panel.groupby('Date').apply(lambda g: compute_ic(g, s)).dropna()
    sign_main = np.sign(res['ic_mean'])
    consistent = 0
    sub_ics = []
    for start, end in periods:
        sub = ic_per_date[(ic_per_date.index >= start) & (ic_per_date.index <= end)]
        if len(sub) > 10:
            sub_mean = sub.mean()
            sub_ics.append(f'{start[:4]}-{end[:4]}={sub_mean:+.4f}')
            if np.sign(sub_mean) == sign_main:
                consistent += 1
    sub_stab = consistent / 3
    ic_results[s]['sub_stab'] = sub_stab
    ic_results[s]['sub_ics'] = sub_ics
    print(f'  {s}: stab={sub_stab:.2f} ({" / ".join(sub_ics)})')

# Save IC results
with open(f'{OUT}/cs_ic_v2.json', 'w') as f:
    json.dump(ic_results, f, indent=2)

# Save panel
out_panel = panel[['Date','Ticker','Sector','fwd_1m_ret','vol_60d_lag1','mom_12_1_lag1',
                    'skew_252d_lag1','beta_252d_lag1','vrp_bkm','vrp_atm','vkospi','bkm_skew_30d',
                    'vrp_bkm_innov_z','vrp_atm_innov_z'] + signals].copy()
out_panel.to_parquet(f'{OUT}/cs_panel_v2.parquet', index=False)
print(f'\nSaved cs_panel_v2.parquet: {out_panel.shape}')
