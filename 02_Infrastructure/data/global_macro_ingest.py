# -*- coding: utf-8 -*-
"""global_macro_ingest.py — 퀀티 경제 질의서 03_Universe/Global_Macro.xlsx → .cache/qw_global_macro.parquet (2026-10-20)

★왜 (도훈 2026-10-20 'WTI 일일 갱신까지 편입'): THGNN(2601.04602) 거시 입력의 WTI 출처.
  FRED DCOILWTICO(EIA 현물)는 주 1회 공표라 보수 오프셋(+16역일)으로만 결합할 수 있었고 도훈이 그 방식을 기각했다.
  국내 출처를 찾은 결과(석유공사 페트로넷 = robots 전면 거부 · KOSIS/KESIS/ECOS = 월간):
    퀀티 ECO Wise › 국제수지/무역/외환(BOP) › 원유 › WTI유(NYMEX) = 심볼 xcCHPRWDQWTI
    = NYMEX 근월 결제가(페트로넷과 같은 값) · 1996-01-02~ · 날짜 = 미국 거래일 · Data Type Previous(미국 휴장일 = 전일값).
  질의서 갱신은 정본 벤치와 같은 길이다(quantiwise_fetch.py --dest → qw_excel_refresh.ps1 · 일일 체인 [1pre-gm]).

가용일은 여기서 정하지 않는다 — 06_Registry/fred_availability_rules.json 의 계열 규칙이 정한다
  (QW_WTI_NYMEX = kr_trading_days_after 1: NYMEX 결제 14:30 ET = 한국 다음 날 03:30~04:30 → 미국 날짜 < 한국 날짜).
규칙이 없는 심볼은 적재하지 않는다(fail-closed · 종료코드 2).

출력: 긴 형식(Date, Series_ID, Value, Symbol, Name, Unit) · 값이 있는 행만 · 원자적 교체 · 메타 .cache/qw_global_macro_meta.json
종료코드: 0 = 적재 · 2 = 형식 이상(심볼 미등록 · 날짜 역행 · 값 없음) · 3 = 신선도 미달(마지막 값이 STALE_DAYS 역일보다 오래됨)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import sys
from datetime import date, datetime
from pathlib import Path

PROJECT_ROOT = Path(os.environ.get('CLAUDE_PROJECT_DIR') or os.environ.get('QM_ROOT') or Path(__file__).resolve().parents[2])
SRC = PROJECT_ROOT / '03_Universe' / 'Global_Macro.xlsx'
OUT = PROJECT_ROOT / '.cache' / 'qw_global_macro.parquet'
META = PROJECT_ROOT / '.cache' / 'qw_global_macro_meta.json'

# 퀀티 심볼 → 계열 id(가용일 규칙 id 와 같아야 한다)
#   xarKOIRKSDACD = 통화/금융(MB) › 시장금리 › CD(91일) — 1994-06-29~ 일간. THGNN 무위험이자율(도훈 10-20 '퀀티 CD91 전 구간':
#   ECOS 817Y002 CD91 은 2005-08-01 부터라 축 첫 7개월이 빈다). ★11-06 정정: 당시 캐시 KR_CD91 은 항목 코드 오류로 KORIBOR(3개월 · 2005-08~)이었다 —
#   '다른 고시라 값이 다르다(최대 39bp)'는 그 오표기 탓이고, 진짜 ECOS CD(91일)(010502000 · 1995~)은 퀀티 CD91 과 같은 계열이다(수집기 수리 11-06).
SERIES = {'xcCHPRWDQWTI': 'QW_WTI_NYMEX', 'xarKOIRKSDACD': 'QW_KR_CD91'}
# 미국 연휴 최장(추수감사절 목 + 주말 = 4역일) + 퀀티 반영 하루 + 여유 = 7역일. 넘으면 수급 정체로 신고한다.
STALE_DAYS = 7
HEADER = {'symbol': 8, 'name': 9, 'unit': 11}
FIRST_DATA_ROW = 15


def read_sheet(path: Path) -> tuple[list[dict], list[tuple]]:
    import openpyxl
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    try:
        ws = wb.worksheets[0]
        head = {k: [c for c in next(ws.iter_rows(min_row=r, max_row=r, values_only=True))] for k, r in HEADER.items()}
        cols = []
        for j, sym in enumerate(head['symbol']):
            if j == 0 or sym in (None, ''):
                continue
            cols.append({'col': j, 'symbol': str(sym).strip(), 'name': head['name'][j], 'unit': head['unit'][j]})
        rows = [r for r in ws.iter_rows(min_row=FIRST_DATA_ROW, values_only=True) if r and r[0] is not None]
    finally:
        wb.close()
    return cols, rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', default=str(SRC))
    ap.add_argument('--out', default=str(OUT))
    ap.add_argument('--meta', default=str(META))
    ap.add_argument('--today', default=None, help='신선도 기준일(YYYY-MM-DD · 검사용)')
    args = ap.parse_args()
    src, out, meta_path = Path(args.src), Path(args.out), Path(args.meta)
    today = date.fromisoformat(args.today) if args.today else date.today()

    cols, rows = read_sheet(src)
    unknown = [c['symbol'] for c in cols if c['symbol'] not in SERIES]
    if not cols or unknown:
        print(f'[global_macro] ★심볼 미등록 {unknown or "(열 없음)"} — SERIES 매핑과 가용일 규칙을 먼저 넣는다(적재 안 함)')
        return 2
    recs, prev = [], None
    for r in rows:
        d = r[0].date() if isinstance(r[0], datetime) else r[0]
        if not isinstance(d, date):
            print(f'[global_macro] ★A열 날짜 아님: {r[0]!r} — 적재 안 함')
            return 2
        if prev is not None and d <= prev:
            print(f'[global_macro] ★날짜 역행·중복 {prev} → {d} — 적재 안 함')
            return 2
        prev = d
        for c in cols:
            v = r[c['col']] if c['col'] < len(r) else None
            if v is None or (isinstance(v, float) and math.isnan(v)):
                continue
            recs.append((d, SERIES[c['symbol']], float(v), c['symbol'], c['name'], c['unit']))
    if not recs:
        print('[global_macro] ★값 0건 — 적재 안 함')
        return 2

    import pyarrow as pa
    import pyarrow.parquet as pq
    tbl = pa.table({
        'Date': pa.array([x[0] for x in recs], pa.date32()),
        'Series_ID': [x[1] for x in recs], 'Value': [x[2] for x in recs],
        'Symbol': [x[3] for x in recs], 'Name': [x[4] for x in recs], 'Unit': [x[5] for x in recs]})
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_name(out.name + f'.tmp{os.getpid()}')
    pq.write_table(tbl, tmp)
    os.replace(tmp, out)

    series_meta = {}
    for sid in sorted({x[1] for x in recs}):
        ds = [x[0] for x in recs if x[1] == sid]
        series_meta[sid] = {'n': len(ds), 'date_min': ds[0].isoformat(), 'date_max': ds[-1].isoformat()}
    st = src.stat()
    meta = {'schema': 'qw_global_macro_meta_v1', 'at': datetime.now().isoformat(timespec='seconds'),
            'source': str(src), 'source_mtime': datetime.fromtimestamp(st.st_mtime).isoformat(timespec='seconds'),
            'source_sha256': hashlib.sha256(src.read_bytes()).hexdigest(), 'rows': len(recs), 'series': series_meta,
            'availability': '06_Registry/fred_availability_rules.json (계열 id 규칙 · 이 파일은 관측 라벨만 싣는다)'}
    mt = meta_path.with_name(meta_path.name + f'.tmp{os.getpid()}')
    mt.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding='utf-8')
    os.replace(mt, meta_path)
    stale = {sid: m['date_max'] for sid, m in series_meta.items() if (today - date.fromisoformat(m['date_max'])).days > STALE_DAYS}
    print(f'[global_macro] 적재 {len(recs)}행 → {out.name} · ' + ' · '.join(f'{k} {v["date_min"]}~{v["date_max"]}' for k, v in series_meta.items()))
    if stale:
        print(f'[global_macro] ★신선도 미달(> {STALE_DAYS}역일): {stale} — 질의서 수급 정체(세션 · 중복 로그인 확인)')
        return 3
    return 0


if __name__ == '__main__':
    sys.exit(main())
