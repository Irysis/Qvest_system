#!/usr/bin/env python3
"""
Screen3 re-run: Coverage-change (ΔN_analysts) momentum -> forward-12M Rank-IC.
SCREEN ONLY / advisory. No backtest, no admission.

PIT:
 - feature uses N up to t-1 (backward) only. No same-day (C2).
 - forward label = forward 12M return (lead). Built with positive-period forward window.
 - lockbox SIGNAL_CUTOFF = 2023-12-22 strict for the IN-SAMPLE screen window.
 - C14: coverage usable <= sig_date (month-end asof <= sig month-end).
"""
import pyarrow.parquet as pq
import numpy as np
import pandas as pd
from scipy import stats as ss
import os, json

OUT = os.path.dirname(os.path.abspath(__file__))
LOCKBOX = pd.Timestamp("2023-12-22")
log = []
def P(*a):
    s = " ".join(str(x) for x in a); log.append(s); print(s, flush=True)

P("=== screen3 deltaN coverage-change rank-IC ===")
P("lockbox SIGNAL_CUTOFF =", LOCKBOX.date())

# -----------------------------------------------------------------------------
# 1) coverage panel -> month-end N per ticker-month, lags, deltaN (t-1 backward)
# -----------------------------------------------------------------------------
cov = pq.read_table('.cache/consensus/coverage.parquet').to_pandas()
cov['Date'] = pd.to_datetime(cov['Date'])
cov = cov.sort_values(['Ticker', 'Date'])
cov['ym'] = cov['Date'].dt.to_period('M')
me = (cov.groupby(['Ticker', 'ym'])
        .agg(N=('coverage', 'last'), asof=('Date', 'max'))
        .reset_index()
        .sort_values(['Ticker', 'ym']))
g = me.groupby('Ticker')['N']
me['N_lag1'] = g.shift(1)   # value known as of prior month-end (t-1)
me['N_lag2'] = g.shift(2)
me['N_lag4'] = g.shift(4)
me['dN_1m'] = me['N_lag1'] - me['N_lag2']   # 1m change, fully lagged (no same-day)
me['dN_3m'] = me['N_lag1'] - me['N_lag4']   # 3m change, fully lagged
me['m_end'] = me['ym'].dt.to_timestamp(how='end').dt.normalize()
P("coverage month panel rows", len(me), "tickers", me.Ticker.nunique(),
  "months", me.ym.nunique(), "range", str(me.ym.min()), str(me.ym.max()))

# -----------------------------------------------------------------------------
# 2) rawdata -> month-end Close + Size + universe flags; forward 12M return
# -----------------------------------------------------------------------------
raw = pq.read_table('.cache/rawdata.parquet',
                    columns=['Date','Ticker','Close','Size','K200','KQ150','Market']).to_pandas()
raw['Date'] = pd.to_datetime(raw['Date'])
raw = raw.sort_values(['Ticker','Date'])
raw['ym'] = raw['Date'].dt.to_period('M')
# month-end snapshot (last trading day per ticker-month)
rme = (raw.groupby(['Ticker','ym'])
         .agg(Close=('Close','last'), Size=('Size','last'),
              K200=('K200','last'), KQ150=('KQ150','last'))
         .reset_index()
         .sort_values(['Ticker','ym']))
# forward 12M return: Close[m+12]/Close[m] - 1  (FORWARD label, lead)
rme['Close_f12'] = rme.groupby('Ticker')['Close'].shift(-12)
rme['fwd_ret_12m'] = rme['Close_f12'] / rme['Close'] - 1.0
P("rawdata month panel rows", len(rme), "tickers", rme.Ticker.nunique())

# -----------------------------------------------------------------------------
# 3) join on (Ticker, ym): feature(deltaN, lagged) at month m -> fwd 12M ret from m
# -----------------------------------------------------------------------------
df = me.merge(rme[['Ticker','ym','Size','K200','KQ150','fwd_ret_12m']],
              on=['Ticker','ym'], how='inner')

# universe filter: KOSPI200 OR KOSDAQ150 (matches production universe)
df['in_univ'] = (df['K200'] == 1) | (df['KQ150'] == 1)
df = df[df['in_univ']].copy()
P("after universe filter rows", len(df))

# log-size for residualization
df['ln_size'] = np.log(df['Size'].where(df['Size'] > 0))

# in-sample screen window: feature asof (t-1, = prior month) <= lockbox
df = df[df['m_end'] <= LOCKBOX].copy()
P("after lockbox cutoff rows", len(df))

# -----------------------------------------------------------------------------
# 4) cross-sectional: residualize deltaN on ln_size each month, then Rank-IC vs fwd ret
# -----------------------------------------------------------------------------
def resid_on_size(sub, col):
    s = sub[[col, 'ln_size']].dropna()
    if len(s) < 30 or s['ln_size'].nunique() < 5:
        return pd.Series(index=sub.index, dtype=float)
    x = s['ln_size'].values; y = s[col].values
    b1, b0, *_ = ss.linregress(x, y)
    r = pd.Series(index=sub.index, dtype=float)
    r.loc[s.index] = s[col].values - (b0 + b1 * s['ln_size'].values)
    return r

def monthly_rank_ic(frame, feat):
    rows = []
    for ym, sub in frame.groupby('ym'):
        s = sub[[feat, 'fwd_ret_12m']].dropna()
        if len(s) < 30:
            continue
        ic = ss.spearmanr(s[feat], s['fwd_ret_12m']).correlation
        if np.isnan(ic):
            continue
        rows.append((ym, len(s), ic))
    r = pd.DataFrame(rows, columns=['ym','n','ic'])
    return r

# add M27 (control) from monthly factor_db, joined by month
P("loading M27 control from factor_db monthly ...")
import glob
m27_list = []
for f in sorted(glob.glob('.cache/factor_db/factor_db_20*.parquet')):
    t = pq.read_table(f, columns=['Date','Ticker','Factor_Name','Z_Score'])
    sub = t.filter(t['Factor_Name'].to_pylist() == None) if False else None
    pdf = t.to_pandas()
    pdf = pdf[pdf['Factor_Name'] == 'M27_Analyst_Rev_Mom'][['Date','Ticker','Z_Score']]
    if len(pdf):
        m27_list.append(pdf)
if m27_list:
    m27 = pd.concat(m27_list, ignore_index=True)
    m27['Date'] = pd.to_datetime(m27['Date'])
    m27['ym'] = m27['Date'].dt.to_period('M')
    m27 = m27.rename(columns={'Z_Score': 'M27'})[['Ticker','ym','M27']]
    df = df.merge(m27, on=['Ticker','ym'], how='left')
    P("M27 merged; non-null M27 rows", int(df['M27'].notna().sum()))
else:
    df['M27'] = np.nan
    P("WARN: no M27 found")

# residualize size each month
for feat in ['dN_1m','dN_3m']:
    df[feat+'_rs'] = np.nan
    for ym, sub in df.groupby('ym'):
        df.loc[sub.index, feat+'_rs'] = resid_on_size(sub, feat)

# residualize deltaN_3m_rs further on M27 (orthogonal-to-revision test)
df['dN_3m_orthoM27'] = np.nan
for ym, sub in df.groupby('ym'):
    s = sub[['dN_3m_rs','M27']].dropna()
    if len(s) < 30 or s['M27'].nunique() < 5:
        continue
    b1, b0, *_ = ss.linregress(s['M27'].values, s['dN_3m_rs'].values)
    df.loc[s.index, 'dN_3m_orthoM27'] = s['dN_3m_rs'].values - (b0 + b1*s['M27'].values)

results = {}
def summarize(name, frame, feat):
    r = monthly_rank_ic(frame, feat)
    if len(r) < 6:
        results[name] = {'n_months': len(r), 'note': 'insufficient months'}
        P(f"[{name}] insufficient months n={len(r)}"); return
    mean_ic = r['ic'].mean(); sd = r['ic'].std(ddof=1)
    icir = mean_ic / sd if sd > 0 else np.nan
    # Newey-West-free simple t on monthly IC series
    t = mean_ic / (sd / np.sqrt(len(r)))
    results[name] = {
        'n_months': int(len(r)),
        'mean_rank_ic': round(float(mean_ic), 5),
        'ic_std': round(float(sd), 5),
        'ICIR': round(float(icir), 4),
        't_stat': round(float(t), 3),
        'avg_n_per_month': round(float(r['n'].mean()), 1),
        'ym_range': [str(r['ym'].min()), str(r['ym'].max())],
    }
    P(f"[{name}] months={len(r)} meanIC={mean_ic:.4f} ICIR={icir:.3f} t={t:.2f} avgN={r['n'].mean():.0f}")

summarize('dN_1m_size_resid', df, 'dN_1m_rs')
summarize('dN_3m_size_resid', df, 'dN_3m_rs')
summarize('dN_3m_ortho_M27',  df, 'dN_3m_orthoM27')
# raw M27 IC for benchmark comparison
summarize('M27_benchmark',    df, 'M27')

# go/no-go on the headline (orthogonal-to-M27) metric
head = results.get('dN_3m_ortho_M27', {})
go = (abs(head.get('mean_rank_ic', 0)) >= 0.02) and (abs(head.get('t_stat', 0)) > 2)
verdict = {
    'idea': 'coverage_change_deltaN_momentum',
    'headline_metric': 'forward_12M_rank_IC (dN_3m residualized on size, orthogonalized on M27)',
    'go_no_go': 'GO' if go else 'NO_GO',
    'criteria': '|IC|>=0.02 & |t|>2 & orthogonal to M27',
    'results': results,
    'lockbox': str(LOCKBOX.date()),
    'note': 'SCREEN advisory only, not tradeable',
}
json.dump(verdict, open(os.path.join(OUT,'screen_result.json'),'w'),
          ensure_ascii=False, indent=2)
open(os.path.join(OUT,'screen_log.txt'),'w').write("\n".join(log))
P("=== VERDICT ===")
P(json.dumps(verdict, ensure_ascii=False, indent=2))
P("WROTE screen_result.json + screen_log.txt")
