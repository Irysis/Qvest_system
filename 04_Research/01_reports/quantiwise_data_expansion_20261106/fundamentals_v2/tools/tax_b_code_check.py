"""Validate FundV2_TAX (Quantiwise tax B codes, Time Series FQ0) against DART. Read-only. (2026-11-09)
TXP_B = OtherCurLiabInclTax - NonInterestCurLiab + TradePayables (B201700 - B101400 + B201600, IFRS glossary).
Truth = DART fnlttSinglAcntAll annual (11011), primary FS (CFS if the firm-year has CFS total assets else OFS),
Dec fiscal-year firms (fiscal_month == 12), FY2015~; TXP / DTL / DTA masks = tax_liab_check.py; several matched lines in
one firm-year -> the largest |value| (tax_liab_check.py took the first line).
Also: deferred tax net change (B100300 = dDTL - dDTA) vs DART same-report difference (current - prior column),
coverage by fiscal year (Dec quarter) and negative TXP_B counts.
Usage: python -I tax_b_code_check.py <root> <out_json>
"""
import json
import sys

import numpy as np
import pandas as pd
import pyarrow.parquet as pq

root, out_json = sys.argv[1].replace('\\', '/'), sys.argv[2]
res = {}

# ---------- FundV2_TAX ----------
t = pq.read_table(f'{root}/.cache/qw_fund_v2/FundV2_TAX.parquet', columns=['Ticker', 'Period', 'Item', 'Value']).to_pandas()
w = t.pivot_table(index=['Ticker', 'Period'], columns='Item', values='Value', aggfunc='first')
need = ['OtherCurLiabInclTax', 'NonInterestCurLiab', 'TradePayables', 'DeferredTaxNetChange']
for c in need:
    if c not in w.columns:
        w[c] = np.nan
w['TXP_B'] = w['OtherCurLiabInclTax'] - w['NonInterestCurLiab'] + w['TradePayables']
w = w.reset_index()
w['Period'] = w['Period'].astype(str)
w['year'] = w['Period'].str[:4].astype(int)
w['mm'] = w['Period'].str[4:6]
res['rows'] = {'raw': int(len(t)), 'ticker_periods': int(len(w)), 'tickers': int(w['Ticker'].nunique()),
               'periods': [w['Period'].min(), w['Period'].max()]}

# coverage by fiscal year (Dec quarter) vs v2 TotalAssets (Dec) firms
bs = pq.read_table(f'{root}/.cache/qw_fund_v2/FundV2_BS.parquet', columns=['Ticker', 'Period', 'Item', 'Value']).to_pandas()
ta = bs[(bs['Item'] == 'TotalAssets') & bs['Period'].astype(str).str.endswith('12') & bs['Value'].notna()].copy()
ta['year'] = ta['Period'].astype(str).str[:4].astype(int)
ta = ta.groupby(['Ticker', 'year'])['Value'].first()
dec = w[w['mm'] == '12'].set_index(['Ticker', 'year'])
cov = {}
for y in range(2000, 2026):
    n_ta = int((ta.index.get_level_values('year') == y).sum())
    d = dec[dec.index.get_level_values('year') == y]
    cov[str(y)] = {'v2_total_assets_firms': n_ta, 'txp_b_firms': int(d['TXP_B'].notna().sum()),
                   'dtax_chg_firms': int(d['DeferredTaxNetChange'].notna().sum())}
res['coverage_dec_by_year'] = cov
txpb = w[w['TXP_B'].notna()]
res['negative_txp_b'] = {'cells': int((txpb['TXP_B'] < -1000).sum()), 'of': int(len(txpb)),
                         'share': round(float((txpb['TXP_B'] < -1000).mean()), 5) if len(txpb) else None}

# ---------- DART truth ----------
fm = pq.read_table(f'{root}/.cache/qw_fund_v2/fiscal_month.parquet').to_pandas()
dec_fy = set(fm.loc[fm['FiscalMonth'].astype(str) == '12', 'Ticker'])
d = pq.read_table(f'{root}/.cache/dart/dart_raw_financials.parquet',
                  columns=['bsns_year', 'sj_div', 'account_id', 'account_nm', 'fs_div', 'Ticker',
                           'thstrm_amount', 'frmtrm_amount']).to_pandas()
d = d[(d['sj_div'].astype(str) == 'BS') & d['Ticker'].isin(dec_fy)].copy()
d['acc'] = d['account_id'].astype(str)
d['nm'] = d['account_nm'].astype(str).str.replace(' ', '', regex=False)
for c in ('thstrm_amount', 'frmtrm_amount'):
    d[c] = pd.to_numeric(d[c].astype(str).str.replace(',', '', regex=False).str.strip(), errors='coerce')
d['year'] = d['bsns_year'].astype(int)
ta_rows = d[d['acc'].isin(['ifrs-full_Assets', 'ifrs_Assets']) & d['thstrm_amount'].notna()]
cfs = set(map(tuple, ta_rows[ta_rows['fs_div'] == 'CFS'][['Ticker', 'year']].values))
d = d[[(fs == 'CFS') or ((tk, y) not in cfs) for fs, tk, y in zip(d['fs_div'], d['Ticker'], d['year'])]]
present = set(map(tuple, ta_rows[['Ticker', 'year']].drop_duplicates().values))
txp_m = d['acc'].isin(['ifrs-full_CurrentTaxLiabilities', 'ifrs_CurrentTaxLiabilities', 'dart_PaymentsOfIncomeTaxesPayable']) | \
    ((d['acc'] == '-표준계정코드 미사용-') & d['nm'].isin(['당기법인세부채', '미지급법인세', '법인세부채']))
dtl_m = d['acc'].isin(['ifrs-full_DeferredTaxLiabilities', 'ifrs_DeferredTaxLiabilities', 'ifrs-full_NetDeferredTaxLiabilities']) | \
    ((d['acc'] == '-표준계정코드 미사용-') & d['nm'].isin(['이연법인세부채', '순이연법인세부채']))
dta_m = d['acc'].isin(['ifrs-full_DeferredTaxAssets', 'ifrs_DeferredTaxAssets', 'ifrs-full_NetDeferredTaxAssets'])


def line(mask, col='thstrm_amount'):
    """One value per firm-year. Several matched lines (standard id + a non-standard duplicate, or '미지급법인세' next to
    '당기법인세부채') often carry the value on one line and 0 on the other -> take the line with the largest |value|
    (11-09: first-line pick turned A064820 FY2023 / A015230 FY2024 into false mismatches - B codes matched the standard line)."""
    x = d[mask & d[col].notna()][['Ticker', 'year', col]].copy()
    x['_a'] = x[col].abs()
    return x.sort_values('_a', ascending=False, kind='mergesort').groupby(['Ticker', 'year'])[col].first()


TXP = line(txp_m)
TA_D = ta_rows[[(fs == 'CFS') or ((tk, y) not in cfs) for fs, tk, y in zip(ta_rows['fs_div'], ta_rows['Ticker'], ta_rows['year'])]] \
    .groupby(['Ticker', 'year'])['thstrm_amount'].first()


def compare(truth, cand, label, by_year=True):
    j = pd.concat([truth, cand, TA_D], axis=1, keys=['t', 'c', 'ta']).dropna(subset=['t', 'c'])
    j = j[[k in present for k in j.index]] if len(j) else j
    if not len(j):
        res[label] = {'n': 0}
        return
    diff = (j['c'] - j['t']).abs()
    rel = diff / j['t'].abs().clip(lower=1)
    exact = diff <= np.maximum(1000.0, 1e-6 * j['t'].abs())
    out = {'n': int(len(j)), 'exact': round(float(exact.mean()), 4), 'within_1pct': round(float((rel <= 0.01).mean()), 4),
           'within_5pct': round(float((rel <= 0.05).mean()), 4),
           'spearman': round(float(j['t'].rank().corr(j['c'].rank())), 4),
           'err_vs_TA_median_pct': round(float((diff / j['ta'].abs().clip(lower=1)).median() * 100), 5)}
    if by_year:
        yrs = j.index.get_level_values('year')
        out['by_year'] = {str(y): {'n': int((yrs == y).sum()), 'exact': round(float(exact[yrs == y].mean()), 4)}
                          for y in sorted(set(yrs))}
    bad = j[~exact].copy()
    bad['rel'] = rel[~exact]
    out['worst_10'] = [{'ticker': k[0], 'year': int(k[1]), 'dart': float(r['t']), 'b_code': float(r['c']), 'rel': round(float(r['rel']), 4)}
                       for k, r in bad.sort_values('rel', ascending=False).head(10).iterrows()]
    res[label] = out


txp_b_dec = dec['TXP_B']
compare(TXP, txp_b_dec, 'TXP_B_vs_DART')
# mismatch profile: DART 0 vs B > 0 · B 0 vs DART > 0 · both non-zero (rounding = DART in KRW mn) · foreign issuers (A9xxxxx)
_j = pd.concat([TXP, txp_b_dec], axis=1, keys=['t', 'c']).dropna()
_j = _j[[k in present for k in _j.index]]
_ex = (_j['c'] - _j['t']).abs() <= np.maximum(1000.0, 1e-6 * _j['t'].abs())
_bad = _j[~_ex]
_cat = np.select([(_bad['t'].abs() <= 1000) & (_bad['c'].abs() > 1000), (_bad['c'].abs() <= 1000) & (_bad['t'].abs() > 1000)],
                 ['dart0_b_pos', 'b0_dart_pos'], 'both_nonzero')
_bn = _bad[_cat == 'both_nonzero']
_dom = ~_j.index.get_level_values('Ticker').str.startswith('A9')
_rel = (_j['c'] - _j['t']).abs() / _j['t'].abs().clip(lower=1)
res['TXP_B_mismatch_profile'] = {
    'n_mismatch': int(len(_bad)), 'by_type': {k: int(v) for k, v in pd.Series(_cat).value_counts().items()},
    'both_nonzero_median_ratio_b_over_dart': round(float((_bn['c'] / _bn['t']).median()), 4) if len(_bn) else None,
    'mismatch_firms': int(_bad.index.get_level_values('Ticker').nunique()),
    'mismatch_foreign_A9_share': round(float(_bad.index.get_level_values('Ticker').str.startswith('A9').mean()), 4) if len(_bad) else None,
    'domestic_only': {'n': int(_dom.sum()), 'exact': round(float(_ex[_dom].mean()), 4),
                      'within_1pct': round(float((_rel[_dom] <= 0.01).mean()), 4)}}
# DART firm-years without any TXP line (truth presumably 0 / not separately reported): how large is TXP_B there?
nol = pd.concat([txp_b_dec, TA_D], axis=1, keys=['c', 'ta']).dropna()
nol = nol[[k in present and k not in TXP.index for k in nol.index]]
res['TXP_B_where_DART_has_no_line'] = {'n': int(len(nol)), 'zero_within_1000won': round(float((nol['c'].abs() <= 1000).mean()), 4) if len(nol) else None,
                                       'abs_vs_TA_median_pct': round(float((nol['c'].abs() / nol['ta'].abs().clip(lower=1)).median() * 100), 5) if len(nol) else None}
# coverage of DART TXP firm-years by B codes
dart_txp_keys = [k for k in TXP.index if k in present]
res['DART_TXP_firmyears_covered_by_B'] = {'dart_n': len(dart_txp_keys),
                                          'b_code_present': int(sum(1 for k in dart_txp_keys if k in txp_b_dec.index and pd.notna(txp_b_dec.get(k))))}

# deferred tax net change: DART same report (current - prior column); missing one of the two lines -> 0 for that line
DTL, DTL0, DTA, DTA0 = line(dtl_m), line(dtl_m, 'frmtrm_amount'), line(dta_m), line(dta_m, 'frmtrm_amount')
idx = sorted(set(DTL.index) | set(DTA.index))
dd = pd.Series({k: (DTL.get(k, 0.0) - DTL0.get(k, 0.0)) - (DTA.get(k, 0.0) - DTA0.get(k, 0.0)) for k in idx
                if (k in DTL.index and k in DTL0.index) or (k in DTA.index and k in DTA0.index)}, dtype=float)
dd.index = pd.MultiIndex.from_tuples(dd.index, names=['Ticker', 'year'])
q = w[['Ticker', 'year', 'DeferredTaxNetChange']].dropna()
qs = q.groupby(['Ticker', 'year'])['DeferredTaxNetChange'].agg(['sum', 'count'])
compare(dd, dec['DeferredTaxNetChange'], 'dDTLnet_vs_DART_dec_value', by_year=False)
compare(dd, qs.loc[qs['count'] == 4, 'sum'], 'dDTLnet_vs_DART_sum_of_4q', by_year=False)

with open(out_json, 'w', encoding='utf-8') as f:
    json.dump(res, f, ensure_ascii=False, indent=1)
print(json.dumps({k: v for k, v in res.items() if k not in ('coverage_dec_by_year',)}, ensure_ascii=False, indent=1, default=str)[:6000])
print('coverage (Dec · v2 TA firms / TXP_B firms):',
      {y: f"{c['v2_total_assets_firms']}/{c['txp_b_firms']}" for y, c in cov.items() if int(y) % 3 == 0 or int(y) >= 2023})
