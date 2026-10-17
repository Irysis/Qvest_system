# -*- coding: utf-8 -*-
"""krx_holidays.py — KRX 공식 휴장일 등록부(06_Registry/krx_holidays.json) 수급 · 조회 (2026-10-17)

왜 (도훈 10-17 "복잡하게 가지말고 부팅시점에 최신화 안되어있으면 퀀티로그인해서 최신화시킨다로 정리해" ·
    "공휴일정보 찾아서 붙여"):
  퀀티 단일(BENCHMARK-QW-ONLY-20261017)에서는 거래일 캘린더(= 벤치)도 퀀티가 늘린다. 퀀티가 멈추면 캘린더 기반
  '직전 거래일'도 같이 멈춰 신선도 감사가 '최신'으로 읽는다(순환). '있어야 할 직전 거래일'을 퀀티와 무관하게
  알려면 거래소 휴장일이 필요하다 — 이 파일이 그 정본을 KRX 에서 받아 등록부에 싣고(fetch) 직전 거래일을 답한다(expected).

원천: 한국거래소 KRX Open '휴장일' https://open.krx.co.kr/contents/MKD/01/0110/01100305/MKD01100305.jsp
  데이터 = POST https://open.krx.co.kr/contents/OPN/99/OPN99000001.jspx (bld MKD/01/0110/01100305/mkd01100305_01 · OTP)
  ★주말이 아닌 휴장일만 온다(연말 휴장 · 선거일 · 임시공휴일 · 근로자의 날 포함).
  ★2008 이전 목록은 불완전하다 — 10-17 대조: 2008 은 설 연휴 · 근로자의 날 · 현충일이 빠졌고 2000~2007 은 연초 · 연말
    1~4일뿐이다. 2009-01-01~2026-10-16 은 벤치 거래일 = 평일 − 이 목록이 정확히 맞는다(차이 = 2024-12-30 하루 —
    KRX 휴장 아님 · 퀀티 xlsx 에 세션 있음 · 벤치 격자에서 빠짐). 그래서 기본 시작 = 2009.

사용:
  python krx_holidays.py fetch [--from 2009] [--to <올해+1>]   # 등록부 갱신(받은 해만 싣는다 · 빈 해 = 미공표)
  python krx_holidays.py expected [--today YYYY-MM-DD] [--no-fetch]
        # 오늘(--today · 없으면 환경변수 QVEST_KRX_TODAY · 없으면 시스템 날짜) 이전 마지막 거래일(YYYY-MM-DD).
        # 그 해가 등록부에 없으면 한 번 받아 본다(--no-fetch 면 안 받음)
        # 그래도 없으면 'NA <사유>' · rc=2
  python krx_holidays.py currency [--no-fetch]                  # 퀀티 최신성 'state|벤치 최신일|직전 거래일' (state 1 = 미최신 · 0 · NA)
  python krx_holidays.py verify                                 # 벤치 거래일 = 평일 − 휴장일 대조(차이 날짜 출력 · 차이 있으면 rc=1)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta
from pathlib import Path

ROOT = Path(os.environ.get('QM_ROOT') or Path(__file__).resolve().parents[2])
REGISTRY = ROOT / '06_Registry' / 'krx_holidays.json'
PAGE = 'https://open.krx.co.kr/contents/MKD/01/0110/01100305/MKD01100305.jsp'
OTP_URL = ('https://open.krx.co.kr/contents/COM/GenerateOTP.jspx'
           '?bld=MKD%2F01%2F0110%2F01100305%2Fmkd01100305_01&name=form')
DATA_URL = 'https://open.krx.co.kr/contents/OPN/99/OPN99000001.jspx'
FIRST_COMPLETE_YEAR = 2009        # 위 머리말 — 2008 이전 KRX 목록은 불완전(벤치 거래일 대조)
UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'


def _http(url: str, data: bytes | None = None, timeout: int = 30) -> str:
    req = urllib.request.Request(url, data=data, headers={'User-Agent': UA, 'Referer': PAGE})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode('utf-8')


def fetch_year(year: int) -> dict[str, str]:
    """KRX 가 그 해에 공시한 (평일) 휴장일 {YYYY-MM-DD: 이름}. 미공표 해는 빈 dict."""
    otp = _http(OTP_URL).strip()
    body = urllib.parse.urlencode({'code': otp, 'search_bas_yy': str(year), 'gridTp': 'KRX',
                                   'pagePath': '/contents/MKD/01/0110/01100305/MKD01100305.jsp'}).encode()
    rows = json.loads(_http(DATA_URL, body)).get('block1') or []
    out = {}
    for x in rows:
        d = str(x.get('calnd_dd') or '')[:10]
        if len(d) == 10 and d.startswith(str(year)):
            out[d] = str(x.get('holdy_nm') or '').strip()
    return out


def load() -> dict:
    try:
        return json.loads(REGISTRY.read_text(encoding='utf-8'))
    except Exception:
        return {}


def save(reg: dict) -> None:
    REGISTRY.parent.mkdir(parents=True, exist_ok=True)
    tmp = REGISTRY.with_name(REGISTRY.name + f'.tmp{os.getpid()}')
    tmp.write_text(json.dumps(reg, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    os.replace(tmp, REGISTRY)


def fetch(y0: int, y1: int, quiet: bool = False) -> dict:
    reg = load()
    hol = dict(reg.get('holidays') or {})
    years = set(int(y) for y in (reg.get('years') or []))
    for y in range(y0, y1 + 1):
        got = fetch_year(y)
        if not got:
            if not quiet:
                print(f'  {y}: KRX 미공표(빈 목록) — 싣지 않는다')
            continue
        hol = {k: v for k, v in hol.items() if not k.startswith(f'{y}-')}
        hol.update(got)
        years.add(y)
        if not quiet:
            print(f'  {y}: {len(got)}일')
    reg.update({
        'schema': 'krx_holidays_v1',
        'source_page': PAGE,
        'source_data': DATA_URL + ' (bld=MKD/01/0110/01100305/mkd01100305_01 · gridTp=KRX · OTP)',
        'fetched_at': datetime.now().astimezone().isoformat(timespec='seconds'),
        'fetcher': '02_Infrastructure/data/krx_holidays.py fetch',
        'note': ('주말이 아닌 휴장일만 싣는다(KRX 목록 그대로). 2008 이전 KRX 목록은 불완전해 싣지 않는다(10-17 벤치 거래일 대조). '
                 '쓰임 = ensure_data_current.sh 퀀티 최신성 축(벤치 최신일 < 직전 거래일 → 퀀티 로그인 · 최신화) · boot_lean.sh Data 줄'),
        'years': sorted(years),
        'holidays': dict(sorted(hol.items())),
    })
    save(reg)
    return reg


def last_session_before(today: date, reg: dict | None = None, allow_fetch: bool = True):
    """오늘 이전 마지막 거래일. 반환 (date, None) 또는 (None, 사유)."""
    reg = reg if reg is not None else load()
    years, hol = {int(y) for y in reg.get('years') or []}, reg.get('holidays') or {}
    d = today - timedelta(days=1)
    for _ in range(31):                       # 최장 연휴(설 · 추석 + 주말 + 대체)보다 넉넉한 탐색 폭
        if d.year not in years:
            if not allow_fetch:
                return None, f'year_not_covered:{d.year}'
            try:
                reg = fetch(d.year, d.year, quiet=True)
            except Exception as e:            # 네트워크 실패 = 판정 불가(호출부가 '미측정'으로 적는다)
                return None, f'fetch_failed:{d.year}:{e.__class__.__name__}'
            years, hol = {int(y) for y in reg.get('years') or []}, reg.get('holidays') or {}
            if d.year not in years:
                return None, f'year_not_published:{d.year}'
            allow_fetch = False
        if d.weekday() < 5 and d.isoformat() not in hol:
            return d, None
        d -= timedelta(days=1)
    return None, 'no_session_within_31d'


def bench_currency(today: date, allow_fetch: bool = True):
    """퀀티 최신성 판정 단일 정본 — (상태 '1' 미최신 · '0' 최신 · 'NA' 판정 불가, 벤치 최신일, 직전 거래일 또는 사유).
    ensure_data_current.sh(currency 하위 명령) 와 boot_lean.sh Data 줄이 같은 판정을 쓴다(판정 생산자 == 판정 보고자)."""
    exp, why = last_session_before(today, allow_fetch=allow_fetch)
    try:
        import pyarrow.parquet as pq
        bm = max(pq.read_table(str(ROOT / '.cache' / 'benchmark.parquet'), columns=['Date']).column('Date').to_pylist())
        bm = bm.date() if isinstance(bm, datetime) else bm
    except Exception as e:
        return 'NA', None, f'bench_unreadable:{e.__class__.__name__}'
    if exp is None:
        return 'NA', bm, why
    return ('1' if bm < exp else '0'), bm, exp


def verify() -> int:
    import pandas as pd
    import pyarrow.parquet as pq
    reg = load()
    hol = set(reg.get('holidays') or {})
    years = sorted(int(y) for y in (reg.get('years') or []))
    if not years:
        print('등록부 비어 있음 — fetch 먼저')
        return 2
    s = pd.to_datetime(pq.read_table(str(ROOT / '.cache' / 'benchmark.parquet'), columns=['Date'])
                       .to_pandas()['Date']).dt.date
    sess = set(s)
    end = max(sess)
    bad = 0
    for y in years:
        e = min(date(y, 12, 31), end)
        if e < date(y, 1, 1):
            continue
        wk = [date(y, 1, 1) + timedelta(days=i) for i in range((e - date(y, 1, 1)).days + 1)]
        exp = {d for d in wk if d.weekday() < 5 and d.isoformat() not in hol}
        got = {d for d in sess if d.year == y and d <= e}
        miss, extra = sorted(exp - got), sorted(got - exp)
        if miss or extra:
            bad += 1
            print(f'{y}: 벤치에 없는 거래일 {[d.isoformat() for d in miss]} · 휴장일인데 벤치에 있는 날 {[d.isoformat() for d in extra]}')
    print(f'대조 {years[0]}~{end.isoformat()} — 차이 있는 해 {bad}')
    return 1 if bad else 0


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    f = sub.add_parser('fetch')
    f.add_argument('--from', dest='y0', type=int, default=FIRST_COMPLETE_YEAR)
    f.add_argument('--to', dest='y1', type=int, default=date.today().year + 1)
    e = sub.add_parser('expected')
    e.add_argument('--today', default=None)
    e.add_argument('--no-fetch', action='store_true')
    c = sub.add_parser('currency')          # 'state|bench_max|expected' — ensure_data_current.sh 2b 축
    c.add_argument('--no-fetch', action='store_true')
    sub.add_parser('verify')
    a = ap.parse_args()
    if a.cmd == 'fetch':
        reg = fetch(a.y0, a.y1)
        print(f'[krx_holidays] {REGISTRY} — {len(reg["holidays"])}일 · 해 {reg["years"][0]}~{reg["years"][-1]}')
        return 0
    t = getattr(a, 'today', None) or os.environ.get('QVEST_KRX_TODAY')      # 시험용 주입(호출부는 인자 없이 부른다)
    today = date.fromisoformat(t) if t else date.today()
    if a.cmd == 'currency':
        st, bm, exp = bench_currency(today, allow_fetch=not a.no_fetch)
        print(f'{st}|{bm.isoformat() if bm else "?"}|{exp.isoformat() if isinstance(exp, date) else exp}')
        return 0 if st != 'NA' else 2
    if a.cmd == 'expected':
        d, why = last_session_before(today, allow_fetch=not a.no_fetch)
        if d is None:
            print(f'NA {why}')
            return 2
        print(d.isoformat())
        return 0
    return verify()


if __name__ == '__main__':
    sys.exit(main())
