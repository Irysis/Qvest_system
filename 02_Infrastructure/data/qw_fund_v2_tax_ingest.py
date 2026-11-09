"""qw_fund_v2_tax_ingest.py - Time Series (Company) tax B-code book -> .cache/qw_fund_v2/FundV2_TAX.parquet (2026-11-09)

Decision: Dohoon 11-09 'jigeum sujip' - collect the four tax-related IFRS B codes for all firms from 2000Q1 into the
fundamentals DB v2 (raw DB FundV2_TAX); same day 'beobinse B code pateu-do jeonggi gaengsin-e neocha' - weekly update.
Current tax payable TXP = OtherCurLiabInclTax - NonInterestCurLiab + TradePayables (B201700 - B101400 + B201600, glossary
definitions; DART FY2015~2025 17,829 firm-years exact 97.0%).

Modes
  full    (default) book = 03_Universe/Fundamental_v2/FundV2_TAX_TS.xlsx (2000~) -> report FundV2_TAX_ingest_report.json.
  window  (--window) book = FundV2_TAX_TS_upd.xlsx (last N quarters, built by ops/qw_fund_v2_tax_ts.ps1 -WindowQuarters;
          the weekly update ops/qw_fund_v2_update.ps1) -> report FundV2_TAX_upd_report.json.
  Both replace the book's (Item, Period) window of the parent parquet with qw_fund_v2_ingest.window_merge (the same
  function as the Peer Analysis DBs): unchanged values keep first_fetched_at . value changes / deletions ->
  .cache/qw_fund_v2/revisions.parquet (Db = FundV2_TAX / FundV2_TAX_upd) . rows outside the window kept . new / changed /
  deleted counts in the report. fetched = the latest B1 stamp (when Quantiwise produced the values).
Book layout (Time Series (Company)): B1 'Last Update : <ts>' . row 8 ticker codes (from column B) . B10 item code .
row 11 unit per column . row 12 Base Date (FQ0) . row 14 item names . rows 15.. column A = date 'YYYY-MM'.
Mapping (official XLA manual p.58 / p.64): with Base Date FQ0 (default 3-month lagging) the value on date row d is the
fiscal quarter d - 1Q. Units 'Local thou' / 'KRW thou' -> x1000 = KRW.
Gates (exit 3, nothing written): every sheet present . B10 code . B12 == 'FQ0' . B1 date == --expect-date (default today) .
numeric cells > 0 per sheet . a numeric cell under an unknown (non-blank) unit . payables positive control
(NonInterestCurLiab >= v2 AccountsPay share >= 0.98 - catches a changed lagging option or unit) . the date rows are the
same on every sheet and one contiguous quarterly run (stale rows left from the template break it) . fill drop per
(Item, Period) vs the parent (qw_fund_v2_ingest.FILL_RATIO / FILL_MIN - a partial refresh) . window mode: the parent
exists . the rows start at the window start of --expect-date (expected_window = the Peer update DBs' rule) or one quarter
before - the add-in starts at the last quarter-end on or before B5 (From 20000101 -> first row 1999-12 . 20140101 ->
2013-12), so the collector's B5 gives one earlier row, which is dropped; a later start or more earlier rows = B5 not
applied or wrong . they end at the window end or one quarter before (the last row is the month of the add-in's last
date CPD-1TD - still in the previous quarter on a quarter-end day or the first days of a quarter; a truncated refresh
breaks it). A blank unit =
add-in default for financial items (KRW thousand, manual p.63) - those tickers are listed in the report. Text cells ('#INVALID OPTION' = financial firms;
B codes are defined for non-financial firms) are dropped and counted.
Output schema = the other raw v2 DBs: Ticker, Period (YYYYMM), Item, Value (KRW), Text, first_fetched_at, last_fetched_at.
Exit: 0 written . 3 gate refused (nothing written) . 1 error.
Usage: python qw_fund_v2_tax_ingest.py --root <project root> [--window] [--book <xlsx>] [--expect-date YYYY-MM-DD] [--dry-run]
"""
import argparse
import datetime as dt
import importlib.util
import json
import os
import re
import sys
from pathlib import Path

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
# Positive control for the period mapping (the d - 1Q rule depends on the add-in's lagging option - Help > Option > Period):
#   NonInterestCurLiab (B101400 = AP & other payables + other current liabilities) >= v2 AccountsPay (M113200) of the same
#   (Ticker, Period). 11-09 full data: right mapping 0.9984 - shifted one quarter either way 0.630 / 0.667 -> gate 0.98.
CONTROL_MIN = 0.98
UPD_DB = 'FundV2_TAX_upd'


class Refused(Exception):
    """A gate refused the book - exit 3, nothing written."""


def load_core():
    """qw_fund_v2_ingest.py next to this file (window_merge . write_revisions . atomic_write . FILL_RATIO . FILL_MIN) - one implementation for
    every v2 DB. Located by code path, not by --root (a data root, e.g. a test sandbox, has no code)."""
    p = Path(__file__).resolve().parent / 'qw_fund_v2_ingest.py'
    spec = importlib.util.spec_from_file_location('qw_fund_v2_ingest', p)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def _qk(k):
    """quarter index k (= year * 4 + quarter - 1) -> fiscal quarter 'YYYYMM'."""
    return f'{k // 4}{(k % 4) * 3 + 3:02d}'


def _k(period):
    """fiscal quarter 'YYYYMM' -> quarter index."""
    return int(period[:4]) * 4 + int(period[4:]) // 3 - 1


def period_from_row_date(d):
    """date row 'YYYY-MM' (or a date) -> fiscal quarter one quarter earlier, as 'YYYYMM' (FQ0 3-month lagging)."""
    if isinstance(d, (dt.datetime, dt.date)):
        y, m = d.year, d.month
    else:
        s = str(d).strip()
        y, m = int(s[:4]), int(s[5:7])
    return _qk(y * 4 + (m - 1) // 3 - 1)


def expected_window(today, n):
    """(first, last) fiscal quarters of the last n quarters ending at the last quarter-end month <= today - the rule of
    qw_fundamental_book.ps1 (period_to 'auto' + window_quarters) and of qw_fund_v2_tax_ts.ps1 Window-From (B5)."""
    qm = [m for m, d in ((3, 31), (6, 30), (9, 30), (12, 31)) if (today.month, today.day) >= (m, d)]
    k = today.year * 4 + (qm[-1] // 3 - 1 if qm else -1)
    return _qk(k - n + 1), _qk(k)


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
        raise Refused(f'{ws.title}: fewer than 15 rows')
    b1 = str(rows[0][1] or '')
    code = str(rows[9][1] or '').strip()
    base = str(rows[11][1] or '').strip()
    if code != code_expected:
        raise Refused(f'{ws.title}: B10 {code!r} != {code_expected!r}')
    if base != 'FQ0':
        raise Refused(f'{ws.title}: B12 {base!r} != FQ0')
    if expect_date and expect_date not in b1:
        raise Refused(f'{ws.title}: B1 {b1!r} has no {expect_date} (not refreshed)')
    tickers = list(rows[7][1:])
    units = list(rows[10][1:])
    recs, row_periods, n_text, unknown_units, defaulted = [], [], 0, set(), set()
    for row in rows[14:]:
        d = row[0]
        if d is None or str(d).strip() == '':
            break
        per = period_from_row_date(d)
        row_periods.append(per)
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
        raise Refused(f'{ws.title}: numeric cells under unknown units {sorted(unknown_units)}')
    if not recs:
        raise Refused(f'{ws.title}: no numeric cells')
    df = pd.DataFrame(recs, columns=['Ticker', 'Period', 'Item', 'Value'])
    m = re.search(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', b1)
    info = {'b1': b1, 'stamp': m.group(1) if m else None, 'code': code, 'base': base, 'numeric': len(df), 'text_dropped': n_text,
            'tickers': int(df['Ticker'].nunique()), 'periods': [df['Period'].min(), df['Period'].max()],
            'row_periods': row_periods, 'unit_defaulted_tickers': sorted(defaulted)}
    return df, info


def read_book(book, expect_date, report):
    wb = load_workbook(book, read_only=True, data_only=True)
    try:
        missing = [s for s in SHEETS if s not in wb.sheetnames]
        if missing:
            raise Refused(f'sheets missing: {missing}')
        parts, rows_by_sheet = [], {}
        for s, (code, item) in SHEETS.items():
            df, info = read_sheet(wb[s], code, item, expect_date)
            parts.append(df)
            rows_by_sheet[s] = tuple(info.pop('row_periods'))
            report['sheets'][s] = {'item': item, **info}
            print(f'[tax-ingest] {s} -> {item}: numeric {info["numeric"]:,} . text dropped {info["text_dropped"]:,} . '
                  f'tickers {info["tickers"]:,} . periods {info["periods"][0]}~{info["periods"][1]}')
    finally:
        wb.close()
    new = pd.concat(parts, ignore_index=True)
    dup = int(new.duplicated(['Ticker', 'Period', 'Item']).sum())
    if dup:
        raise Refused(f'duplicated (Ticker, Period, Item) rows: {dup}')
    return new, rows_by_sheet


def run(a):
    root = a.root.replace('\\', '/')
    out = f'{root}/.cache/qw_fund_v2/FundV2_TAX.parquet'
    reg = json.loads(Path(f'{root}/02_Infrastructure/data/qw_updatefile_registry.json').read_text(encoding='utf-8'))
    ts = next((d for d in reg.get('fundamentals_v2', {}).get('ts_dbs', []) if d.get('name') == 'FundV2_TAX'), {})
    upd = ts.get('update') or {}
    fv_dir = reg.get('fundamentals_v2', {}).get('dir', '03_Universe/Fundamental_v2')
    book = a.book or f'{root}/{fv_dir}/' + (upd.get('file', 'FundV2_TAX_TS_upd.xlsx') if a.window else ts.get('file', 'FundV2_TAX_TS.xlsx'))
    report = {'mode': 'window' if a.window else 'full', 'book': book, 'expect_date': a.expect_date, 'sheets': {}}
    new, rows_by_sheet = read_book(book, a.expect_date, report)
    ctl = payables_control(new, root)
    report['payables_control'] = ctl
    print(f'[tax-ingest] payables control: NonInterestCurLiab >= v2 AccountsPay {ctl["share_nil_ge_ap"]} (n {ctl["n"]:,} . min {CONTROL_MIN})')
    if not ctl['n'] or not ctl['share_nil_ge_ap'] >= CONTROL_MIN:
        raise Refused(f'payables control failed {ctl} - period mapping (FQ0 lagging option) or units changed')
    new['Text'] = pd.Series([None] * len(new), dtype=object)
    stamps = [s['stamp'] for s in report['sheets'].values() if s.get('stamp')]
    fetched = max(stamps).replace(' ', 'T') if stamps else dt.datetime.now().strftime('%Y-%m-%dT%H:%M:%S')
    if len(set(rows_by_sheet.values())) != 1:
        raise Refused('date rows differ between sheets')
    periods = list(next(iter(rows_by_sheet.values())))
    ks = [_k(p) for p in periods]
    if any(y - x != 1 for x, y in zip(ks, ks[1:])):
        raise Refused(f'date rows are not one contiguous quarterly run ({len(ks)} rows {periods[0]}..{periods[-1]})'
                      ' - stale rows left from the template?')
    if a.window:
        wq = int(a.window_quarters or upd.get('window_quarters') or 8)
        today = dt.date.fromisoformat(a.expect_date) if a.expect_date else dt.date.today()
        first, last = expected_window(today, wq)
        kf, kl = _k(first), _k(last)
        before = [p for p, k in zip(periods, ks) if k < kf]
        if ks[0] > kf or len(before) > 1:
            raise Refused(f'date rows start at quarter {periods[0]} - expected the window start {first} or one quarter before '
                          f'({wq} quarters as of {today}; B5 not applied or wrong?)')
        if ks[-1] not in (kl - 1, kl):
            raise Refused(f'last date row = quarter {periods[-1]} - expected {last} or one quarter before (truncated refresh?)')
        if not os.path.exists(out):
            raise Refused(f'parent {out} missing - run the full ingest first')
        report['rows_before_window_dropped'] = before
        periods = [p for p, k in zip(periods, ks) if k >= kf]
        if not periods:
            raise Refused(f'no date row inside the window {first}..{last}')
        new = new[new['Period'].isin(periods)]
    # both modes replace the book's (Item, Period) window of the parent with the shared window_merge (Peer v2 DBs): unchanged
    # values keep first_fetched_at . changed / deleted -> revisions.parquet (Db = FundV2_TAX full . FundV2_TAX_upd window)
    core = load_core()
    new = new[['Ticker', 'Period', 'Item', 'Value', 'Text']]
    if os.path.exists(out):
        old = pq.read_table(out).to_pandas()
        # fill drop vs the parent (same rule and constants as the Peer Analysis DBs - qw_fund_v2_ingest G3)
        pc = old[old['Period'].isin(periods)].groupby(['Item', 'Period']).size()
        nc = new.groupby(['Item', 'Period']).size()
        drops = [f'{i}|{p} {int(pc[(i, p)])}->{int(nc.get((i, p), 0))}' for (i, p) in pc.index
                 if pc[(i, p)] >= core.FILL_MIN and nc.get((i, p), 0) < core.FILL_RATIO * pc[(i, p)]]
        if drops:
            raise Refused(f'fill drop vs parent {len(drops)} cells: ' + '; '.join(drops[:5]))
        win = {(it, p) for _, it in SHEETS.values() for p in periods}
        res, revs, cnt = core.window_merge(old, new, win, UPD_DB if a.window else 'FundV2_TAX', fetched)
        report['previous_rows'] = int(len(old))
    else:
        res = new.assign(first_fetched_at=fetched, last_fetched_at=fetched).sort_values(core.KEYS, kind='stable').reset_index(drop=True)
        revs, cnt = [], {'new': int(len(res)), 'changed': 0, 'deleted': 0}
    report.update({'periods': [periods[0], periods[-1], len(periods)], 'counts': cnt})
    print(f'[tax-ingest] {report["mode"]} {periods[0]}~{periods[-1]} ({len(periods)} quarters) . new {cnt["new"]:,} . '
          f'changed {cnt["changed"]:,} . deleted {cnt["deleted"]:,}')
    rep_path = f'{root}/.cache/qw_fund_v2/' + ('FundV2_TAX_upd_report.json' if a.window else 'FundV2_TAX_ingest_report.json')
    report.update({'rows': int(len(res)), 'tickers': int(res['Ticker'].nunique()), 'items': sorted(res['Item'].unique()),
                   'fetched': fetched, 'written_at': dt.datetime.now().strftime('%Y-%m-%dT%H:%M:%S'), 'dry_run': bool(a.dry_run), 'output': out})
    print(f'[tax-ingest] total rows {len(res):,} . tickers {res["Ticker"].nunique():,}')
    if a.dry_run:
        print('[tax-ingest] dry-run - nothing written')
        return 0
    tab = pa.Table.from_pandas(res[[f.name for f in SCHEMA]], schema=SCHEMA, preserve_index=False)
    core.atomic_write(Path(out), lambda p: pq.write_table(tab, p))
    if 'previous_rows' in report:
        core.write_revisions(Path(f'{root}/.cache/qw_fund_v2/revisions.parquet'), revs)
    with open(rep_path, 'w', encoding='utf-8') as f:
        json.dump(report, f, ensure_ascii=False, indent=1, default=str)
    print(f'[tax-ingest] wrote {out} . report {rep_path}')
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', required=True)
    ap.add_argument('--book', default='')
    ap.add_argument('--window', action='store_true')
    ap.add_argument('--window-quarters', type=int, default=0)
    ap.add_argument('--expect-date', default=dt.date.today().isoformat())
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()
    try:
        return run(a)
    except Refused as e:
        print(f'[tax-ingest] refused (nothing written): {e}')
        return 3


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001
        print(f'[tax-ingest] error: {e!r}')
        sys.exit(1)
