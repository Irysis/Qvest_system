"""F-Score (Piotroski 2000) hl representative — 2026 portfolio analysis (descriptive · read-only).
Inputs = contract artifacts of the canonical run (04_holdings.csv · 03_period_returns.csv · 05_benchmark_returns.csv ·
factors_panel.parquet) + RAWDATA daily Ret/Name. Portfolio-level figures (YTD · monthly · drawdown) = contract NAV ratios.
Stock attribution = DIAGNOSTIC reconstruction with a dollar buy-and-hold book (P = 1 + L - S within a cohort, paper-style).
It does NOT reconcile with the contract: the harness combines legs daily (Rg = GL*L - GS*S, replication_harness.R:339),
so contract-vs-reconstruction diverge (2026 corr 0.83). Contribution sums are therefore paper-style diagnostics, not
contract numbers (summary.reconstruction.reconciled = False). Writes ytd_2026_*.csv + ytd_2026_summary.json here."""
import json, sys, os
import numpy as np, pandas as pd, pyarrow.parquet as pq

ROOT = sys.argv[1]
RUN = sys.argv[2]                       # stage_artifacts/replication/<run_id>
OUT = os.path.dirname(os.path.abspath(__file__))
D = os.path.join(ROOT, RUN)
h = pd.read_csv(os.path.join(D, '04_holdings.csv'), dtype={'ticker': str}, parse_dates=['date'])
pr = pd.read_csv(os.path.join(D, '03_period_returns.csv'), parse_dates=['date'])[['date', 'ret_gross', 'ret_net']]
bm = pd.read_csv(os.path.join(D, '05_benchmark_returns.csv'), parse_dates=['date'])[['date', 'benchmark_ret']]
fp = pq.read_table(os.path.join(D, 'factors_panel.parquet')).to_pandas()
fp['Date'] = pd.to_datetime(fp['Date'])

reb = sorted(h['date'].unique())
c25, c26 = pd.Timestamp('2025-05-02'), pd.Timestamp('2026-05-04')
assert c25 in reb and c26 in reb, reb[-3:]
tick = sorted(set(h.loc[h['date'].isin([c25, c26]), 'ticker']))
rd = pq.read_table(os.path.join(ROOT, '.cache', 'RAWDATA.parquet'), columns=['Date', 'Ticker', 'Name', 'Ret', 'Close'],
                   filters=[('Ticker', 'in', tick), ('Date', '>=', pd.Timestamp('2025-04-25'))]).to_pandas()
rd['Date'] = pd.to_datetime(rd['Date'])
names = rd.sort_values('Date').groupby('Ticker')['Name'].last()
R = rd.pivot_table(index='Date', columns='Ticker', values='Ret', aggfunc='first').sort_index()
days = pr.loc[pr['date'] > c25, 'date'].tolist()

def book(cohort_date, end_date):
    """Daily reconstructed returns + per-stock daily contributions for one cohort (execution at cohort_date close)."""
    w = h[h['date'] == cohort_date].set_index('ticker')['target_weight']
    longs, shorts = w[w > 0].index.tolist(), w[w < 0].index.tolist()
    l = pd.Series(w[longs].values, index=longs)          # long values per unit NAV at formation (sum 1)
    s = pd.Series(-w[shorts].values, index=shorts)       # short liability per unit NAV (sum 1)
    P = 1.0
    rows, contrib = [], []
    for d in [x for x in days if cohort_date < x <= end_date]:
        r = R.loc[d] if d in R.index else pd.Series(dtype=float)
        rl = r.reindex(longs).fillna(0.0); rs = r.reindex(shorts).fillna(0.0)    # missing day (halt/delisted) = 0
        dl = l * rl; ds = s * rs
        ret = (dl.sum() - ds.sum()) / P
        contrib.append(pd.concat([dl / P, -ds / P]).rename(d))
        l = l + dl; s = s + ds; P = P + dl.sum() - ds.sum()
        rows.append((d, ret))
    return pd.DataFrame(rows, columns=['date', 'ret_rec']), pd.DataFrame(contrib), longs, shorts

b25, k25, L25, S25 = book(c25, c26)
b26, k26, L26, S26 = book(c26, pr['date'].max())
rec = pd.concat([b25, b26]).merge(pr, on='date')
chk = rec[rec['date'].dt.year == 2026]
dev = (chk['ret_rec'] - chk['ret_gross']).abs()
cum_c = float((1 + chk['ret_gross']).prod() - 1); cum_r = float((1 + chk['ret_rec']).prod() - 1)
print(f'reconstruction 2026: n={len(chk)} corr={chk["ret_rec"].corr(chk["ret_gross"]):.6f} max|dev|={dev.max():.2e} '
      f'cum contract={cum_c:.4f} rec={cum_r:.4f}')

# ---- contract numbers (2026 YTD · monthly) — NAV ratios from 02_nav.csv / 05_benchmark_returns.csv (no self compounding) ----
nv = pd.read_csv(os.path.join(D, '02_nav.csv'), parse_dates=['date'])[['date', 'nav_net']]
bn = pd.read_csv(os.path.join(D, '05_benchmark_returns.csv'), parse_dates=['date'])[['date', 'benchmark_nav']]
nb = nv.merge(bn, on='date').set_index('date').sort_index()
base = nb[nb.index.year == 2025].iloc[-1]                       # last 2025 close = 2026 base
y26 = nb[nb.index.year == 2026]
ytd = {'strategy_net': float(y26['nav_net'].iloc[-1] / base['nav_net'] - 1),
       'kospi200': float(y26['benchmark_nav'].iloc[-1] / base['benchmark_nav'] - 1),
       'first': str(y26.index.min().date()), 'last': str(y26.index.max().date())}
me = pd.concat([base.to_frame().T, y26.groupby(y26.index.to_period('M')).tail(1)])
mon = pd.DataFrame({'strategy': me['nav_net'].pct_change(), 'kospi200': me['benchmark_nav'].pct_change()}).iloc[1:]
mon.index = [d.strftime('%Y-%m') for d in mon.index]
rel = y26['nav_net'] / base['nav_net']                          # 2026 path (NAV ratio)
dd = rel / rel.cummax() - 1
ytd['max_dd_2026'] = float(dd.min()); ytd['max_dd_trough'] = str(dd.idxmin().date()); ytd['max_dd_peak'] = str(rel.loc[:dd.idxmin()].idxmax().date())
ytd['peak_ytd'] = float(rel.max() - 1); ytd['peak_ytd_date'] = str(rel.idxmax().date())
ytd['trough_ytd'] = float(rel.min() - 1); ytd['trough_ytd_date'] = str(rel.idxmin().date())

# ---- attribution (2026 days only · arithmetic sum of daily contributions) ------------------
def attrib(k, longs, shorts, cohort_date, seg):
    k = k[k.index.year == 2026]
    if k.empty:
        return pd.DataFrame()
    t = pd.DataFrame({'contrib_sum': k.sum()})
    t['leg'] = np.where(t.index.isin(shorts), 'short', 'long'); t['name'] = names.reindex(t.index).values
    seg_days = k.index
    cr = (1 + R.loc[R.index.isin(seg_days)].reindex(columns=t.index).fillna(0)).prod() - 1
    t['stock_ret_in_segment'] = cr.values
    f = fp[fp['Date'] == fp.loc[fp['Date'] <= cohort_date, 'Date'].max()].set_index('Ticker')['Score']
    t['fscore'] = f.reindex(t.index).values
    t['segment'] = seg
    return t.sort_values('contrib_sum')

a25 = attrib(k25, L25, S25, c25, '2026-01-02..2026-05-04 (2025 cohort)')
a26 = attrib(k26, L26, S26, c26, '2026-05-05..' + ytd['last'] + ' (2026 cohort)')
att = pd.concat([a25, a26]).reset_index(names='ticker')
att.to_csv(os.path.join(OUT, 'ytd_2026_attribution.csv'), index=False, encoding='utf-8-sig')
mon.to_csv(os.path.join(OUT, 'ytd_2026_monthly.csv'), encoding='utf-8-sig')
legs = att.groupby(['segment', 'leg'])['contrib_sum'].agg(['sum', 'count']).reset_index()
summary = {'run': RUN, 'ytd': ytd, 'reconstruction': {'n_days': int(len(chk)), 'corr': float(chk['ret_rec'].corr(chk['ret_gross'])),
           'max_abs_dev': float(dev.max()), 'cum_contract_gross': cum_c, 'cum_reconstructed': cum_r,
           'reconciled': bool(dev.max() < 1e-6),
           'note': 'dollar buy-and-hold (paper-style) vs harness daily leg combination Rg = GL*L - GS*S — contributions are diagnostic'},
           'cohorts': {'2025': {'n_long': len(L25), 'n_short': len(S25), 'shorts': {t: names.get(t) for t in S25}},
                       '2026': {'n_long': len(L26), 'n_short': len(S26), 'shorts': {t: names.get(t) for t in S26}}},
           'legs': legs.to_dict('records'), 'monthly': mon.reset_index().to_dict('records')}
json.dump(summary, open(os.path.join(OUT, 'ytd_2026_summary.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1, default=str)
print(json.dumps({k: summary[k] for k in ('ytd', 'reconstruction', 'cohorts')}, ensure_ascii=False, indent=1, default=str))
print(legs.to_string(index=False))
print(mon.round(4).to_string())
for seg, g in att.groupby('segment'):
    print('==', seg)
    print(g.sort_values('contrib_sum').head(6)[['ticker', 'name', 'leg', 'fscore', 'stock_ret_in_segment', 'contrib_sum']].round(4).to_string(index=False))
    print(g.sort_values('contrib_sum').tail(6)[['ticker', 'name', 'leg', 'fscore', 'stock_ret_in_segment', 'contrib_sum']].round(4).to_string(index=False))
