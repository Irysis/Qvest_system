"""qw_fund_v2_tax_ingest.py - Time Series (Company) tax B-code book -> .cache/qw_fund_v2/FundV2_TAX.parquet (2026-11-09)

Decision: Dohoon 11-09 'jigeum sujip' - collect the four tax-related IFRS B codes for all firms from 2000Q1 into the
fundamentals DB v2 (raw DB FundV2_TAX). Current tax payable TXP = OtherCurLiabInclTax - NonInterestCurLiab + TradePayables
(B201700 - B101400 + B201600, glossary definitions; matched DART 109/109 in the 10-firm test).

Book = 03_Universe/Fundamental_v2/FundV2_TAX_TS.xlsx, built and refreshed by 02_Infrastructure/ops/qw_fund_v2_tax_ts.ps1.
Sheet layout (Time Series (Company)): B1 'Last Update : <ts>' . row 8 ticker codes (from column B) . B10 item code .
row 11 unit per column . row 12 Base Date (FQ0) . row 14 item names . rows 15.. column A = date 'YYYY-MM'.
Mapping (official XLA manual p.58 / p.64): with Base Date FQ0 (default 3-month lagging) the value on date row d is the
fiscal quarter d - 1Q. Units 'Local thou' / 'KRW thou' -> x1000 = KRW.

Gates (stop with rc 1, nothing written): every sheet present . B10 code as expected . B12 == 'FQ0' . B1 date == --expect-date
(default today) . numeric cells > 0 per sheet . a numeric cell under an unknown (non-blank) unit . payables positive control
(NonInterestCurLiab >= v2 AccountsPay share >= 0.98 - catches a changed lagging option or unit). A blank unit = add-in default
for financial items (KRW thousand, manual p.63) - those tickers are listed in the report.
Text cells ('#INVALID OPTION' = financial firms; B codes are defined for non-financial firms) are dropped and counted.
Output schema = the other raw v2 DBs: Ticker, Period (YYYYMM), Item, Value (KRW), Text, first_fetched_at, last_fetched_at.
The book is a full window -> the parquet is replaced; first_fetched_at is kept for (Ticker, Period, Item) already present.
Usage: python qw_fund_v2_tax_ingest.py --root <project root> [--book <xlsx>] [--expect-date YYYY-MM-DD] [--dry-run]
"""
import argparse
import datetime as dt
import json
import os
import sys

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
from openpyxl import load_workbook

SCHEMA = pa.schema([('Ticker', pa.string()), ('Period', pa.string()), ('Item', pa.string()), ('Value', pa.float64()),
                    ('Text', pa.string()), ('first_fetched_at', pa.string()), ('last_fetched_at', pa.string())])

SHEETS = {  # sheet -> (expected code, item name)
    'B201700_M': ('B201700.M', 'OtherCurLiabInclTax'),
    'B101400_M': ('B101400.M', 'NonInterestCurLiab'),
    'B201600_M': ('B201600.M', 'TradePayables'),
    'B100300_M': ('B100300.M', 'DeferredTaxNetChange'),
}
UNIT_SCALE = {'local thou': 1e3, 'krw thou': 1e3, 'local': 1.0, 'krw': 1.0, 'local mn': 1e6, 'krw mn': 1e6}
# A blank unit cell with numbers under it = the add-in default for financial items, KRW thousand (manual p.63). 11-09 full run:
#   4 tickers (delisted 'EX' A150840 . A208340 and new-format A0001A0 . A0011A0 - name 'N/A') had blank units; their values
#   matched v2 AccountsPay in KRW thousand exactly (A208340 202606 3,351,668.79 -> 3,351,668,790). Counted in the report.
DEFAULT_UNIT = 'local thou'


def period_from_row_date(d):
    """date row 'YYYY-MM' (or a date) -> fiscal quarter one quarter earlier, as 'YYYYMM' (FQ0 3-month lagging)."""
    if isinstance(d, (dt.datetime, dt.date)):
        y, m = d.year, d.month
    else:
        s = str(d).strip()
        y, m = int(s[:4]), int(s[5:7])
    k = y * 4 + (m - 1) // 3 - 1
    return f'{k // 4}{(k % 4) * 3 + 3:02d}'


# Positive control for the period mapping (the d - 1Q rule depends on the add-in's lagging option - Help > Option > Period):
#   NonInterestCurLiab (B101400 = AP & other payables + other current liabilities) >= v2 AccountsPay (M113200) of the same
#   (Ticker, Period). 11-09 full data: right mapping 0.9984 - shifted one quarter either way 0.630 / 0.667 -> gate 0.98.
CONTROL_MIN = 0.98


def payables_control(df, root):
    bs = pq.read_table(f'{root}/.cache/qw_fund_v2/FundV2_BS.parquet', columns=['Ticker', 'Period', 'Item', 'Value'],
                       filters=[('Item', '==', 'AccountsPay')]).to_pandas()
    bs['Period'] = bs['Period'].astype(str)
    nil = df.loc[df['Item'] == 'NonInterestCurLiab', ['Ticker', 'Period', 'Value']]
    j = nil.merge(bs[['Ticker', 'Period', 'Value']].rename(columns={'Value': 'ap'}), on=['Ticker', 'Period'])
    j = j[j['ap'].abs() > 0]
    share = float((j['Value'] >= j['ap'] - 1000).mean()) if len(j) else float('nan')
    return {'n': int(len(j)), 'share_nil_ge_ap': round(share, 5), 'min': CONTROL_MIN}


def read_sheet(ws, code_expected, item, expect_date):
    rows = list(ws.iter_rows(min_row=1, values_only=True))
    if len(rows) < 15:
        raise SystemExit(f'[tax-ingest] {ws.title}: fewer than 15 rows')
    b1 = str(rows[0][1] or '')
    code = str(rows[9][1] or '').strip()
    base = str(rows[11][1] or '').strip()
    if code != code_expected:
        raise SystemExit(f'[tax-ingest] {ws.title}: B10 {code!r} != {code_expected!r}')
    if base != 'FQ0':
        raise SystemExit(f'[tax-ingest] {ws.title}: B12 {base!r} != FQ0')
    if expect_date and expect_date not in b1:
        raise SystemExit(f'[tax-ingest] {ws.title}: B1 {b1!r} has no {expect_date} (not refreshed)')
    tickers = list(rows[7][1:])
    units = list(rows[10][1:])
    recs, n_text, unknown_units, defaulted = [], 0, set(), set()
    for row in rows[14:]:
        d = row[0]
        if d is None or str(d).strip() == '':
            break
        per = period_from_row_date(d)
        for j, v in enumerate(row[1:]):
            if v is None or v == '':
                continue
            t = tickers[j] if j < len(tickers) else None
            if not t:
                continue
            if isinstance(v, str):
                n_text += 1
                continue
            u = str(units[j] or '').strip().lower()
            if not u:
                u = DEFAULT_UNIT
                defaulted.add(str(t))
            if u not in UNIT_SCALE:
                unknown_units.add(u)
                continue
            recs.append((str(t), per, item, float(v) * UNIT_SCALE[u]))
    if unknown_units:
        raise SystemExit(f'[tax-ingest] {ws.title}: numeric cells under unknown units {sorted(unknown_units)}')
    if not recs:
        raise SystemExit(f'[tax-ingest] {ws.title}: no numeric cells')
    df = pd.DataFrame(recs, columns=['Ticker', 'Period', 'Item', 'Value'])
    info = {'b1': b1, 'code': code, 'base': base, 'numeric': len(df), 'text_dropped': n_text,
            'tickers': int(df['Ticker'].nunique()), 'periods': [df['Period'].min(), df['Period'].max()],
            'unit_defaulted_tickers': sorted(defaulted)}
    return df, info


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', required=True)
    ap.add_argument('--book', default='')
    ap.add_argument('--expect-date', default=dt.date.today().isoformat())
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()
    root = a.root.replace('\\', '/')
    book = a.book or f'{root}/03_Universe/Fundamental_v2/FundV2_TAX_TS.xlsx'
    out = f'{root}/.cache/qw_fund_v2/FundV2_TAX.parquet'
    rep_path = f'{root}/.cache/qw_fund_v2/FundV2_TAX_ingest_report.json'
    wb = load_workbook(book, read_only=True, data_only=True)
    missing = [s for s in SHEETS if s not in wb.sheetnames]
    if missing:
        raise SystemExit(f'[tax-ingest] sheets missing: {missing}')
    parts, report = [], {'book': book, 'expect_date': a.expect_date, 'sheets': {}}
    for s, (code, item) in SHEETS.items():
        df, info = read_sheet(wb[s], code, item, a.expect_date)
        parts.append(df)
        report['sheets'][s] = {'item': item, **info}
        print(f'[tax-ingest] {s} -> {item}: numeric {info["numeric"]:,} . text dropped {info["text_dropped"]:,} . '
              f'tickers {info["tickers"]:,} . periods {info["periods"][0]}~{info["periods"][1]}')
    wb.close()
    new = pd.concat(parts, ignore_index=True)
    dup = int(new.duplicated(['Ticker', 'Period', 'Item']).sum())
    if dup:
        raise SystemExit(f'[tax-ingest] duplicated (Ticker, Period, Item) rows: {dup}')
    now = dt.datetime.now().strftime('%Y-%m-%dT%H:%M:%S')
    new['Text'] = pd.Series([None] * len(new), dtype=object)
    new['first_fetched_at'] = now
    new['last_fetched_at'] = now
    if os.path.exists(out):
        old = pd.read_parquet(out, columns=['Ticker', 'Period', 'Item', 'first_fetched_at'])
        new = new.merge(old.rename(columns={'first_fetched_at': '_ff'}), on=['Ticker', 'Period', 'Item'], how='left')
        new['first_fetched_at'] = new['_ff'].fillna(new['first_fetched_at'])
        new = new.drop(columns=['_ff'])
        report['previous_rows'] = int(len(old))
    new = new.sort_values(['Ticker', 'Period', 'Item'], kind='mergesort').reset_index(drop=True)[[f.name for f in SCHEMA]]
    ctl = payables_control(new, root)
    report['payables_control'] = ctl
    print(f'[tax-ingest] payables control: NonInterestCurLiab >= v2 AccountsPay {ctl["share_nil_ge_ap"]} (n {ctl["n"]:,} . min {CONTROL_MIN})')
    if not ctl['n'] or not ctl['share_nil_ge_ap'] >= CONTROL_MIN:
        raise SystemExit(f'[tax-ingest] payables control failed {ctl} - period mapping (FQ0 lagging option) or units changed; nothing written')
    report.update({'rows': int(len(new)), 'tickers': int(new['Ticker'].nunique()), 'items': sorted(new['Item'].unique()),
                   'written_at': now, 'dry_run': bool(a.dry_run), 'output': out})
    print(f'[tax-ingest] total rows {len(new):,} . tickers {new["Ticker"].nunique():,}')
    if a.dry_run:
        print(json.dumps(report, ensure_ascii=False, indent=1, default=str))
        return 0
    tmp = out + '.tmp'
    pq.write_table(pa.Table.from_pandas(new, schema=SCHEMA, preserve_index=False), tmp)
    os.replace(tmp, out)
    with open(rep_path, 'w', encoding='utf-8') as f:
        json.dump(report, f, ensure_ascii=False, indent=1, default=str)
    print(f'[tax-ingest] wrote {out} . report {rep_path}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
