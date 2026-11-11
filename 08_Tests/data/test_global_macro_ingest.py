# -*- coding: utf-8 -*-
"""test_global_macro_ingest.py — 02_Infrastructure/data/global_macro_ingest.py (퀀티 경제 질의서 → qw_global_macro.parquet · 2026-10-20)

합성 질의서(퀀티 머리말 형식 · 8행 Symbol · 9행 Name · 11행 Unit · 15행부터 날짜/값)로 종료코드와 산출을 잰다. 운영 .cache · 03_Universe 무접촉.
  a 정상 → rc 0 · 값 있는 행만 · 음수(2020-04-20 −37.63 같은) 보존 · Series_ID = 가용일 규칙 id
  b 미등록 심볼 → rc 2(적재 안 함)    c 날짜 역행 → rc 2    d 마지막 값이 8역일 전 → rc 3(신선도 미달)
  e 실제 정본 질의서(있으면) → 심볼 전부 등록 · 규칙 파일에 계열 id 존재
실행: .venv_qvest_ml/Scripts/python.exe -X utf8 08_Tests/data/test_global_macro_ingest.py
"""
import json
import os
import subprocess
import sys
import tempfile
from datetime import date, datetime
from pathlib import Path

# ── (2026-11-11) 해석기 자기해결 — 배터리(run_all_hooks.sh)는 pyarrow 없는 시스템 파이썬으로 돈다.
#   없으면 venv 로 다시 실행한다(SKIP 하지 않는다 — SKIP 은 통과와 겉보기가 같다). 패턴 = data/test_qw_fund_v2_ingest.py.
try:
    import pyarrow as _pa_probe  # noqa: F401
except ImportError:
    import subprocess as _sp
    _venv = ""
    for _cand in (str(Path(__file__).resolve().parents[2]), os.environ.get("CLAUDE_PROJECT_DIR", ""), os.environ.get("QM_ROOT", "")):
        _p = os.path.join(_cand.replace("\\", "/"), ".venv_qvest_ml", "Scripts", "python.exe") if _cand else ""
        if _p and os.path.exists(_p):
            _venv = _p
            break
    if _venv and os.environ.get("_QVEST_VENV_REEXEC") != "1":
        sys.exit(_sp.call([_venv, "-X", "utf8", os.path.abspath(__file__)] + sys.argv[1:], env=dict(os.environ, _QVEST_VENV_REEXEC="1")))
    raise

ROOT = Path(os.environ.get('QM_ROOT') or Path(__file__).resolve().parents[2])
ING = ROOT / '02_Infrastructure' / 'data' / 'global_macro_ingest.py'
PASS = FAIL = 0


def chk(name, ok, extra=''):
    global PASS, FAIL
    print(f"  {'PASS' if ok else 'FAIL'}  {name} {extra}")
    PASS, FAIL = PASS + bool(ok), FAIL + (not ok)


def make_xlsx(path, symbol, rows):
    import openpyxl
    wb = openpyxl.Workbook()
    ws = wb.active
    ws['A1'] = '     Refresh     '
    ws['A3'] = 'Economy'
    ws['A8'], ws['B8'] = 'Symbol', symbol
    ws['A9'], ws['B9'] = 'Name', 'WTI유(NYMEX)'
    ws['A11'], ws['B11'] = 'Unit', 'USD/베럴'
    ws['A14'] = 'D A T E'
    for i, (d, v) in enumerate(rows):
        ws.cell(15 + i, 1, datetime(d.year, d.month, d.day))
        if v is not None:
            ws.cell(15 + i, 2, v)
    wb.save(path)


def run(src, out, today):
    meta = Path(out).with_name(Path(out).stem + '_meta.json')     # 운영 .cache/qw_global_macro_meta.json 무접촉
    p = subprocess.run([sys.executable, '-X', 'utf8', str(ING), '--src', str(src), '--out', str(out), '--meta', str(meta), '--today', today],
                       capture_output=True, text=True, encoding='utf-8', errors='replace')
    return p.returncode, p.stdout


with tempfile.TemporaryDirectory() as td:
    td = Path(td)
    (td / '.cache').mkdir()
    out = td / '.cache' / 'qw_global_macro.parquet'
    good = [(date(2020, 4, 17), 18.27), (date(2020, 4, 20), -37.63), (date(2020, 4, 21), 10.01), (date(2020, 4, 22), None)]
    make_xlsx(td / 'a.xlsx', 'xcCHPRWDQWTI', good)
    rc, so = run(td / 'a.xlsx', out, '2020-04-23')
    chk('a 정상 → rc 0', rc == 0, f'(rc={rc})')
    if rc == 0:
        import pyarrow.parquet as pq
        t = pq.read_table(out).to_pydict()
        chk('a 값 있는 행만(4행 중 3행)', len(t['Date']) == 3, f"({len(t['Date'])})")
        chk('a 음수 결제가 보존(−37.63)', -37.63 in t['Value'])
        chk('a Series_ID = 가용일 규칙 id QW_WTI_NYMEX', set(t['Series_ID']) == {'QW_WTI_NYMEX'})
    make_xlsx(td / 'b.xlsx', 'xcCHPRWDQXXX', good)
    rc, _ = run(td / 'b.xlsx', td / '.cache' / 'b.parquet', '2020-04-23')
    chk('b 미등록 심볼 → rc 2 · 산출 없음', rc == 2 and not (td / '.cache' / 'b.parquet').exists(), f'(rc={rc})')
    make_xlsx(td / 'c.xlsx', 'xcCHPRWDQWTI', [(date(2020, 4, 20), 1.0), (date(2020, 4, 17), 2.0)])
    rc, _ = run(td / 'c.xlsx', td / '.cache' / 'c.parquet', '2020-04-23')
    chk('c 날짜 역행 → rc 2', rc == 2, f'(rc={rc})')
    rc, so = run(td / 'a.xlsx', out, '2020-04-30')
    chk('d 마지막 값 2020-04-21 · 기준 04-30(9역일) → rc 3 신선도 미달', rc == 3, f'(rc={rc})')
    rc, _ = run(td / 'a.xlsx', out, '2020-04-28')
    chk('d2 경계: 7역일 = 통과(rc 0)', rc == 0, f'(rc={rc})')

real = ROOT / '03_Universe' / 'Global_Macro.xlsx'
if real.exists():
    sys.path.insert(0, str(ING.parent))
    import global_macro_ingest as G
    cols, _ = G.read_sheet(real)
    syms = [c['symbol'] for c in cols]
    chk('e 정본 질의서 심볼 전부 등록', bool(syms) and all(s in G.SERIES for s in syms), f'({syms})')
    rules = json.load(open(ROOT / '06_Registry' / 'fred_availability_rules.json', encoding='utf-8'))
    ids = {s['id'] for s in rules['series'] if s.get('status') == 'active'}
    chk('e 계열 id 마다 가용일 규칙(active) 존재', all(G.SERIES[s] in ids for s in syms))
else:
    print('  SKIP  e 정본 질의서 없음(통과 아님)')

print(f'\n결과: PASS={PASS} FAIL={FAIL}')
print(json.dumps({'test': 'global_macro_ingest', 'pass': PASS, 'fail': FAIL, 'total': PASS + FAIL}))
sys.exit(1 if FAIL else 0)
