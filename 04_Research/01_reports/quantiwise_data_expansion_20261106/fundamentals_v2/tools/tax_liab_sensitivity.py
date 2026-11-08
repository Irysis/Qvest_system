"""2015~ sensitivity: QMJ measures with DART current tax liabilities (TXP) / deferred tax liabilities (DTL)
vs the same measures with both set to 0 (what 2000~2014 would have to use). Read-only.
Also counts how far DART comparatives (frmtrm = prior year, bfefrmtrm = two years back) reach before 2015."""
import json, sys
import numpy as np
import pandas as pd
import pyarrow.parquet as pq

root, out_json = sys.argv[1], sys.argv[2]

# ---------- DART (primary FS, current + comparative columns) ----------
d = pq.read_table(f'{root}/.cache/dart/dart_raw_financials.parquet',
                  columns=['bsns_year', 'sj_div', 'account_id', 'account_nm', 'fs_div', 'Ticker',
                           'thstrm_amount', 'frmtrm_amount', 'bfefrmtrm_amount']).to_pandas()
d = d[d['sj_div'].astype(str) == 'BS'].copy()
d['acc'] = d['account_id'].astype(str)
d['nm'] = d['account_nm'].astype(str).str.replace(' ', '', regex=False)
num = lambda s: pd.to_numeric(s.astype(str).str.replace(',', '', regex=False).str.strip(), errors='coerce')
for c in ('thstrm_amount', 'frmtrm_amount', 'bfefrmtrm_amount'):
    d[c] = num(d[c])
d['year'] = d['bsns_year'].astype(int)
ta_rows = d[d['acc'].isin(['ifrs-full_Assets', 'ifrs_Assets']) & d['thstrm_amount'].notna()]
cfs = set(map(tuple, ta_rows[ta_rows['fs_div'] == 'CFS'][['Ticker', 'year']].values))
d = d[[(fs == 'CFS') or ((t, y) not in cfs) for fs, t, y in zip(d['fs_div'], d['Ticker'], d['year'])]]
txp_mask = d['acc'].isin(['ifrs-full_CurrentTaxLiabilities', 'ifrs_CurrentTaxLiabilities', 'dart_PaymentsOfIncomeTaxesPayable']) | \
           ((d['acc'] == '-표준계정코드 미사용-') & d['nm'].isin(['당기법인세부채', '미지급법인세', '법인세부채']))
dtl_mask = d['acc'].isin(['ifrs-full_DeferredTaxLiabilities', 'ifrs_DeferredTaxLiabilities', 'ifrs-full_NetDeferredTaxLiabilities']) | \
           ((d['acc'] == '-표준계정코드 미사용-') & d['nm'].isin(['이연법인세부채', '순이연법인세부채']))

def series(mask, col, shift):
    x = d[mask & d[col].notna()].groupby(['Ticker', 'year'], observed=True)[col].first().reset_index()
    x['year'] = x['year'] - shift
    return x.set_index(['Ticker', 'year'])[col]

def merged(mask):
    cur, prev, prev2 = series(mask, 'thstrm_amount', 0), series(mask, 'frmtrm_amount', 1), series(mask, 'bfefrmtrm_amount', 2)
    s = cur.combine_first(prev).combine_first(prev2)        # own report first, then later reports' comparatives
    return s, cur, prev, prev2

txp, txp_cur, txp_prev, txp_prev2 = merged(txp_mask)
dtl, dtl_cur, dtl_prev, dtl_prev2 = merged(dtl_mask)
reach = {}
for nm, (cur, prev, prev2) in (('TXP', (txp_cur, txp_prev, txp_prev2)), ('DTL', (dtl_cur, dtl_prev, dtl_prev2))):
    allv = cur.combine_first(prev).combine_first(prev2)
    yrs = allv.index.get_level_values('year')
    reach[nm] = {str(y): int((yrs == y).sum()) for y in range(2011, 2017)}
dart_firms = set(ta_rows['Ticker'])

# ---------- v2 annual (Dec FY) ----------
def load(db, items):
    t = pq.read_table(f'{root}/.cache/qw_fund_v2/{db}.parquet', columns=['Ticker', 'Period', 'Item', 'Value']).to_pandas()
    t = t[t['Item'].isin(items)]
    t['Period'] = t['Period'].astype(str)
    return t

bs = load('FundV2_BS', ['TotalEquity', 'PreferredCapital', 'TotalAssets', 'CurrentAssets', 'CashAndEquiv', 'CurrentLiab', 'CurrentBorr', 'CurrentBonds'])
bs = bs[bs['Period'].str.endswith('12')]
bs['year'] = bs['Period'].str[:4].astype(int)
B = bs.pivot_table(index=['Ticker', 'year'], columns='Item', values='Value', aggfunc='first')
flows = pd.concat([load('FundV2_IS', ['NetIncome', 'Revenue', 'GrossProfit']), load('FundV2_CF', ['DepAmortCF', 'Capex'])])
flows['year'] = flows['Period'].str[:4].astype(int)
fq = flows.groupby(['Ticker', 'year', 'Item'], observed=True)['Value'].agg(['sum', 'count']).reset_index()
fq = fq[fq['count'] == 4]
F = fq.pivot_table(index=['Ticker', 'year'], columns='Item', values='sum', aggfunc='first')
V = B.join(F, how='left')
V = V[V.index.get_level_values('Ticker').isin(dart_firms)]
z0 = lambda s: s.fillna(0.0)
V['txpD'] = z0(txp.reindex(V.index)); V['dtlD'] = z0(dtl.reindex(V.index))

def build(v, tx, dt):
    o = pd.DataFrame(index=v.index)
    be = v['TotalEquity'] - z0(v.get('PreferredCapital', 0)) + dt
    o['ROE'] = v['NetIncome'] / be.where(be > 0)
    wc = v['CurrentAssets'] - z0(v['CashAndEquiv']) - v['CurrentLiab'] + z0(v['CurrentBorr']) + z0(v['CurrentBonds']) + tx
    dwc = wc - wc.groupby(level=0).shift(1)
    o['ACC'] = -(dwc - z0(v['DepAmortCF'])) / v['TotalAssets']
    o['CFOA'] = (v['NetIncome'] + z0(v['DepAmortCF']) - dwc - z0(v['Capex'])) / v['TotalAssets']
    o['GPOA'] = v['GrossProfit'] / v['TotalAssets']
    o['ROA'] = v['NetIncome'] / v['TotalAssets']
    o['GMAR'] = v['GrossProfit'] / v['Revenue'].where(v['Revenue'] > 0)
    return o

D = build(V, V['txpD'], V['dtlD'])
Z = build(V, 0.0, 0.0)

def zrank(s):  # AFP: cross-sectional rank -> z
    r = s.rank()
    return (r - r.mean()) / r.std()

def prof(o):
    zz = pd.concat({m: o.groupby(level='year')[m].transform(zrank) for m in ('GPOA', 'ROE', 'ROA', 'CFOA', 'GMAR', 'ACC')}, axis=1)
    return zz.mean(axis=1, skipna=True)

D['PROF'] = prof(D); Z['PROF'] = prof(Z)
# compare only firm-years whose own DART annual report exists (otherwise D == Z by construction and agreement is inflated)
present = pd.MultiIndex.from_frame(ta_rows[['Ticker', 'year']].drop_duplicates())
keep = D.index.isin(present)
D = D[keep]; Z = Z[keep]
res = {'dart_reach_by_year(own_report+comparatives)': reach, 'per_measure': {}}
for m in ('ROE', 'ACC', 'CFOA', 'PROF'):
    rows = []
    for y in range(2016, 2025):
        a = D[m].xs(y, level='year'); b = Z[m].xs(y, level='year')
        s = pd.concat([a, b], axis=1, keys=['d', 'z']).replace([np.inf, -np.inf], np.nan).dropna()
        if len(s) < 50:
            continue
        rho = s['d'].rank().corr(s['z'].rank())
        q = lambda x: pd.cut(x.rank(pct=True), [0, 0.3, 0.7, 1.0], labels=['L', 'M', 'H'])
        agree = float((q(s['d']) == q(s['z'])).mean())
        rows.append({'year': y, 'n': int(len(s)), 'spearman': round(float(rho), 4), 'tercile_agree': round(agree, 4)})
    if rows:
        res['per_measure'][m] = {'years': rows,
                                 'spearman_median': round(float(np.median([r['spearman'] for r in rows])), 4),
                                 'spearman_min': round(float(min(r['spearman'] for r in rows)), 4),
                                 'tercile_agree_median': round(float(np.median([r['tercile_agree'] for r in rows])), 4),
                                 'tercile_agree_min': round(float(min(r['tercile_agree'] for r in rows)), 4)}
json.dump(res, open(out_json, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print(json.dumps({'reach': res['dart_reach_by_year(own_report+comparatives)'],
                  'summary': {m: {k: v for k, v in r.items() if k != 'years'} for m, r in res['per_measure'].items()},
                  'n_2020': {m: next((x['n'] for x in r['years'] if x['year'] == 2020), None) for m, r in res['per_measure'].items()}},
                 ensure_ascii=False, indent=1))
