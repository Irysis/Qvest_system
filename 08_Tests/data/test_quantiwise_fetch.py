# -*- coding: utf-8 -*-
"""test_quantiwise_fetch.py — 퀀티 정본 수급기 양방향 검사 (2026-09-18 신설)

## 왜
`quantiwise_fetch.py` 는 퀀티 단말 + 엑셀 애드인으로 정본 xlsx 를 다시 받아와 **검증 뒤에만**
정본 자리에 올린다. 이날 실측으로 물린 함정 셋을 고정한다:
  ① 드라이버 종료코드 → 의미 사상(0 교체 · 2 무변화 · 3 전제부재 · 1 실패)이 어긋나면
     로그인 창이 떠 있는 날도 '성공' 으로 읽히거나, 정상 무변화가 '실패' 로 읽힌다.
  ② **지평선이 안 늘었는데 교체하지 않는다** — 세션 없이 Refresh 하면 스탬프만 새로 찍힌
     같은 파일이 온다. mtime 만 바뀐 교체는 신선도 계기를 속인다.
  ③ 상태 파일은 **대상별**이다 — 다른 통합문서를 조회하면 벤치 상태가 덮였다(초판 결함).
실제 단말·엑셀은 부르지 않는다(subprocess 를 대체). 운영 파일 쓰기 0 — 전부 임시 폴더.

## 실행
  .venv_qvest_ml/Scripts/python.exe 08_Tests/data/test_quantiwise_fetch.py
"""
from __future__ import annotations

import json
import shutil
import sys
import tempfile
import traceback
import types
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '02_Infrastructure' / 'data'))
import quantiwise_fetch as QF   # noqa: E402

CASES = []


def case(name):
    def deco(fn):
        CASES.append((name, fn))
        return fn
    return deco


class _FakeRun:
    """subprocess.run 대체 — 드라이버가 낼 종료코드·JSON·결과 파일을 흉내 낸다."""
    def __init__(self, rc, result, message='', make_out=True):
        self.rc, self.result, self.message, self.make_out = rc, result, message, make_out

    def __call__(self, cmd, **kw):
        out = Path(cmd[cmd.index('-Out') + 1])
        jout = Path(cmd[cmd.index('-JsonOut') + 1])
        src = Path(cmd[cmd.index('-Source') + 1])
        if self.make_out and src.exists():
            shutil.copy(src, out)
        jout.write_text(json.dumps({'result': self.result, 'message': self.message}), encoding='utf-8')
        return types.SimpleNamespace(returncode=self.rc, stdout='[qw_refresh] fake\n', stderr='')


def _with_fake(rc, result, **kw):
    orig = QF.subprocess.run
    QF.subprocess.run = _FakeRun(rc, result, **kw)
    return orig


# ── ① 종료코드 사상 ──────────────────────────────────────────────────────────
@case('RC-1 드라이버 rc 사상 — 3 전제부재 · 2 무변화 · 1 실패 · 0 인데 파일 없음 = 실패 · 0 = 경로')
def _():
    if QF.os.name != 'nt':
        return 'Windows 전용 경로 — 건너뜀(미측정)'
    with tempfile.TemporaryDirectory() as td:
        wd = Path(td)
        src = wd / 'Benchmark_price.xlsx'
        src.write_bytes(b'PK-fake')
        seen = []
        for rc, res, kw, expect in [
            (3, 'login_required', {}, 'NotImplementedError'),
            (2, 'no_change', {}, 'None'),
            (1, 'error', {}, 'RuntimeError'),
            (0, 'updated', {'make_out': False}, 'RuntimeError'),
            (0, 'updated', {}, 'Path'),
        ]:
            orig = _with_fake(rc, res, **kw)
            try:
                got = QF._fetch_impl(wd, 10, False, target=src)
                kind = 'None' if got is None else ('Path' if isinstance(got, Path) else type(got).__name__)
            except Exception as e:
                kind = type(e).__name__
            finally:
                QF.subprocess.run = orig
            assert kind == expect, f'rc={rc}({res}) → {kind} (기대 {expect})'
            seen.append(f'{rc}→{kind}')
    return ' · '.join(seen)


# ── ② 지평선 판정 (양방향) ───────────────────────────────────────────────────
def _run_main(dest: Path, cand_desc: dict, before_desc: dict):
    """main() 을 격리 실행 — _fetch_impl · _describe 를 대체하고 교체 여부를 본다."""
    got_path = dest.with_name('cand.xlsx')
    got_path.write_bytes(b'CANDIDATE')
    o_fetch, o_desc, o_argv = QF._fetch_impl, QF._describe, sys.argv
    o_stat, o_root = QF.STATUS_PATH, QF.PROJECT_ROOT
    QF._fetch_impl = lambda *a, **k: got_path
    QF._describe = lambda p: dict(cand_desc) if Path(p) == got_path else dict(before_desc)
    QF.STATUS_PATH = dest.with_name('status.json')
    QF.PROJECT_ROOT = dest.parent
    sys.argv = ['quantiwise_fetch.py', '--dest', str(dest)]
    try:
        rc = QF.main()
    finally:
        QF._fetch_impl, QF._describe, sys.argv = o_fetch, o_desc, o_argv
        QF.STATUS_PATH, QF.PROJECT_ROOT = o_stat, o_root
    return rc, dest.read_bytes()


@case('HZ-1 지평선이 안 늘면 교체하지 않는다(rc 2) — 스탬프만 바뀐 파일로 정본을 덮지 않는다')
def _():
    with tempfile.TemporaryDirectory() as td:
        dest = Path(td) / 'Benchmark_price.xlsx'
        dest.write_bytes(b'ORIGINAL')
        rc, body = _run_main(dest, {'rows': 100, 'date_max': '2026-06-30'},
                             {'rows': 100, 'date_max': '2026-06-30'})
        assert rc == 2, f'rc={rc} (기대 2)'
        assert body == b'ORIGINAL', '정본이 바뀌었다'
    return 'rc=2 · 정본 불변'


@case('HZ-2 지평선이 늘면 교체한다(rc 0) — HZ-1 의 양성 대조')
def _():
    with tempfile.TemporaryDirectory() as td:
        dest = Path(td) / 'Benchmark_price.xlsx'
        dest.write_bytes(b'ORIGINAL')
        rc, body = _run_main(dest, {'rows': 155, 'date_max': '2026-09-17'},
                             {'rows': 100, 'date_max': '2026-06-30'})
        assert rc == 0, f'rc={rc} (기대 0)'
        assert body == b'CANDIDATE', '정본이 교체되지 않았다'
    return 'rc=0 · 정본 교체'


@case('HZ-3 행이 줄면 거부(rc 1) — 부분 응답으로 정본을 깎지 않는다')
def _():
    with tempfile.TemporaryDirectory() as td:
        dest = Path(td) / 'Benchmark_price.xlsx'
        dest.write_bytes(b'ORIGINAL')
        rc, body = _run_main(dest, {'rows': 90, 'date_max': '2026-09-17'},
                             {'rows': 100, 'date_max': '2026-06-30'})
        assert rc == 1 and body == b'ORIGINAL', f'rc={rc} · 교체={body != b"ORIGINAL"}'
    return 'rc=1 · 정본 불변'


# ── ③ 상태 파일은 대상별 ─────────────────────────────────────────────────────
@case('ST-1 상태 파일 분리 — 벤치 정본은 기존 이름, 다른 통합문서는 자기 이름(서로 덮지 않는다)')
def _():
    a = QF._status_path_for(QF.DEST)
    b = QF._status_path_for(QF.PROJECT_ROOT / '03_Universe' / 'Update_File' / 'OHLCVS_update.xlsx')
    assert a == QF.STATUS_PATH, f'벤치 상태 경로 {a}'
    assert b != a and 'OHLCVS_update' in b.name, f'다른 대상이 벤치 상태로 간다: {b}'
    return f'{a.name} · {b.name}'


@case('DS-1 비벤치 대상은 지수 파서를 쓰지 않는다(generic) — 벤치는 지수 파서')
def _():
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / 'x_update.xlsx'
        try:
            import openpyxl
        except ImportError:
            return 'openpyxl 부재 — 건너뜀(미측정)'
        wb = openpyxl.Workbook()
        ws = wb.active
        ws['A1'] = 'Refresh'
        for i, d in enumerate(['2026-08-27', '2026-08-28'], start=15):
            ws.cell(row=i, column=1).value = d
        wb.save(p)
        wb.close()
        d = QF._describe(p)
        assert d.get('kind') == 'generic', f'kind={d.get("kind")}'
        assert d.get('date_max') == '2026-08-28' and d.get('rows') == 2, d
    return f"generic · rows={d['rows']} · date_max={d['date_max']}"


def main() -> int:
    print('=' * 78)
    print('test_quantiwise_fetch — 퀀티 정본 수급기 양방향 검사')
    print('=' * 78)
    npass, fails = 0, []
    for name, fn in CASES:
        try:
            note = fn()
            npass += 1
            print(f'  PASS  {name}\n          {note}')
        except Exception as e:
            fails.append(name)
            print(f'  ★FAIL {name}\n          {type(e).__name__}: {e}')
            traceback.print_exc()
    print('-' * 78)
    print(f'  {npass}/{len(CASES)} PASS')
    print('{"test":"quantiwise_fetch","pass":%d,"fail":%d,"total":%d,"skipped":0}'
          % (npass, len(fails), npass + len(fails)))
    return 0 if not fails else 1


if __name__ == '__main__':
    sys.exit(main())
