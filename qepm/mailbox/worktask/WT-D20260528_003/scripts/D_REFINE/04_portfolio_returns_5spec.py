#!/usr/bin/env python
"""
WT-D20260528_003 Track 2 D REFINE — Step 4: Portfolio Returns + 5-spec Robustness

Goals:
  1. Compute portfolio monthly returns using weights_schedule.parquet
  2. CAPM α + Carhart 4-F + FF5 + Q5 + FF6 multi-factor regression
  3. Realized Sharpe + DSR (with proper portfolio SR)
  4. AX-001 v2 hard crisis: KOSPI -10% month OR VKOSPI > 30 dates → realized IC

Output:
  stage_artifacts/WT_D20260528_003_D_REFINE/
    - portfolio_returns.parquet
    - five_spec_results.json
    - crisis_test.json
    - dsr_proper.json
"""

import sys
import json
import time
from pathlib import Path
from datetime import datetime

import numpy as np
import pandas as pd
from scipy.stats import spearmanr, t as tdist, norm

PROJ = Path('/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot')
OUT_DIR = PROJ / 'stage_artifacts' / 'WT_D20260528_003_D_REFINE'
SRC_DIR = PROJ / 'stage_artifacts' / 'WT_D20260528_003_overnight_D_ML'  # for label reuse

sys.stdout = open(sys.stdout.fileno(), mode='w', buffering=1, encoding='utf-8', closefd=False)

t0 = time.time()
print(f"[{datetime.now().strftime('%H:%M:%S')}] D REFINE Step 4 — Portfolio Returns + 5-spec", flush=True)

# Load weights + audit predictions (with labels)
weights = pd.read_parquet(OUT_DIR / 'weights_schedule.parquet')
weights['Date'] = pd.to_datetime(weights['Date'])
print(f"  Weights: {weights.shape[0]} rows × {weights.shape[1]} cols")

preds_audit = pd.read_parquet(OUT_DIR / 'alpha_scores_audit.parquet')
preds_audit['Date'] = pd.to_datetime(preds_audit['Date'])
print(f"  Audit preds: {preds_audit.shape[0]} rows")

# Step 1: Portfolio returns per sig_date
# Use realized log_ret_1m_w as next month return per ticker
returns_per_date = []
for sd in weights['Date'].unique():
    w_grp = weights[weights['Date'] == sd]
    r_grp = preds_audit[preds_audit['Date'] == sd][['Ticker', 'log_ret_1m_w']]
    merged = w_grp.merge(r_grp, on='Ticker', how='left')
    merged = merged.dropna(subset=['log_ret_1m_w'])
    if merged.shape[0] == 0:
        continue
    port_ret = (merged['weight'] * merged['log_ret_1m_w']).sum()
    returns_per_date.append({'Date': sd, 'port_ret': float(port_ret), 'n_names': int(merged.shape[0])})

port_df = pd.DataFrame(returns_per_date).sort_values('Date').reset_index(drop=True)
print(f"  Portfolio returns: {len(port_df)} sig_dates")
print(f"  Mean = {port_df['port_ret'].mean():.4%}  Std = {port_df['port_ret'].std():.4%}")

# Subtract benchmark (KOSPI200 monthly log return)
# Use RAWDATA
print(f"  Loading RAWDATA for benchmark...")
rawdata = pd.read_parquet(PROJ / '.cache' / 'rawdata.parquet')
rawdata['Date'] = pd.to_datetime(rawdata['Date'])

# Monthly KOSPI return: take BM_Ret column at month-end
bm_monthly = rawdata.groupby('Date')[['BM_Ret']].first().reset_index()
bm_monthly = bm_monthly[bm_monthly['Date'].isin(port_df['Date'])][['Date', 'BM_Ret']].copy()

# Compute next month BM_Ret cumulative
month_ends = sorted(bm_monthly['Date'].unique())
me_seq = sorted(rawdata['Date'].unique())

# Calculate forward 1M BM log return
# BM_Ret is daily simple return. For log return: sum log(1+r) over period
def bm_next_1m_log_ret(sd):
    next_me = [d for d in me_seq if d > sd][0] if any(d > sd for d in me_seq) else None
    if next_me is None: return None
    in_period = rawdata[(rawdata['Date'] > sd) & (rawdata['Date'] <= next_me)]
    if in_period.shape[0] == 0: return None
    # Per-date BM_Ret (one value), then convert to log return
    bm_daily = in_period.groupby('Date')['BM_Ret'].first()
    log_period = np.log(1 + bm_daily.dropna()).sum()
    return float(log_period)

bm_returns = pd.DataFrame({
    'Date': port_df['Date'],
    'bm_log_ret': [bm_next_1m_log_ret(d) for d in port_df['Date']]
})
port_df = port_df.merge(bm_returns, on='Date', how='left')
port_df['active_ret'] = port_df['port_ret'] - port_df['bm_log_ret']
print(f"  Active return: mean = {port_df['active_ret'].mean():.4%}  std = {port_df['active_ret'].std():.4%}")

# Net of cost (15bps one-way, turnover from summary)
with open(OUT_DIR / 'turnover_summary.json') as f:
    to_summary = json.load(f)
monthly_2way = to_summary['monthly_2way_mean']
cost_per_month = monthly_2way * 0.0015  # 15bps × 2-way = 30bps total monthly cost
port_df['port_ret_net'] = port_df['port_ret'] - cost_per_month
port_df['active_ret_net'] = port_df['port_ret_net'] - port_df['bm_log_ret']

print(f"  Cost per month (15bps × {monthly_2way:.3f} 2-way): {cost_per_month*1e4:.1f}bps")
print(f"  Active net return: mean = {port_df['active_ret_net'].mean():.4%}")

port_df.to_parquet(OUT_DIR / 'portfolio_returns.parquet', index=False)

# Step 2: Sharpe + DSR proper
n = len(port_df)
sr_gross = port_df['port_ret'].mean() / (port_df['port_ret'].std() + 1e-8) * np.sqrt(12)
sr_net = port_df['port_ret_net'].mean() / (port_df['port_ret_net'].std() + 1e-8) * np.sqrt(12)
sr_active = port_df['active_ret'].mean() / (port_df['active_ret'].std() + 1e-8) * np.sqrt(12)
sr_active_net = port_df['active_ret_net'].mean() / (port_df['active_ret_net'].std() + 1e-8) * np.sqrt(12)

print(f"\n  Sharpe (annualized):")
print(f"    Portfolio gross : {sr_gross:.3f}")
print(f"    Portfolio net   : {sr_net:.3f}")
print(f"    Active gross    : {sr_active:.3f}")
print(f"    Active net      : {sr_active_net:.3f}")

# DSR proper using realized portfolio SR
n_trials_eff = 411  # D ML 269 + Phase 3 38 + Optuna 100 + parallel 4
exp_max_sr = np.sqrt(2 * np.log(max(n_trials_eff, 2)))

# Use net portfolio SR for DSR
sr_observed = sr_net
# Higher moments correction (Mertens 2002)
ret_series = port_df['port_ret_net'].values
mean_r = ret_series.mean()
std_r = ret_series.std()
skew_r = ((ret_series - mean_r)**3).mean() / (std_r + 1e-10)**3
kurt_r = ((ret_series - mean_r)**4).mean() / (std_r + 1e-10)**4

# Bailey-Lopez de Prado 2014 DSR formula
sr_monthly = mean_r / (std_r + 1e-8)
sr_se_factor = np.sqrt((1 - skew_r * sr_monthly + (kurt_r - 1) / 4 * sr_monthly**2) / (n - 1))

# DSR = Pr(SR > E[max SR | N trials, null])
dsr_z = (sr_observed - exp_max_sr * (1 - 0.5772 / np.sqrt(2 * np.log(n_trials_eff)))) / max(sr_se_factor * np.sqrt(12), 1e-8)
dsr_proper = float(norm.cdf(dsr_z))

print(f"\n  DSR Proper (realized portfolio SR + Mertens correction):")
print(f"    n_trials_eff: {n_trials_eff}  Expected max SR: {exp_max_sr:.3f}")
print(f"    Skewness: {skew_r:.3f}  Kurtosis: {kurt_r:.3f}")
print(f"    DSR z: {dsr_z:.3f}  DSR: {dsr_proper:.4f}")
print(f"    Threshold 0.5: {'PASS' if dsr_proper >= 0.5 else 'FAIL'}")

# Step 3: 5-spec robustness (CAPM + Carhart 4F + FF5 + Q5 + simplified version)
# For KR market: we'll use KOSPI (BM_Ret), Size, Value, Momentum proxies
# Build factor returns from RAWDATA proxy

# Simplified factor returns:
#   MKT = BM_Ret
#   SMB = Size top quintile cross-section return diff (placeholder using rawdata)
#   HML = BM (book-to-market) — not directly in RAWDATA, will use V01_BM if available
#   WML = M01_Mom_12_1 quintile diff
#   For simplification, run CAPM-only first; Carhart/FF5/Q5 use Korean proxies

# Build monthly factor returns from existing factor DB (use Factor DB month-end snapshots)
# For brevity, run a single CAPM regression here and note that full 5-spec requires factor DB integration

# Simple OLS: active_ret_net ~ MKT (KOSPI return)
# Using NumPy lstsq for simplicity
mask = ~port_df['active_ret_net'].isna() & ~port_df['bm_log_ret'].isna()
y = port_df.loc[mask, 'active_ret_net'].values
x = port_df.loc[mask, 'bm_log_ret'].values
n_obs = len(y)

# CAPM: r_i - r_f = α + β * (r_m - r_f)
# Approximation: r_f = 0 (Korean short rate small)
X = np.column_stack([np.ones(n_obs), x])
beta_hat, _, _, _ = np.linalg.lstsq(X, y, rcond=None)
y_pred = X @ beta_hat
resid = y - y_pred

# Newey-West HAC SE (Andrews 1991)
def newey_west_se(X, resid, lag=3):
    n_obs = len(resid)
    XtX_inv = np.linalg.inv(X.T @ X)
    S = (resid[:, None] * X).T @ (resid[:, None] * X)
    for k in range(1, lag + 1):
        w = 1 - k / (lag + 1)
        Gk = (resid[k:, None] * X[k:]).T @ (resid[:-k, None] * X[:-k])
        S += w * (Gk + Gk.T)
    var = XtX_inv @ S @ XtX_inv
    se = np.sqrt(np.diag(var))
    return se

se = newey_west_se(X, resid)
alpha_t = beta_hat[0] / se[0]
beta_t = beta_hat[1] / se[1]

# Annualize alpha
alpha_monthly = beta_hat[0]
alpha_annual = alpha_monthly * 12

# Information ratio
te_monthly = port_df.loc[mask, 'active_ret_net'].std()
ir = port_df.loc[mask, 'active_ret_net'].mean() / (te_monthly + 1e-8) * np.sqrt(12)

print(f"\n  5-spec robustness (CAPM only for now, others require KR factor DB integration):")
print(f"    CAPM α = {alpha_monthly:.4%}/m ({alpha_annual:.2%}/yr)  t_NW = {alpha_t:.3f}")
print(f"    CAPM β = {beta_hat[1]:.3f}  t_NW = {beta_t:.3f}")
print(f"    IR = {ir:.3f}  TE = {te_monthly:.4%}/m")

five_spec_results = {
    'capm': {
        'alpha_monthly': float(alpha_monthly),
        'alpha_annual': float(alpha_annual),
        'alpha_t_nw': float(alpha_t),
        'beta': float(beta_hat[1]),
        'beta_t_nw': float(beta_t),
        'information_ratio': float(ir),
        'tracking_error_monthly': float(te_monthly),
        'n_obs': int(n_obs),
    },
    'carhart_4f': {'status': 'KR_factor_DB_integration_required'},
    'ff5': {'status': 'KR_factor_DB_integration_required'},
    'q5': {'status': 'KR_factor_DB_integration_required'},
    'note': 'Full 5-spec requires KR equivalent SMB/HML/RMW/CMA/QMJ factors from Korean factor DB; CAPM-only here for discovery stage.',
}
with open(OUT_DIR / 'five_spec_results.json', 'w') as f:
    json.dump(five_spec_results, f, indent=2)

# Step 4: AX-001 v2 hard crisis test
# Use BM_Ret monthly drawdown to define crisis
# KR market: -10% / 1M is rare; use multi-tier: -5%, -7.5%, -10%
crisis_dates_5 = port_df[port_df['bm_log_ret'] < -0.05]['Date'].tolist()
crisis_dates_75 = port_df[port_df['bm_log_ret'] < -0.075]['Date'].tolist()
crisis_dates_10 = port_df[port_df['bm_log_ret'] < -0.10]['Date'].tolist()
# Use the -5% as primary hard test (more samples)
crisis_dates = crisis_dates_5
print(f"\n  AX-001 v2 hard crisis dates:")
print(f"    KOSPI < -5%:  {len(crisis_dates_5)}")
print(f"    KOSPI < -7.5%: {len(crisis_dates_75)}")
print(f"    KOSPI < -10%: {len(crisis_dates_10)}")
print(f"  Using -5% threshold as primary hard test")

if len(crisis_dates) >= 3:
    crisis_active = port_df[port_df['Date'].isin(crisis_dates)]['active_ret'].mean()
    crisis_active_net = port_df[port_df['Date'].isin(crisis_dates)]['active_ret_net'].mean()
    normal_active = port_df[~port_df['Date'].isin(crisis_dates)]['active_ret'].mean()
    crisis_alpha = crisis_active - 0  # vs zero benchmark
    print(f"    Crisis active alpha (gross): {crisis_active:.4%}")
    print(f"    Crisis active alpha (net):   {crisis_active_net:.4%}")
    print(f"    Normal active alpha (gross): {normal_active:.4%}")

    crisis_summary = {
        'threshold_used': -0.05,
        'n_crisis_dates_neg5pct': len(crisis_dates_5),
        'n_crisis_dates_neg7_5pct': len(crisis_dates_75),
        'n_crisis_dates_neg10pct': len(crisis_dates_10),
        'crisis_active_alpha_gross': float(crisis_active),
        'crisis_active_alpha_net': float(crisis_active_net),
        'normal_active_alpha_gross': float(normal_active),
        'crisis_alpha_positive': bool(crisis_active > 0),
        'crisis_dates_sample': [str(d.date()) for d in crisis_dates[:10]],
    }
else:
    print(f"    Insufficient crisis dates for AX-001 v2 hard test")
    crisis_summary = {
        'n_crisis_dates': len(crisis_dates),
        'status': 'insufficient_dates',
    }

with open(OUT_DIR / 'crisis_test.json', 'w') as f:
    json.dump(crisis_summary, f, indent=2)

# Save DSR proper
with open(OUT_DIR / 'dsr_proper.json', 'w') as f:
    json.dump({
        'sr_observed_net': float(sr_observed),
        'sr_observed_gross': float(sr_gross),
        'sr_active_net': float(sr_active_net),
        'n_trials_eff': n_trials_eff,
        'expected_max_sr_under_null': float(exp_max_sr),
        'skewness': float(skew_r),
        'kurtosis': float(kurt_r),
        'dsr_z': float(dsr_z),
        'dsr_proper': dsr_proper,
        'threshold_0_5': bool(dsr_proper >= 0.5),
    }, f, indent=2)

print(f"\n=== Step 4 COMPLETE — elapsed {(time.time()-t0):.1f} sec ===")
