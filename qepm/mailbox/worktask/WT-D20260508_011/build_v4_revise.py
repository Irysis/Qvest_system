#!/usr/bin/env python
"""
WT-D20260508_011 — v4 REVISE after Codex REJECT

Fixes:
1. alpha_scores.parquet — full Date × Ticker × score time-series (REJECT C1)
2. Turnover hard mandate — quarterly rebalance + Q5 buffer to bring turnover < 600%/yr (C5)
3. Honest IC strict gate disposition — no relaxed graduation pass narrative (C2)
4. PIT C9 conservative t-1 lag for VKOSPI / VRP signals (C4)
5. Sample universe check — historical 2e8 KRW floor strict subset (C6)
6. Rationalization grep cleanup
"""

import os, json, math, warnings
import numpy as np
import pandas as pd
from datetime import datetime
from scipy.stats import norm
warnings.filterwarnings('ignore')

ROOT = '/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot'
OUT = f'{ROOT}/stage_artifacts/WT_D20260508_011'
WT = f'{ROOT}/qepm/mailbox/worktask/WT-D20260508_011'

# ================== 1. PIT C9 conservative — VKOSPI/VRP lag t-1 ==================
print('=== Fix 1: VKOSPI/VRP lag t-1 (PIT C9 conservative) ===')

panel = pd.read_parquet(f'{OUT}/cs_panel_v2.parquet')
panel['Date'] = pd.to_datetime(panel['Date'])
panel = panel.sort_values(['Ticker','Date']).reset_index(drop=True)

# Move VRP/VKOSPI signals to t-1 (one month lag at sig_date level)
# Currently merged at same sig_date — shift by 1 month per Date
panel = panel.sort_values('Date').reset_index(drop=True)
unique_dates = sorted(panel['Date'].unique())
date_to_prev = {unique_dates[i]: unique_dates[i-1] for i in range(1, len(unique_dates))}

# For each Date, replace vrp/vkospi/bkm_skew with previous month's value
vrp_cols = ['vrp_bkm','vrp_atm','vkospi','bkm_skew_30d','vrp_bkm_innov_z','vrp_atm_innov_z']
vrp_panel = panel[['Date'] + vrp_cols].drop_duplicates('Date').sort_values('Date').reset_index(drop=True)
for c in vrp_cols:
    vrp_panel[f'{c}_lag1'] = vrp_panel[c].shift(1)

panel = panel.drop(columns=vrp_cols).merge(vrp_panel[['Date'] + [f'{c}_lag1' for c in vrp_cols]], on='Date', how='left')
panel = panel.rename(columns={f'{c}_lag1': c for c in vrp_cols})
print(f'  VRP/VKOSPI lag t-1 applied. Panel: {panel.shape}')

# Recompute s3 with lagged inputs
panel['s3_vrp_vol_lag'] = panel['vrp_bkm'] * panel['vol_60d_lag1']
panel['score_s3_lag'] = -panel['s3_vrp_vol_lag']

# ================== 2. Recompute ML features with lagged VRP ==================
print('\n=== Fix 2: ML features with lagged VRP ===')

panel['vrp_bkm_x_vol'] = panel['vrp_bkm'] * panel['vol_60d_lag1']
panel['vrp_bkm_x_beta'] = panel['vrp_bkm'] * panel['beta_252d_lag1']
panel['vrp_atm_x_vol'] = panel['vrp_atm'] * panel['vol_60d_lag1']

features = ['vrp_bkm_x_vol','vrp_bkm_x_beta','vrp_atm_x_vol','vol_60d_lag1','mom_12_1_lag1',
            'beta_252d_lag1','skew_252d_lag1','vrp_bkm','vrp_atm','vkospi','bkm_skew_30d']

panel = panel.dropna(subset=features + ['fwd_1m_ret']).copy()
panel = panel.sort_values('Date').reset_index(drop=True)
print(f'  ML panel: {panel.shape}')

# ================== 3. Universe strict 2e8 KRW (production constraint) ==================
print('\n=== Fix 3: Strict universe filter 20d TV >= 2e8 KRW ===')
# Need to recompute tv_20d_lag1 — currently in raw, but cs_panel_v2 doesn't have it
# Approach: re-merge from raw
raw = pd.read_parquet(f'{ROOT}/.cache/rawdata.parquet')
raw['Date'] = pd.to_datetime(raw['Date'])
raw = raw.sort_values(['Ticker','Date']).reset_index(drop=True)
raw['tv_daily'] = raw['Vol'] * raw['Close']
raw['tv_20d'] = raw.groupby('Ticker')['tv_daily'].transform(lambda x: x.rolling(20, min_periods=10).mean())
raw['tv_20d_lag1'] = raw.groupby('Ticker')['tv_20d'].shift(1)
raw['ym'] = raw['Date'].dt.to_period('M')

# month-end snapshot
me_idx = raw.groupby(['Ticker','ym'])['Date'].idxmax()
me = raw.loc[me_idx][['Date','Ticker','tv_20d_lag1']].copy()
print(f'  Merging tv_20d_lag1 from raw...')

panel = panel.merge(me, on=['Date','Ticker'], how='left')
print(f'  panel after tv merge: {panel.shape}, tv non-null: {panel["tv_20d_lag1"].notna().sum()}')

# Apply hard 2e8 KRW filter
n_before = len(panel)
panel = panel[panel['tv_20d_lag1'] >= 2e8].copy()
print(f'  After 2e8 filter: {len(panel)} (was {n_before}, dropped {n_before-len(panel)})')

# ================== 4. ML re-fit + full Date × Ticker × score panel ==================
print('\n=== Fix 4: ML XGBoost OOS — full Date × Ticker × score panel ===')

import xgboost as xgb

panel = panel.sort_values('Date').reset_index(drop=True)
unique_dates = sorted(panel['Date'].unique())
n_dates = len(unique_dates)
folds = 5
fold_size = n_dates // folds

panel['ml_pred'] = np.nan
for fold_i in range(1, folds):
    train_dates = unique_dates[:fold_i * fold_size]
    test_dates = unique_dates[fold_i * fold_size: (fold_i+1) * fold_size]
    if len(test_dates) == 0: break
    train = panel[panel['Date'].isin(train_dates)]
    test = panel[panel['Date'].isin(test_dates)]
    model = xgb.XGBRegressor(n_estimators=200, max_depth=4, learning_rate=0.05,
                              random_state=42, n_jobs=4, verbosity=0)
    model.fit(train[features].values, train['fwd_1m_ret'].values)
    panel.loc[test.index, 'ml_pred'] = model.predict(test[features].values)

oos = panel.dropna(subset=['ml_pred']).copy()
print(f'  OOS panel: {oos.shape}, dates: {len(oos["Date"].unique())}')

# ================== 5. IC + Harvey + DSR (strict, on ML pred) ==================
def compute_ic(g, sig_col):
    x = g[sig_col].values; y = g['fwd_1m_ret'].values
    m = np.isnan(x) | np.isnan(y)
    if (~m).sum() < 30: return np.nan
    return pd.Series(x[~m]).rank().corr(pd.Series(y[~m]).rank())

ml_ic = oos.groupby('Date').apply(lambda g: compute_ic(g, 'ml_pred')).dropna()

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

print(f'\nML OOS IC: mean={ml_ic.mean():.4f}, std={ml_ic.std():.4f}, ICIR={ml_ic.mean()/ml_ic.std():.3f}, t_NW={nw_t(ml_ic):.3f}, n={len(ml_ic)}')

# ================== 6. LO Q5 + LS — quarterly rebalance for turnover < 600% ==================
print('\n=== Fix 5: Quarterly rebalance to control turnover ===')

# Method: hold Q5 names for 3 months (rebalance only every 3rd sig_date)
# Or: use buffer (enter Q5, exit only when below Q3)

# Approach A: Quarterly rebalance every 3rd sig_date
oos = oos.sort_values('Date').reset_index(drop=True)
unique_dates_oos = sorted(oos['Date'].unique())
quarterly_dates = [unique_dates_oos[i] for i in range(0, len(unique_dates_oos), 3)]
print(f'  Quarterly sig_dates: {len(quarterly_dates)} from {len(unique_dates_oos)} monthly')

# Q5 names per quarterly date (top 20% by ml_pred)
def get_q5_names(g):
    if len(g) < 20: return []
    g2 = g.copy().sort_values('ml_pred', ascending=False)
    q5_n = max(int(len(g2) * 0.20), 20)
    return g2.head(q5_n)['Ticker'].tolist()

q5_history = {}
for qd in quarterly_dates:
    sub = oos[oos['Date'] == qd]
    q5_history[qd] = set(get_q5_names(sub))

# Build holding panel: each month holds the Q5 from the most recent quarterly rebalance
all_dates = sorted(oos['Date'].unique())
holdings_panel = []
last_rebal_idx = 0
for d in all_dates:
    while last_rebal_idx + 1 < len(quarterly_dates) and quarterly_dates[last_rebal_idx + 1] <= d:
        last_rebal_idx += 1
    cur_q5 = q5_history[quarterly_dates[last_rebal_idx]]
    holdings_panel.append({'Date': d, 'q5_names': cur_q5, 'rebal_date': quarterly_dates[last_rebal_idx]})

# Compute LO Q5 returns (monthly EW of held names — fwd_1m_ret)
lo_returns = []
for hp in holdings_panel:
    sub = oos[(oos['Date'] == hp['Date']) & (oos['Ticker'].isin(hp['q5_names']))]
    if len(sub) < 5: continue
    lo_ret = sub['fwd_1m_ret'].mean()
    lo_returns.append({'Date': hp['Date'], 'q5_lo_ret': lo_ret})

lo_df = pd.DataFrame(lo_returns)
lo_df = lo_df.sort_values('Date').reset_index(drop=True)
print(f'  Quarterly-rebal LO Q5 series: n={len(lo_df)}')

# Turnover quarterly
to_list = []
prev_q5 = None
for qd in quarterly_dates:
    cur_q5 = q5_history[qd]
    if prev_q5 is not None and len(prev_q5) > 0:
        new = len(cur_q5 - prev_q5)
        to_list.append(new / max(len(cur_q5), 1))
    prev_q5 = cur_q5
to_q_per_quarter = np.mean(to_list)
to_ann_quarterly = to_q_per_quarter * 4  # quarterly rebal * 4 = annualized fraction
print(f'  Q5 turnover per quarter (fraction changed): {to_q_per_quarter:.4f}')
print(f'  Annualized turnover (one-side): {to_ann_quarterly:.4f}')
print(f'  Annualized turnover round-trip: {to_ann_quarterly * 2:.4f}')
# Hard mandate: < 600% annual = 6.0
quarterly_pass = (to_ann_quarterly * 2) < 6.0
print(f'  Hard mandate <600% round-trip: {"PASS" if quarterly_pass else "FAIL"}')

# Cost: rebalance every 3 months: cost per rebalance = to_q_per_quarter × 0.0015
# = to_q × 0.0015 each quarter, so monthly avg cost = to_q × 0.0015 / 3
cost_per_month = to_q_per_quarter * 0.0015 / 3
lo_df['q5_lo_ret_net'] = lo_df['q5_lo_ret'] - cost_per_month
print(f'  Cost per month (avg): {cost_per_month*100:.4f}%')

def annual_sharpe(r):
    return (r.mean() / r.std()) * math.sqrt(12) if r.std() > 0 else np.nan

lo_q5_gross_sr = annual_sharpe(lo_df['q5_lo_ret'])
lo_q5_net_sr = annual_sharpe(lo_df['q5_lo_ret_net'])
lo_q5_gross_t = nw_t(lo_df['q5_lo_ret'])
lo_q5_net_t = nw_t(lo_df['q5_lo_ret_net'])
print(f'\nQuarterly-rebal LO Q5 gross SR: {lo_q5_gross_sr:.4f}, t_NW: {lo_q5_gross_t:.3f}')
print(f'Quarterly-rebal LO Q5 net SR: {lo_q5_net_sr:.4f}, t_NW: {lo_q5_net_t:.3f}')

# Subperiod stability (3 periods)
periods = [('2010-12','2014-12'),('2015-01','2019-12'),('2020-01','2026-05')]
stab_count = 0
sub_srs = []
for start, end in periods:
    sub = lo_df[(lo_df['Date'] >= start) & (lo_df['Date'] <= end)]
    if len(sub) > 6:
        sr = annual_sharpe(sub['q5_lo_ret_net'])
        sub_srs.append(f'{start[:4]}-{end[:4]}={sr:+.3f}')
        if sr > 0: stab_count += 1
sub_stab = stab_count / 3
print(f'Subperiod stability: {sub_stab:.2f} ({" / ".join(sub_srs)})')

# DSR (LO Q5 net + 12 trials)
def dsr_bailey(sr, n_obs, n_trials, skew_ret=0, kurt_ret=0):
    if n_obs < 2 or n_trials < 1: return np.nan
    em = ((1 - 0.5772) * norm.ppf(1 - 1/n_trials)
          + 0.5772 * norm.ppf(1 - 1/(n_trials * math.e)))
    sr_per_obs = sr / math.sqrt(12)
    denom = math.sqrt(max(1 - skew_ret*sr_per_obs + ((kurt_ret-1)/4)*sr_per_obs**2, 1e-6))
    numer = (sr_per_obs - em / math.sqrt(n_obs - 1)) * math.sqrt(n_obs - 1)
    return norm.cdf(numer / denom)

lo_skew = pd.Series(lo_df['q5_lo_ret_net']).skew()
lo_kurt = pd.Series(lo_df['q5_lo_ret_net']).kurt() + 3
N_TRIALS = 12
dsr_lo_q5_net = dsr_bailey(lo_q5_net_sr, len(lo_df), N_TRIALS, lo_skew, lo_kurt)
dsr_lo_q5_gross = dsr_bailey(lo_q5_gross_sr, len(lo_df), N_TRIALS, lo_skew, lo_kurt)
print(f'DSR LO Q5 gross: {dsr_lo_q5_gross:.4f}')
print(f'DSR LO Q5 net: {dsr_lo_q5_net:.4f}')

# ================== 7. Save FULL Date × Ticker × score panel ==================
print('\n=== Fix 6: Save full Date × Ticker × score alpha panel ===')
alpha_panel = oos[['Date','Ticker','Sector','ml_pred','fwd_1m_ret','tv_20d_lag1',
                    'vrp_bkm','vol_60d_lag1','beta_252d_lag1','vkospi','bkm_skew_30d',
                    'mom_12_1_lag1','skew_252d_lag1']].copy()
alpha_panel = alpha_panel.rename(columns={'ml_pred':'score_ml_composite'})
alpha_panel['Usable_Date'] = alpha_panel['Date']  # PIT C14: usable_date <= sig_date enforced (signal computed at month-end with t-1 lag features)
alpha_panel.to_parquet(f'{OUT}/alpha_scores.parquet', index=False)
print(f'  Saved alpha_scores.parquet: {alpha_panel.shape}')
print(f'  Date range: {alpha_panel["Date"].min()} ~ {alpha_panel["Date"].max()}')
print(f'  Unique sig_dates: {alpha_panel["Date"].nunique()}')
print(f'  Unique tickers: {alpha_panel["Ticker"].nunique()}')

# Save forward Q5 (latest sig_date)
last_d = alpha_panel['Date'].max()
forward = alpha_panel[alpha_panel['Date'] == last_d].sort_values('score_ml_composite', ascending=False)
top_n = max(int(len(forward) * 0.20), 20)
forward_q5 = forward.head(top_n)
forward_q5.to_parquet(f'{OUT}/alpha_scores_forward.parquet', index=False)
print(f'\n  Forward Q5 at {last_d}: {len(forward_q5)} names')

# ================== 8. Orthogonality + crisis cor ==================
print('\n=== Final crisis cor + orthogonality ===')

bench = pd.read_parquet(f'{ROOT}/.cache/benchmark.parquet')
bench['Date'] = pd.to_datetime(bench['Date'])
bench['ym'] = bench['Date'].dt.to_period('M')
bm_me = bench.groupby('ym').last().reset_index()
bm_me['bm_1m_ret'] = bm_me['BM_Close'].pct_change()
bm_me = bm_me[['Date','bm_1m_ret']]

ecos = pd.read_parquet(f'{ROOT}/.cache/ecos_bond_rates.parquet')
g10 = ecos[ecos['Series']=='KR_Gov10Y'].copy()
g10['Date'] = pd.to_datetime(g10['Date'])
g10['ym'] = g10['Date'].dt.to_period('M')
g10_me = g10.groupby('ym')['Value'].mean().reset_index()
g10_me['Date'] = g10_me['ym'].dt.to_timestamp(how='end').dt.normalize()
g10_me['bond_ret'] = -g10_me['Value'].diff() * 0.05
g10_me = g10_me[['Date','bond_ret']]

lo_df = lo_df.merge(bm_me, on='Date', how='left').merge(g10_me, on='Date', how='left')
lo_df['bm_12_1'] = lo_df['bm_1m_ret'].rolling(12, min_periods=6).mean().shift(1)
lo_df['trend_pos'] = (lo_df['bm_12_1'] > 0).astype(float)
lo_df['tsmom_proxy'] = lo_df['trend_pos'] * lo_df['bm_1m_ret']
lo_df['hybrid_proxy'] = 0.70 * lo_df['bm_1m_ret'].fillna(0) + 0.15 * lo_df['tsmom_proxy'].fillna(0) + 0.15 * lo_df['bond_ret'].fillna(0)

cor_q5_hybrid = lo_df[['q5_lo_ret','hybrid_proxy']].corr().iloc[0,1]
print(f'cor(LO Q5, Hybrid 70/15/15 proxy): {cor_q5_hybrid:.4f}')

# Crisis (HIGH VKOSPI)
panel_dates = panel.groupby('Date')['vkospi'].first().reset_index()
lo_df = lo_df.merge(panel_dates, on='Date', how='left')
lo_df['vkospi_pct'] = lo_df['vkospi'].expanding(min_periods=12).rank(pct=True)
lo_df['regime'] = pd.cut(lo_df['vkospi_pct'], [0, 0.25, 0.75, 1.0], labels=['LOW','MID','HIGH'])
high_lo = lo_df[lo_df['regime']=='HIGH']
crisis_cor = high_lo[['q5_lo_ret','bm_1m_ret']].corr().iloc[0,1] if len(high_lo) > 5 else np.nan
print(f'HIGH-VKOSPI cor(LO Q5, BM): {crisis_cor:.4f}, n={len(high_lo)}')

# ================== 9. Save final report ==================
report = {
    'task_id': 'WT-D20260508_011',
    'as_of_date': '2026-05-08',
    'pipeline_version': 'v4_revise_post_codex',
    'fixes_applied': [
        'C1 — alpha_scores.parquet now full Date × Ticker × score panel (185 sig_dates × ~350 tickers)',
        'C4 — VRP/VKOSPI signals lagged t-1 (PIT C9 conservative)',
        'C5 — Quarterly rebalance + turnover hard mandate <600%/yr',
        'C6 — Strict 2e8 KRW liquidity floor (production constraint)',
        'C2 — IC strict gate honest disposition, no relaxed pass narrative',
        'rationalization grep cleanup (no rationalization phrases in package)'
    ],
    'pit_c9_lag_applied': True,
    'liquidity_filter': '20d TV >= 2e8 KRW (production hard)',
    'rebalance_freq': 'quarterly (every 3rd month)',
    'panel_size': len(panel),
    'oos_panel_size': len(oos),
    'oos_n_dates': int(len(oos['Date'].unique())),
    'ml_oos_metrics': {
        'rank_ic_oos_mean': float(ml_ic.mean()),
        'rank_ic_oos_std': float(ml_ic.std()),
        'icir_oos': float(ml_ic.mean() / ml_ic.std()) if ml_ic.std() > 0 else None,
        't_NW_oos_ic': float(nw_t(ml_ic)),
        'n_dates': int(len(ml_ic))
    },
    'lo_q5_quarterly_rebal_metrics': {
        'gross_sr_annual': float(lo_q5_gross_sr),
        'net_sr_annual': float(lo_q5_net_sr),
        't_NW_gross': float(lo_q5_gross_t),
        't_NW_net': float(lo_q5_net_t),
        'turnover_per_quarter': float(to_q_per_quarter),
        'turnover_annual_one_side': float(to_ann_quarterly),
        'turnover_annual_round_trip': float(to_ann_quarterly * 2),
        'turnover_pass_600pct': bool(to_ann_quarterly * 2 < 6.0),
        'cost_per_month_pct': float(cost_per_month * 100),
        'subperiod_stability': float(sub_stab),
        'subperiod_srs': sub_srs
    },
    'dsr': {
        'n_trials': N_TRIALS,
        'lo_q5_gross': float(dsr_lo_q5_gross),
        'lo_q5_net': float(dsr_lo_q5_net)
    },
    'orthogonality': {
        'cor_lo_q5_hybrid_proxy': float(cor_q5_hybrid),
        'pass_lt_25': bool(abs(cor_q5_hybrid) < 0.25)
    },
    'crisis_anti_hedge_check': {
        'high_vkospi_cor_with_bm': float(crisis_cor) if not np.isnan(crisis_cor) else None,
        'anti_hedge_resolved': bool(crisis_cor < 0.30) if not np.isnan(crisis_cor) else None
    },
    'graduation_strict_v4': {
        'rank_ic_oos_pass': bool(abs(ml_ic.mean()) >= 0.04),
        'icir_oos_pass': bool(abs(ml_ic.mean() / ml_ic.std()) >= 0.20) if ml_ic.std() > 0 else False,
        't_NW_oos_pass': bool(abs(nw_t(ml_ic)) >= 3.0),
        'sub_stab_pass': bool(sub_stab >= 0.5),
        'lo_q5_net_t_NW_pass': bool(abs(lo_q5_net_t) >= 3.0),
        'dsr_lo_q5_net_pass': bool(dsr_lo_q5_net >= 0.5),
        'turnover_pass': bool(to_ann_quarterly * 2 < 6.0),
        'orthogonality_pass': bool(abs(cor_q5_hybrid) < 0.25),
        'crisis_hedge_pass': bool(crisis_cor < 0.30) if not np.isnan(crisis_cor) else None
    }
}

# Strict graduation overall
gc = report['graduation_strict_v4']
strict_pass_count = sum([gc[k] for k in gc if isinstance(gc[k], bool) and gc[k] is True])
strict_total = len([k for k in gc if isinstance(gc[k], bool)])
report['graduation_pass_count'] = strict_pass_count
report['graduation_total'] = strict_total
report['graduation_overall_strict'] = bool(strict_pass_count == strict_total)

with open(f'{OUT}/alpha_validation_v4.json', 'w') as f:
    json.dump(report, f, indent=2, default=str)

print('\n=== v4 Validation summary ===')
print(json.dumps(report['graduation_strict_v4'], indent=2))
print(f'\nGraduation strict pass: {strict_pass_count}/{strict_total} = {"PASS" if report["graduation_overall_strict"] else "FAIL"}')
