"""Can v2 (Quantiwise fundamentals) compute current tax liabilities (TXP) and deferred tax liabilities (DTL)?
Ground truth = DART fnlttSinglAcntAll annual (11011), primary FS (CFS if present else OFS), Dec FY firm-years 2015~.
Read-only. Prints agreement metrics per candidate."""
import json, sys
import numpy as np
import pandas as pd
import pyarrow.parquet as pq

root = sys.argv[1]
out_json = sys.argv[2]

# ---------- DART ground truth ----------
d = pq.read_table(f'{root}/.cache/dart/dart_raw_financials.parquet',
                  columns=['bsns_year', 'sj_div', 'account_id', 'account_nm', 'fs_div', 'Ticker', 'thstrm_amount']).to_pandas()
d = d[d['sj_div'].astype(str) == 'BS'].copy()
d['acc'] = d['account_id'].astype(str)
d['nm'] = d['account_nm'].astype(str).str.replace(' ', '', regex=False)
d['v'] = pd.to_numeric(d['thstrm_amount'].astype(str).str.replace(',', '', regex=False).str.strip(), errors='coerce')
d['year'] = d['bsns_year'].astype(str)

def pick(mask):
    x = d[mask & d['v'].notna()]
    # one value per (Ticker, year, fs_div): first occurrence (standard code rows come first in ord order)
    return x.groupby(['Ticker', 'year', 'fs_div'], observed=True)['v'].first()

txp_mask = d['acc'].isin(['ifrs-full_CurrentTaxLiabilities', 'ifrs_CurrentTaxLiabilities', 'dart_PaymentsOfIncomeTaxesPayable']) | \
           ((d['acc'] == '-표준계정코드 미사용-') & d['nm'].isin(['당기법인세부채', '미지급법인세', '법인세부채']))
dtl_mask = d['acc'].isin(['ifrs-full_DeferredTaxLiabilities', 'ifrs_DeferredTaxLiabilities', 'ifrs-full_NetDeferredTaxLiabilities']) | \
           ((d['acc'] == '-표준계정코드 미사용-') & d['nm'].isin(['이연법인세부채', '순이연법인세부채']))
ta_mask = d['acc'].isin(['ifrs-full_Assets', 'ifrs_Assets'])
cl_mask = d['acc'].isin(['ifrs-full_CurrentLiabilities', 'ifrs_CurrentLiabilities'])
ncl_mask = d['acc'].isin(['ifrs-full_NoncurrentLiabilities', 'ifrs_NoncurrentLiabilities'])

g = pd.DataFrame({'txp': pick(txp_mask), 'dtl': pick(dtl_mask), 'ta': pick(ta_mask), 'cl': pick(cl_mask), 'ncl': pick(ncl_mask)}).reset_index()
# primary FS: CFS if the firm-year has a CFS total-assets row, else OFS
has_cfs = g[(g['fs_div'] == 'CFS') & g['ta'].notna()][['Ticker', 'year']].drop_duplicates().assign(cfs=True)
g = g.merge(has_cfs, on=['Ticker', 'year'], how='left')
g = g[(g['fs_div'] == 'CFS') | ((g['fs_div'] == 'OFS') & g['cfs'].isna())].drop(columns=['cfs'])
g = g[g['ta'].notna() & (g['ta'] > 0)]
dart = g.set_index(['Ticker', 'year'])

# ---------- v2 ----------
bs = pq.read_table(f'{root}/.cache/qw_fund_v2/FundV2_BS.parquet', columns=['Ticker', 'Period', 'Item', 'Value']).to_pandas()
bs = bs[bs['Period'].astype(str).str.endswith('12') & (bs['Period'].astype(str) >= '201412')]
bs['year'] = bs['Period'].astype(str).str[:4]
w = bs.pivot_table(index=['Ticker', 'year'], columns='Item', values='Value', aggfunc='first')
isq = pq.read_table(f'{root}/.cache/qw_fund_v2/FundV2_IS.parquet', columns=['Ticker', 'Period', 'Item', 'Value']).to_pandas()
isq = isq[(isq['Item'] == 'TaxExpense') & (isq['Period'].astype(str) >= '201403')]
isq['year'] = isq['Period'].astype(str).str[:4]
tax = isq.groupby(['Ticker', 'year'], observed=True)['Value'].agg(['sum', 'count'])
tax = tax[tax['count'] == 4]['sum'].rename('tax_exp')
w = w.join(tax, how='left')
w['tax_exp_lag'] = w.groupby(level=0)['tax_exp'].shift(1)

def col(name):
    return w[name] if name in w.columns else pd.Series(0.0, index=w.index)

z = lambda s: s.fillna(0.0)
# candidates
w['TXP_resid'] = col('CurrentLiab') - z(col('AccountsPay')) - z(col('CurrentBorr')) - z(col('CurrentBonds')) - z(col('HeldForSaleLiab'))
w['TXP_taxmodel'] = (w['tax_exp'] - 0.5 * w['tax_exp_lag']).clip(lower=0)
w['TXP_half_tax'] = (0.5 * w['tax_exp']).clip(lower=0)
lt_debt = z(col('Bonds')) + z(col('ConvBonds')) + z(col('BondsWithWarrants')) + z(col('ExchBonds')) + z(col('LongTermBorr'))
w['DTL_resid'] = col('NonCurrentLiab') - lt_debt - z(col('LongTermPay'))
w['DTL_resid_ibd'] = col('NonCurrentLiab') - (z(col('InterestBearingDebt')) - z(col('CurrentBorr')) - z(col('CurrentBonds'))) - z(col('LongTermPay'))

j = dart.join(w[['TotalAssets', 'CurrentLiab', 'NonCurrentLiab', 'TotalEquity', 'TXP_resid', 'TXP_taxmodel', 'TXP_half_tax', 'DTL_resid', 'DTL_resid_ibd']], how='inner')
j = j[j.index.get_level_values('year') >= '2015']
res = {'n_dart_firmyears': int(len(dart[dart.index.get_level_values('year') >= '2015'])), 'n_joined': int(len(j))}

# sanity: base totals agree (same firm-year, same FS)?
for a, b in (('ta', 'TotalAssets'), ('cl', 'CurrentLiab'), ('ncl', 'NonCurrentLiab')):
    s = j[[a, b]].dropna()
    rel = (s[b] - s[a]).abs() / s[a].abs().clip(lower=1)
    res[f'sanity_{a}'] = {'n': int(len(s)), 'within_0.5pct': round(float((rel <= 0.005).mean()), 4)}

def metrics(truth, cand, scale):
    s = pd.DataFrame({'t': truth, 'c': cand, 'sc': scale}).dropna()
    s = s[s['sc'] > 0]
    if not len(s):
        return {'n': 0}
    err = (s['c'] - s['t']).abs() / s['sc']
    rel = (s['c'] - s['t']).abs() / s['t'].abs().clip(lower=1)
    return {'n': int(len(s)),
            'spearman': round(float(s['t'].rank().corr(s['c'].rank())), 3),
            'exact_within_1pct_of_value': round(float((rel <= 0.01).mean()), 3),
            'err_vs_TA_median_pct': round(float(err.median() * 100), 3),
            'err_vs_TA_p90_pct': round(float(err.quantile(0.9) * 100), 3),
            'truth_vs_TA_median_pct': round(float((s['t'].abs() / s['sc']).median() * 100), 3),
            'truth_vs_TA_p90_pct': round(float((s['t'].abs() / s['sc']).quantile(0.9) * 100), 3)}

res['TXP_coverage'] = {'dart_reports_line_share': round(float(j['txp'].notna().mean()), 3)}
res['DTL_coverage'] = {'dart_reports_line_share': round(float(j['dtl'].notna().mean()), 3)}
for c in ('TXP_resid', 'TXP_taxmodel', 'TXP_half_tax'):
    res[c] = metrics(j['txp'], j[c], j['ta'])
res['TXP_zero'] = metrics(j['txp'], pd.Series(0.0, index=j.index).where(j['txp'].notna()), j['ta'])
for c in ('DTL_resid', 'DTL_resid_ibd'):
    res[c] = metrics(j['dtl'], j[c], j['ta'])
res['DTL_zero'] = metrics(j['dtl'], pd.Series(0.0, index=j.index).where(j['dtl'].notna()), j['ta'])
# share of DTL in book equity (how much BE moves if DTL is set to 0)
s = j[['dtl', 'TotalEquity']].dropna(); s = s[s['TotalEquity'] > 0]
res['DTL_vs_equity'] = {'n': int(len(s)), 'median_pct': round(float((s['dtl'] / s['TotalEquity']).median() * 100), 3),
                        'p90_pct': round(float((s['dtl'] / s['TotalEquity']).quantile(0.9) * 100), 3)}
json.dump(res, open(out_json, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print(json.dumps(res, ensure_ascii=False, indent=1))
