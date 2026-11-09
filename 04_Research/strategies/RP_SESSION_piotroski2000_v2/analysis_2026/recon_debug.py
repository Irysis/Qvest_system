"""Where does the reconstruction diverge from the contract daily returns? (diagnostic · read-only)"""
import sys, os
import numpy as np, pandas as pd, pyarrow.parquet as pq
ROOT, RUN = sys.argv[1], sys.argv[2]
D = os.path.join(ROOT, RUN)
pr = pd.read_csv(os.path.join(D, '03_period_returns.csv'), parse_dates=['date'])[['date', 'ret_gross', 'turnover', 'n_holdings']]
h = pd.read_csv(os.path.join(D, '04_holdings.csv'), dtype={'ticker': str}, parse_dates=['date'])
tk = ['A210980']
rd = pq.read_table(os.path.join(ROOT, '.cache', 'RAWDATA.parquet'), columns=['Date', 'Ticker', 'Close', 'Ret', 'TradingHalt', 'Vol'],
                   filters=[('Ticker', 'in', tk), ('Date', '>=', pd.Timestamp('2026-04-20'))]).to_pandas()
rd['Date'] = pd.to_datetime(rd['Date']); rd = rd.sort_values('Date')
rd['cc_ret'] = rd['Close'] / rd['Close'].shift(1) - 1
rd['ret_minus_cc'] = rd['Ret'] - rd['cc_ret']
m = rd.merge(pr, left_on='Date', right_on='date', how='left')
print('SK D&D days with |Ret| > 10% or Ret != close-to-close (>0.5%p) or halts:')
sel = m[(m['Ret'].abs() > 0.10) | (m['ret_minus_cc'].abs() > 0.005) | (m['TradingHalt'].fillna(0) > 0)]
print(sel[['Date', 'Close', 'Ret', 'cc_ret', 'TradingHalt', 'Vol', 'ret_gross']].round(4).to_string(index=False))
print('first/last close:', m[['Date', 'Close']].iloc[[0, -1]].to_string(index=False))
print('days in window:', len(m), '| NaN Ret days:', int(m['Ret'].isna().sum()))
w26 = h[h['date'] == pd.Timestamp('2026-05-04')]
print('2026 cohort weights: long n', int((w26.target_weight > 0).sum()), 'short', w26[w26.target_weight < 0][['ticker', 'target_weight', 'actual_weight']].to_string(index=False))
print(pr[pr['date'].between('2026-04-28', '2026-05-08')].to_string(index=False))
