"""qw_fund_v2_tax_ingest.py - Time Series (Company) tax B-code book -> .cache/qw_fund_v2/FundV2_TAX.parquet (2026-11-09)

Decision: Dohoon 11-09 'jigeum sujip' - collect the four tax-related IFRS B codes for all firms from 2000Q1 into the
fundamentals DB v2 (raw DB FundV2_TAX); same day 'beobinse B code pateu-do jeonggi gaengsin-e neocha' - weekly update;
same day 'jigeum gochyeo' - period labels by each firm's fiscal year-end month (Mapping).
Current tax payable TXP = OtherCurLiabInclTax - NonInterestCurLiab + TradePayables (B201700 - B101400 + B201600, glossary
definitions; DART FY2015~2025 17,829 firm-years exact 97.0%).

Modes
  full    (default) book = 03_Universe/Fundamental_v2/FundV2_TAX_TS.xlsx (2000~) -> report FundV2_TAX_ingest_report.json.
  window  (--window) book = FundV2_TAX_TS_upd.xlsx (last N quarters, built by ops/qw_fund_v2_tax_ts.ps1 -WindowQuarters;
          the weekly update ops/qw_fund_v2_update.ps1) -> report FundV2_TAX_upd_report.json.
  Both replace the (Item, Period) window the book covers - per class of fiscal year-end month (Mapping), each class its
  own periods - in the parent parquet with qw_fund_v2_ingest.window_merge (the same function as the Peer Analysis DBs):
  unchanged values keep first_fetched_at . value changes / deletions ->
  .cache/qw_fund_v2/revisions.parquet (Db = FundV2_TAX / FundV2_TAX_upd) . rows outside the window kept . new / changed /
  deleted counts in the report. fetched = the latest B1 stamp (when Quantiwise produced the values).
Book layout (Time Series (Company)): B1 'Last Update : <ts>' . row 8 ticker codes (from column B) . B10 item code .
row 11 unit per column . row 12 Base Date (FQ0) . row 14 item names . rows 15.. column A = date 'YYYY-MM'.
Mapping (official XLA manual p.58 / p.64 + 11-09 measurement): with Base Date FQ0 (default 3-month lagging) date row d shows
the fiscal quarter that contains the day 3 months before d. Period = the calendar quarter in which that fiscal quarter ends,
the label of the v2 Peer Analysis DBs (FundV2_BS ...). Fiscal quarters end in the months congruent to the fiscal year-end
month mod 3 (.cache/qw_fund_v2/fiscal_month.parquet - the Peer sheets' column C, written by qw_fund_v2_ingest.py; the
weekly runner loads the Peer DBs before this step):
  Dec / Mar / Jun / Sep year-ends: fiscal quarter = calendar quarter -> Period = d - 1Q.
  other year-ends: fiscal quarters end 1-2 months after a calendar quarter end -> one quarter later than d - 1Q on the
  quarter-end rows; the last row (the month of CPD-1TD) can land on the period of the row before it with the same values
  (kept once).
  11-09: the d - 1Q rule for every firm left 12 such firms one quarter early (Hyundai Pharm Nov . Poongkang Aug ...) - a
  look-ahead (C4) once a consumer dates the period; payables control same quarter 0.47~0.83 vs one quarter later 0.97~1.00.
  Limit: fiscal_month.parquet holds the current year-end only, so a firm that changed it keeps today's rule for its whole
  history (11-09: A008320 Dec until ~2004 then Oct - its 2000~2004 quarters sit one quarter late, the safe side; a year-by-
  year scan found 24 of 45,831 ticker-years with a low same-quarter share, mostly 2001~2009).
Units 'Local thou' / 'KRW thou' -> x1000 = KRW.
Gates (exit 3, nothing written): every sheet present . B10 code . B12 == 'FQ0' . B1 date == --expect-date (default today) .
numeric cells > 0 per sheet . a numeric cell under an unknown (non-blank) unit . the date rows are the same on every sheet
and one contiguous quarterly run (stale rows left from the template break it) . fiscal_month.parquet present and a fiscal
year-end month 1~12 for every ticker with numbers . two date rows landing on one (Ticker, Period, Item) carry the same value .
payables positive control (NonInterestCurLiab >= v2 AccountsPay share >= 0.98 - catches a changed lagging option or unit) .
fill drop per (Item, Period) and fiscal year-end class vs the parent (qw_fund_v2_ingest.FILL_RATIO / FILL_MIN - a partial
refresh) . window mode: the
parent exists . the rows start at the window start of --expect-date (expected_window = the Peer update DBs' rule) or one
quarter before - the add-in starts at the last quarter-end on or before B5 (From 20000101 -> first row 1999-12 . 20140101 ->
2013-12), so the collector's B5 gives one earlier row (dropped for Dec year-ends, inside the window for off-calendar ones); a
later start or more earlier rows = B5 not applied or wrong . they end at the window end or one quarter before (the last row
is the month of the add-in's last date CPD-1TD - still in the previous quarter on a quarter-end day or the first days of a
quarter; a truncated refresh breaks it) . per-ticker alignment control on the result (a ticker whose same-quarter payables
share is low but lines up one quarter off = a wrong fiscal year-end month). A blank unit = add-in default for financial
items (KRW thousand, manual p.63) - those tickers are listed in the report. Text cells ('#INVALID OPTION' = financial firms;
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

import numpy as np
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
# Per-ticker alignment control (backstop for a wrong fiscal year-end month - the global control above cannot see a dozen
#   firms): the same share per ticker for the same quarter vs one quarter later / earlier. 11-09 with the old d - 1Q rule for
#   every firm: the 7 off-calendar fiscal-year firms with 12+ comparable quarters same 0.47~0.83 . one quarter later
#   0.97~1.00 . the other 2,976 tickers median 1.00 -> flag = same < 0.9 and a shifted share >= 0.9 (12+ quarters each).
#   Real data with this gate: old labels flagged 8 (the 7 + A039870 0.662 / 0.965); fixed labels 0 of 3,223 - the 3 tickers
#   still under 0.9 (A008320 year-end changed . A011720 . A054050) have shifted shares <= 0.848.
ALIGN_SAME_MAX, ALIGN_SHIFT_MIN, ALIGN_MIN_N = 0.9, 0.9, 12
FM_CLASSES = (12, 11, 10)  # one year-end month per class of fiscal quarter-end months (mod 3) - each class's window
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


def _kv(s):
    """'YYYYMM' Series -> quarter index (vectorised _k)."""
    s = s.astype(str)
    return s.str[:4].astype(int) * 4 + s.str[4:].astype(int) // 3 - 1


def row_month(d):
    """date row 'YYYY-MM' (or a date) -> (year, month)."""
    if isinstance(d, (dt.datetime, dt.date)):
        return d.year, d.month
    s = str(d).strip()
    return int(s[:4]), int(s[5:7])


def period_from_row_date(d, fiscal_month=12):
    """date row d -> Period 'YYYYMM' for a firm with that fiscal year-end month (Mapping): the fiscal quarter containing
    d - 3 months, labelled by the calendar quarter in which it ends. Dec (and Mar / Jun / Sep) year-ends = d - 1Q."""
    y, m = row_month(d)
    i = y * 12 + (m - 1) - 3  # month index of d - 3 months
    return _qk((i + (int(fiscal_month) - 1 - i) % 3) // 3)  # the first fiscal quarter-end month at or after it -> its quarter


def expected_window(today, n):
    """(first, last) fiscal quarters of the last n quarters ending at the last quarter-end month <= today - the rule of
    qw_fundamental_book.ps1 (period_to 'auto' + window_quarters) and of qw_fund_v2_tax_ts.ps1 Window-From (B5)."""
    qm = [m for m, d in ((3, 31), (6, 30), (9, 30), (12, 31)) if (today.month, today.day) >= (m, d)]
    k = today.year * 4 + (qm[-1] // 3 - 1 if qm else -1)
    return _qk(k - n + 1), _qk(k)


def load_fiscal_months(root):
    """Ticker -> fiscal year-end month 1~12 (.cache/qw_fund_v2/fiscal_month.parquet)."""
    p = f'{root}/.cache/qw_fund_v2/fiscal_month.parquet'
    if not os.path.exists(p):
        raise Refused(f'{p} missing - the fiscal year-end months come from the Peer Analysis ingest (qw_fund_v2_ingest.py)')
    fm = pq.read_table(p, columns=['Ticker', 'FiscalMonth']).to_pandas()
    m = pd.to_numeric(fm['FiscalMonth'], errors='coerce')
    good = m.between(1, 12) & (m == m.round())
    s = pd.Series(m[good].astype(int).to_numpy(), index=fm.loc[good, 'Ticker'].astype(str).to_numpy())
    return s[~s.index.duplicated(keep='last')]


def map_periods(new, fms, report):
    """date row -> Period per ticker by its fiscal year-end month (Mapping) . rows that land on one period kept once."""
    fmv = new['Ticker'].map(fms)
    unknown = sorted(new.loc[fmv.isna(), 'Ticker'].unique())
    if unknown:
        raise Refused(f'no fiscal year-end month (fiscal_month.parquet) for {len(unknown)} tickers with numbers: {unknown[:10]}'
                      ' - load the Peer Analysis DBs first')
    key = list(zip(new['RowDate'], fmv.astype(int)))
    lab = {k: period_from_row_date(*k) for k in set(key)}
    new = new.assign(Period=[lab[k] for k in key]).drop(columns='RowDate')
    keys = ['Ticker', 'Period', 'Item']
    dup = new.duplicated(keys, keep=False)
    if dup.any():
        nv = new[dup].groupby(keys)['Value'].nunique()
        if (nv > 1).any():
            raise Refused(f'{int((nv > 1).sum())} (Ticker, Period, Item) get different values from two date rows: '
                          f'{list(nv[nv > 1].index[:5])}')
    n_once = int(new.duplicated(keys).sum())
    new = new.drop_duplicates(keys).reset_index(drop=True)
    off = fms[(fms % 3 != 0) & fms.index.isin(new['Ticker'].unique())]
    report['fiscal_month'] = {'off_calendar_tickers': {t: int(v) for t, v in sorted(off.items())},
                              'same_period_rows_kept_once': n_once}
    print(f'[tax-ingest] fiscal year-end months: {len(off)} off-calendar tickers (one quarter later than d - 1Q) . '
          f'{n_once} rows on one period kept once')
    return new


def load_ap(root):
    """v2 AccountsPay (M113200, KRW) per (Ticker, Period) - the reference of both payables controls."""
    bs = pq.read_table(f'{root}/.cache/qw_fund_v2/FundV2_BS.parquet', columns=['Ticker', 'Period', 'Item', 'Value'],
                       filters=[('Item', '==', 'AccountsPay')]).to_pandas()
    bs = bs[bs['Value'].abs() > 0]
    return pd.DataFrame({'Ticker': bs['Ticker'].astype(str), 'Period': bs['Period'].astype(str), 'ap': bs['Value']})


def payables_control(df, ap):
    nil = df.loc[df['Item'] == 'NonInterestCurLiab', ['Ticker', 'Period', 'Value']]
    j = nil.merge(ap, on=['Ticker', 'Period'])
    share = float((j['Value'] >= j['ap'] - 1000).mean()) if len(j) else float('nan')
    return {'n': int(len(j)), 'share_nil_ge_ap': round(share, 5), 'min': CONTROL_MIN}


def alignment_control(df, ap, watch=()):
    """per ticker: share of NonInterestCurLiab >= v2 AccountsPay for the same quarter, one quarter later and one earlier
    (watch = tickers whose shares go to the report - the off-calendar ones)."""
    nil = df.loc[df['Item'] == 'NonInterestCurLiab', ['Ticker', 'Period', 'Value']]
    b = ap.assign(k=_kv(ap['Period'])).drop_duplicates(['Ticker', 'k']).set_index(['Ticker', 'k'])['ap']
    t, k, v = nil['Ticker'].to_numpy(), _kv(nil['Period']).to_numpy(), nil['Value'].to_numpy()
    d = pd.DataFrame({'Ticker': t})
    for tag, s in (('same', 0), ('later', 1), ('earlier', -1)):
        x = b.reindex(pd.MultiIndex.from_arrays([t, k + s])).to_numpy(dtype=float)
        has = ~np.isnan(x)
        d['n_' + tag] = has
        d['ge_' + tag] = has & (v >= np.where(has, x, 0) - 1000)
    g = d.groupby('Ticker').sum()
    sh = {tag: g['ge_' + tag] / g['n_' + tag].where(g['n_' + tag] > 0) for tag in ('same', 'later', 'earlier')}
    tested = g['n_same'] >= ALIGN_MIN_N
    shifted = ((g['n_later'] >= ALIGN_MIN_N) & (sh['later'] >= ALIGN_SHIFT_MIN)) | \
              ((g['n_earlier'] >= ALIGN_MIN_N) & (sh['earlier'] >= ALIGN_SHIFT_MIN))
    flag = tested & (sh['same'] < ALIGN_SAME_MAX) & shifted
    row = lambda x: [round(float(sh[tag][x]), 3) for tag in ('same', 'later', 'earlier')]
    return {'tested': int(tested.sum()),
            'same_median': round(float(sh['same'][tested].median()), 4) if tested.any() else None,
            'flagged': {x: row(x) for x in g.index[flag]},
            'watch': {x: [int(g['n_same'][x])] + row(x) for x in watch if x in g.index},
            'rule': f'same < {ALIGN_SAME_MAX} and one quarter later or earlier >= {ALIGN_SHIFT_MIN} ({ALIGN_MIN_N}+ quarters each)'
                    ' . watch = [n . same . one later . one earlier]'}


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
    recs, row_dates, n_text, unknown_units, defaulted = [], [], 0, set(), set()
    for row in rows[14:]:
        d = row[0]
        if d is None or str(d).strip() == '':
            break
        lab = '%04d-%02d' % row_month(d)
        row_dates.append(lab)
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
            recs.append((str(t), lab, item, float(v) * UNIT_SCALE[u]))
    if unknown_units:
        raise Refused(f'{ws.title}: numeric cells under unknown units {sorted(unknown_units)}')
    if not recs:
        raise Refused(f'{ws.title}: no numeric cells')
    df = pd.DataFrame(recs, columns=['Ticker', 'RowDate', 'Item', 'Value'])
    m = re.search(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', b1)
    info = {'b1': b1, 'stamp': m.group(1) if m else None, 'code': code, 'base': base, 'numeric': len(df), 'text_dropped': n_text,
            'tickers': int(df['Ticker'].nunique()),
            'periods': [period_from_row_date(df['RowDate'].min()), period_from_row_date(df['RowDate'].max())],
            'row_dates': row_dates, 'unit_defaulted_tickers': sorted(defaulted)}
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
            rows_by_sheet[s] = tuple(info.pop('row_dates'))
            report['sheets'][s] = {'item': item, **info}
            print(f'[tax-ingest] {s} -> {item}: numeric {info["numeric"]:,} . text dropped {info["text_dropped"]:,} . '
                  f'tickers {info["tickers"]:,} . periods {info["periods"][0]}~{info["periods"][1]} (Dec year-end labels)')
    finally:
        wb.close()
    new = pd.concat(parts, ignore_index=True)
    dup = int(new.duplicated(['Ticker', 'RowDate', 'Item']).sum())
    if dup:
        raise Refused(f'duplicated (Ticker, date row, Item) cells: {dup}')
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
    new['Text'] = pd.Series([None] * len(new), dtype=object)
    stamps = [s['stamp'] for s in report['sheets'].values() if s.get('stamp')]
    fetched = max(stamps).replace(' ', 'T') if stamps else dt.datetime.now().strftime('%Y-%m-%dT%H:%M:%S')
    if len(set(rows_by_sheet.values())) != 1:
        raise Refused('date rows differ between sheets')
    row_dates = list(next(iter(rows_by_sheet.values())))
    periods = [period_from_row_date(d) for d in row_dates]  # Dec year-end label of each date row - the row gates below
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
    fms = load_fiscal_months(root)
    new = map_periods(new, fms, report)
    ap = load_ap(root)
    ctl = payables_control(new, ap)
    report['payables_control'] = ctl
    print(f'[tax-ingest] payables control: NonInterestCurLiab >= v2 AccountsPay {ctl["share_nil_ge_ap"]} (n {ctl["n"]:,} . min {CONTROL_MIN})')
    if not ctl['n'] or not ctl['share_nil_ge_ap'] >= CONTROL_MIN:
        raise Refused(f'payables control failed {ctl} - period mapping (FQ0 lagging option) or units changed')
    # the periods the date rows cover differ by class of fiscal year-end month (mod 3 - FM_CLASSES: Dec / Mar / Jun / Sep .
    # Nov / Aug / May / Feb . Oct / Jul / Apr / Jan): each class is checked and merged against its own cover, so a value
    # that disappears from a covered period is a deletion and the periods only another class covers are left alone
    cover = {f % 3: sorted({period_from_row_date(d, f) for d in row_dates}) for f in FM_CLASSES}
    if a.window:
        cover = {c: [p for p in ps if p >= first] for c, ps in cover.items()}
        report['cells_before_window_dropped'] = int((new['Period'] < first).sum())
        new = new[new['Period'] >= first]
    win_periods = sorted(set().union(*cover.values()))
    core = load_core()
    new = new[['Ticker', 'Period', 'Item', 'Value', 'Text']]
    if os.path.exists(out):
        old = pq.read_table(out).to_pandas()
        c_old = (old['Ticker'].map(fms).fillna(12).astype(int) % 3).to_numpy()
        c_new = (new['Ticker'].map(fms).astype(int) % 3).to_numpy()
        # fill drop vs the parent per class (same rule and constants as the Peer Analysis DBs - qw_fund_v2_ingest G3)
        drops = []
        for c, ps in cover.items():
            pc = old[(c_old == c) & old['Period'].isin(ps).to_numpy()].groupby(['Item', 'Period']).size()
            nc = new[c_new == c].groupby(['Item', 'Period']).size()
            drops += [f'{i}|{p} {int(pc[(i, p)])}->{int(nc.get((i, p), 0))}' for (i, p) in pc.index
                      if pc[(i, p)] >= core.FILL_MIN and nc.get((i, p), 0) < core.FILL_RATIO * pc[(i, p)]]
        if drops:
            raise Refused(f'fill drop vs parent {len(drops)} cells: ' + '; '.join(drops[:5]))
        # both modes replace the covered (Item, Period) window of the parent with the shared window_merge (Peer v2 DBs):
        # unchanged values keep first_fetched_at . changed / deleted -> revisions.parquet (Db = FundV2_TAX . FundV2_TAX_upd)
        parts, revs, cnt = [], [], {'new': 0, 'changed': 0, 'deleted': 0}
        for c, ps in cover.items():
            win = {(it, p) for _, it in SHEETS.values() for p in ps}
            r, rv, n = core.window_merge(old[c_old == c], new[c_new == c], win, UPD_DB if a.window else 'FundV2_TAX', fetched)
            parts.append(r); revs += rv; cnt = {k: cnt[k] + n[k] for k in cnt}
        res = pd.concat([r for r in parts if len(r)] or parts[:1], ignore_index=True)
        res = res.sort_values(core.KEYS, kind='stable').reset_index(drop=True)
        report['previous_rows'] = int(len(old))
    else:
        res = new.assign(first_fetched_at=fetched, last_fetched_at=fetched).sort_values(core.KEYS, kind='stable').reset_index(drop=True)
        revs, cnt = [], {'new': int(len(res)), 'changed': 0, 'deleted': 0}
    al = alignment_control(res, ap, watch=report['fiscal_month']['off_calendar_tickers'])
    report['alignment_control'] = al
    print(f'[tax-ingest] alignment control: {al["tested"]:,} tickers with {ALIGN_MIN_N}+ quarters . same-quarter median '
          f'{al["same_median"]} . flagged {len(al["flagged"])}')
    if al['flagged']:
        raise Refused(f'{len(al["flagged"])} tickers line up one quarter off with v2 AccountsPay - fiscal year-end month wrong? '
                      f'{dict(list(al["flagged"].items())[:5])} [same . one later . one earlier]')
    report.update({'periods': [periods[0], periods[-1], len(periods)],
                   'win_periods': [win_periods[0], win_periods[-1], len(win_periods)], 'counts': cnt})
    print(f'[tax-ingest] {report["mode"]} {periods[0]}~{periods[-1]} ({len(periods)} quarters . window labels '
          f'{win_periods[0]}~{win_periods[-1]}) . new {cnt["new"]:,} . changed {cnt["changed"]:,} . deleted {cnt["deleted"]:,}')
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
