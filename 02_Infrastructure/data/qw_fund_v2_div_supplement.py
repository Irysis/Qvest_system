"""qw_fund_v2_div_supplement.py - Time Series (Company) books for the cells the Peer Analysis books cannot give ->
the parent raw v2 DBs (.cache/qw_fund_v2/FundV2_META.parquet . FundV2_INFO.parquet)           (2026-11-23)

Decision: Dohoon 11-23 'jedaero doen kwonti setting-euro (ga)an silhaeng' (re-fetch) . '1beon baedang suri banyeong' (bring the
  repair into the infrastructure).
Why: the Peer Analysis books FundV2_META . FundV2_INFO return '#INVALID OPTION' in the period columns 201209..201312 of the five
  dividend sheets (CashDivTotal . CashDivCommon . AdjDPS . AdjDPSFinal . AdjDPSInterim) whatever the code suffix ('.M' . none .
  '.IP' - 11-23 test). So the raw DBs, fund_v2_quarterly, the fundamentals caches and the dividend factors have no dividend rows
  for those six quarters (trailing-four-quarter sums are missing 2013Q1..2014Q3). The same items in a Time Series (Company)
  sheet with Base Date FQ0 - the layout of the tax B codes (qw_fund_v2_tax_ts.ps1) - return values: no error cell, and in the
  quarters the Peer books do have, the two layouts agree (amounts 132/132 . 126/126 cells; per-share items 124/126 - the two
  off cells are one ticker whose adjustment factor changed between the two fetch days).
What: the supplement books and their (sheet -> item . code . kind . parent DB) map live in the registry
  (02_Infrastructure/data/qw_updatefile_registry.json :: fundamentals_v2.ts_supplements). For each sheet: B10 code . row 12
  Base Date = FQ0 . units -> date row d -> Period with the rule of the tax ingest (qw_fund_v2_tax_ingest.period_from_row_date -
  the fiscal quarter that contains d - 3 months, labelled by the calendar quarter in which it ends; fiscal year-end months from
  fiscal_month.parquet) -> only the supplement periods are kept -> merged into the parent parquet of the item with the shared
  window_merge (rows outside the window untouched . first_fetched_at = the book's B1 stamp . changed values -> revisions.parquet).
  Amount items: unit 'local thou' / 'krw thou' -> x1000 = KRW (the unit of the Peer DBs). Per-share items: as they are (KRW per
  share - the unit row of a per-share sheet is not reliable: it reads 'Local thou' for most columns).
Not supplemented: AdjDPSInterim (M423000). In the Time Series layout that code gives a value on the fiscal year-end row only
  (mostly 0) - not the quarterly values of the Peer DB - so it is not taken. In the Peer DB AdjDPSInterim = AdjDPS wherever both
  exist (1,056/1,056 non-zero cells), i.e. it could be derived - a decision that is not made here.
Gates (exit 3, nothing written): registry entry . every book and sheet present . B10 code . B12 FQ0 . known units for amount
  items . numeric cells . the date rows cover every supplement period for every class of fiscal year-end month . a fiscal year-end
  month for every ticker with a non-zero value (tickers with only zeros and no fiscal month are dropped and counted) . two date
  rows on one (Ticker, Period, Item) carry the same value . fill per (Item, Period) >= FILL_MIN . overlap control: in the periods
  next to the window that the book covers and the parent already has, the share of equal values among the cells where either
  side is non-zero >= OVERLAP_MIN[kind] with at least OVERLAP_MIN_N such cells (catches a changed lagging option, a wrong unit or
  a wrong code) . the parent parquet exists.
Protection: the Peer ingest (qw_fund_v2_ingest.py) leaves the supplement cells alone - a full-book re-ingest would otherwise delete
  these rows (the Peer book has no values there) - see protected_cells() there.
After a write the downstream chain is NOT run here: fund_v2_quarterly + the fundamentals caches (fundamental_produce_v2.R) ->
  the affected factors (run_factor_subset_repair.sh + daily phase F) -> the factor DB vintage ledger. Run them as one repair.
Exit: 0 written (or dry-run passed) . 3 gate refused (nothing written) . 1 error.
Usage: python qw_fund_v2_div_supplement.py --root <project root> [--name FundV2_DIV_201209_201312] [--dry-run]
"""
import argparse
import datetime as dt
import importlib.util
import json
import os
import re
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
from openpyxl import load_workbook

UNIT_SCALE = {'local thou': 1e3, 'krw thou': 1e3}      # amount items (the Peer DBs hold KRW)
OVERLAP_MIN = {'amount': 0.98, 'per_share': 0.95}      # 11-23 real books: amounts 1.000 . per-share 0.984 (one ticker's adjustment factor)
OVERLAP_MIN_N = 20                                     # non-zero cells the overlap control needs (11-23: 126~132 per item)
FM_CLASSES = (12, 11, 10)                              # one fiscal year-end month per class of fiscal quarter-end months (mod 3)
DEFAULT_NAME = 'FundV2_DIV_201209_201312'


class Refused(Exception):
    """A gate refused the books - exit 3, nothing written."""


def load_sibling(name):
    """A module next to this file (one implementation of the period rule and of the window merge for every v2 DB)."""
    p = Path(__file__).resolve().parent / f'{name}.py'
    spec = importlib.util.spec_from_file_location(name, p)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def read_sheet(ws, sh, tax):
    rows = list(ws.iter_rows(min_row=1, values_only=True))
    if len(rows) < 15:
        raise Refused(f'{ws.title}: fewer than 15 rows')
    b1, code = str(rows[0][1] or ''), str(rows[9][1] or '').strip()
    if code != sh['code']:
        raise Refused(f'{ws.title}: B10 {code!r} != {sh["code"]!r}')
    tickers = [str(t).strip() if t is not None else '' for t in rows[7][1:]]
    n = max((i for i, t in enumerate(tickers) if t), default=-1) + 1
    if n == 0:
        raise Refused(f'{ws.title}: no ticker in row 8')
    base = {str(v).strip() for v in rows[11][1:1 + n]}
    if base != {'FQ0'}:
        raise Refused(f'{ws.title}: row 12 Base Date {sorted(base)[:3]} != FQ0')
    units = [str(u or '').strip().lower() for u in rows[10][1:1 + n]]
    recs, row_dates, n_text, bad_units = [], [], 0, set()
    for row in rows[14:]:
        d = row[0]
        if d is None or str(d).strip() == '':
            break
        lab = '%04d-%02d' % tax.row_month(d)
        row_dates.append(lab)
        for j, v in enumerate(row[1:1 + n]):
            if v is None or v == '' or not tickers[j]:
                continue
            if isinstance(v, str):
                n_text += 1
                continue
            if sh['kind'] == 'amount':
                if units[j] not in UNIT_SCALE:
                    bad_units.add(units[j])
                    continue
                recs.append((tickers[j], lab, sh['item'], float(v) * UNIT_SCALE[units[j]]))
            else:
                recs.append((tickers[j], lab, sh['item'], float(v)))
    if bad_units:
        raise Refused(f'{ws.title}: numeric cells of an amount item under unknown units {sorted(bad_units)}')
    if not recs:
        raise Refused(f'{ws.title}: no numeric cells')
    m = re.search(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', b1)
    return pd.DataFrame(recs, columns=['Ticker', 'RowDate', 'Item', 'Value']), {'code': code, 'stamp': m.group(1) if m else None, 'numeric': len(recs),
                                                                               'text_dropped': n_text, 'row_dates': row_dates}


def run(a):
    root = a.root.replace('\\', '/')
    tax, core = load_sibling('qw_fund_v2_tax_ingest'), load_sibling('qw_fund_v2_ingest')
    reg = json.loads(Path(f'{root}/02_Infrastructure/data/qw_updatefile_registry.json').read_text(encoding='utf-8'))
    fv = reg.get('fundamentals_v2', {})
    sup = next((s for s in fv.get('ts_supplements', []) if s.get('name') == a.name), None)
    if not sup:
        raise Refused(f'registry fundamentals_v2.ts_supplements has no {a.name!r}')
    periods = sorted(sup['periods'])
    fv_dir = fv.get('dir', '03_Universe/Fundamental_v2')
    report = {'name': a.name, 'periods': periods, 'sheets': {}, 'dry_run': bool(a.dry_run)}
    parts, stamps, parent_of, kind_of = [], [], {}, {}
    for b in sup['books']:
        book = f'{root}/{fv_dir}/{b["file"]}'
        if not os.path.exists(book):
            raise Refused(f'book missing: {book}')
        wb = load_workbook(book, read_only=True, data_only=True)
        try:
            for sh in b['sheets']:
                if sh['sheet'] not in wb.sheetnames:
                    raise Refused(f'{b["file"]}: sheet {sh["sheet"]!r} missing')
                df, info = read_sheet(wb[sh['sheet']], sh, tax)
                cover = {f % 3: {tax.period_from_row_date(d, f) for d in info['row_dates']} for f in FM_CLASSES}
                short = {c: sorted(set(periods) - ps) for c, ps in cover.items() if set(periods) - ps}
                if short:
                    raise Refused(f'{b["file"]}/{sh["sheet"]}: the date rows do not cover the supplement periods {short} (fiscal year-end class: periods)')
                parts.append(df)
                parent_of[sh['item']], kind_of[sh['item']] = sh['parent'], sh['kind']
                if info['stamp']:
                    stamps.append(info['stamp'])
                report['sheets'][f'{b["file"]}/{sh["sheet"]}'] = {'item': sh['item'], **{k: v for k, v in info.items() if k != 'row_dates'},
                                                                 'rows': [info['row_dates'][0], info['row_dates'][-1], len(info['row_dates'])]}
        finally:
            wb.close()
    new = pd.concat(parts, ignore_index=True)
    if new.duplicated(['Ticker', 'RowDate', 'Item']).any():
        raise Refused('duplicated (Ticker, date row, Item) cells')
    fms = tax.load_fiscal_months(root)
    fmv = new['Ticker'].map(fms)
    nofm = new[fmv.isna()]
    if (nofm['Value'] != 0).any():
        raise Refused(f'no fiscal year-end month (fiscal_month.parquet) for tickers with non-zero values: {sorted(nofm.loc[nofm["Value"] != 0, "Ticker"].unique())[:10]}')
    report['tickers_without_fiscal_month_dropped'] = sorted(nofm['Ticker'].unique())
    new, fmv = new[fmv.notna()], fmv[fmv.notna()].astype(int)
    key = list(zip(new['RowDate'], fmv))
    lab = {k: tax.period_from_row_date(*k) for k in set(key)}
    new = new.assign(Period=[lab[k] for k in key]).drop(columns='RowDate')
    keys = ['Ticker', 'Period', 'Item']
    dup = new.duplicated(keys, keep=False)
    if dup.any() and (new[dup].groupby(keys)['Value'].nunique() > 1).any():
        raise Refused('two date rows put different values on one (Ticker, Period, Item)')
    new = new.drop_duplicates(keys).reset_index(drop=True)
    fetched = max(stamps).replace(' ', 'T') if stamps else dt.datetime.now().strftime('%Y-%m-%dT%H:%M:%S')

    out_dir = Path(f'{root}/.cache/qw_fund_v2')
    results, revs_all, counts = {}, [], {}
    for parent in sorted(set(parent_of.values())):
        items = sorted(i for i, p in parent_of.items() if p == parent)
        path = out_dir / f'{parent}.parquet'
        if not path.exists():
            raise Refused(f'parent {path} missing')
        old = pq.read_table(path).to_pandas()
        for it in items:
            x = new[(new['Item'] == it) & ~new['Period'].isin(periods)]
            o = old[(old['Item'] == it) & old['Period'].isin(sorted(x['Period'].unique()))]
            m = x.merge(o[['Ticker', 'Period', 'Value']], on=['Ticker', 'Period'], suffixes=('', '_peer'))
            nz = (m['Value'] != 0) | (m['Value_peer'] != 0)
            same = np.isclose(m['Value'], m['Value_peer'], rtol=1e-6, atol=0.5) & nz
            share = float(same.sum() / nz.sum()) if nz.sum() else float('nan')
            off = m[nz & ~same]
            report.setdefault('overlap_control', {})[it] = {'periods': sorted(m['Period'].unique()), 'cells': int(len(m)), 'nonzero': int(nz.sum()), 'same': int(same.sum()),
                                                            'share': share, 'off': [[r.Ticker, r.Period, float(r.Value), float(r.Value_peer)] for r in off.head(10).itertuples()]}
            print(f'[div-supplement] overlap control {it}: {int(same.sum())}/{int(nz.sum())} equal among non-zero cells (share {share:.3f} . min {OVERLAP_MIN[kind_of[it]]})')
            if not (nz.sum() >= OVERLAP_MIN_N and share >= OVERLAP_MIN[kind_of[it]]):
                raise Refused(f'overlap control failed for {it}: {int(same.sum())}/{int(nz.sum())} (min share {OVERLAP_MIN[kind_of[it]]} . min cells {OVERLAP_MIN_N}) - '
                              'lagging option, unit or code changed?')
        add = new[new['Item'].isin(items) & new['Period'].isin(periods)].copy()
        fill = add.groupby(['Item', 'Period']).size()
        thin = [f'{i}|{p} {int(fill.get((i, p), 0))}' for i in items for p in periods if fill.get((i, p), 0) < core.FILL_MIN]
        if thin:
            raise Refused(f'thin (Item, Period) cells in the supplement window: {thin[:6]}')
        add['Text'] = pd.Series([None] * len(add), dtype=object)
        win = {(i, p) for i in items for p in periods}
        res, revs, cnt = core.window_merge(old, add[['Ticker', 'Period', 'Item', 'Value', 'Text']], win, a.name, fetched)
        results[parent], counts[parent] = (path, res), {**cnt, 'rows_before': int(len(old)), 'rows_after': int(len(res)), 'items': items}
        revs_all += revs
        print(f'[div-supplement] {parent}: items {items} . new {cnt["new"]:,} . changed {cnt["changed"]:,} . deleted {cnt["deleted"]:,} . rows {len(old):,} -> {len(res):,}')
    report.update({'counts': counts, 'fetched': fetched, 'written_at': dt.datetime.now().strftime('%Y-%m-%dT%H:%M:%S')})
    if a.dry_run:
        print('[div-supplement] dry-run - nothing written')
        return 0
    schema = pa.schema([('Ticker', pa.string()), ('Period', pa.string()), ('Item', pa.string()), ('Value', pa.float64()), ('Text', pa.string()),
                        ('first_fetched_at', pa.string()), ('last_fetched_at', pa.string())])
    for parent, (path, res) in results.items():
        tab = pa.Table.from_pandas(res[[f.name for f in schema]], schema=schema, preserve_index=False)
        core.atomic_write(path, lambda p, tab=tab: pq.write_table(tab, p))
    core.write_revisions(out_dir / 'revisions.parquet', revs_all)
    with open(out_dir / 'FundV2_DIV_supplement_report.json', 'w', encoding='utf-8') as f:
        json.dump(report, f, ensure_ascii=False, indent=1, default=str)
    print(f'[div-supplement] wrote {[str(p) for p, _ in results.values()]} . report {out_dir / "FundV2_DIV_supplement_report.json"}')
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', required=True)
    ap.add_argument('--name', default=DEFAULT_NAME)
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()
    try:
        return run(a)
    except Refused as e:
        print(f'[div-supplement] refused (nothing written): {e}')
        return 3


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001
        print(f'[div-supplement] error: {e!r}')
        sys.exit(1)
