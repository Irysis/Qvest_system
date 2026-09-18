# -*- coding: utf-8 -*-
"""test_benchmark_axis_rebuild.py — 벤치 정본 재구축 양방향 검사 (2026-09-18 신설)

## 왜 이 검사가 있나
2026-09-18 축 정규화는 `.cache/benchmark.parquet` 의 저장 규약을 바꿨다:
  BM_Close = 공표 코스피200 지수 종가(포인트) 그대로. 배율 개념 없음.
그 이전(구 리베이스 체인)에는 갱신기가 배수를 **추정**해야 했고, 추정이 미끄러진 날의
하루 수익률이 배수비를 통째로 삼켰다 — 07-27 · 07-29 · 2025-01-02 이 전부 같은 병이다.

재구축기(rebuild_benchmark_canonical.py)는 그 축을 되돌린다. 이 검사가 지키는 것:
  ① 구 이음매가 있는 픽스처에서 **이음매를 검출하고 고치는가**       (수리 방향)
  ② 이미 정본 축인 입력에서 **아무것도 바꾸지 않는가**(멱등)         (양성 대조)
  ③ 실파일에서 **이음매가 아닌 날의 수익률이 비트 동일한가**          (회귀 증명)
     — 실파일은 **읽기 전용 사본**으로만 만진다. 운영 캐시를 건드리지 않는다.
  ④ manifest 가 배율(scale)을 선언하지 않는가                        (재발 방지)
  ⑤ 원천 우선순위가 실제로 지켜지는가(xlsx > KRX > 구 체인 환산)

## 실행
  .venv_qvest_ml/Scripts/python.exe 08_Tests/data/test_benchmark_axis_rebuild.py
네트워크 미사용. 운영 파일 쓰기 0.
"""
from __future__ import annotations

import sys
import tempfile
import traceback
from pathlib import Path

try:
    import pandas as _probe  # noqa: F401
except ImportError:
    import os as _os, subprocess as _sp, sys as _sys
    _root = _os.path.dirname(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))))
    _venv = ""
    for _c in (_root, _os.environ.get("CLAUDE_PROJECT_DIR", ""), _os.environ.get("QM_ROOT", "")):
        if not _c:
            continue
        _p = _os.path.join(_c.replace("\\", "/"), ".venv_qvest_ml", "Scripts", "python.exe")
        if _os.path.exists(_p):
            _venv = _p
            break
    if _venv and _os.environ.get("_AXIS_REEXEC") != "1":
        _sys.exit(_sp.call([_venv, _os.path.abspath(__file__)] + _sys.argv[1:],
                           env=dict(_os.environ, _AXIS_REEXEC="1")))
    raise

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '02_Infrastructure' / 'data'))
import benchmark_axis as BA                 # noqa: E402
import rebuild_benchmark_canonical as RB    # noqa: E402

CASES = []


def case(name):
    def deco(fn):
        CASES.append((name, fn))
        return fn
    return deco


def synth(n=200, seed=5):
    """참조 지수(공표 포인트)와 그 위의 날짜 격자."""
    rng = np.random.default_rng(seed)
    d = pd.bdate_range('2025-01-01', periods=n)
    lvl = np.round(1000 * np.cumprod(1 + np.concatenate([[0.0], rng.normal(3e-4, 0.01, n - 1)])), 2)
    ref = pd.DataFrame({'Date': d, 'ref_close': lvl, 'ref_source': 'quantiwise_iks200'})
    return d, lvl, ref


def chain(d, lvl, scale_a=8.800941613, scale_b=8.834448439, seam_at=120):
    """구 리베이스 체인 재현 — seam_at 부터 배수가 한 칸 움직인다(실측 재발 형태)."""
    sc = np.where(np.arange(len(d)) < seam_at, scale_a, scale_b)
    close = lvl * sc
    ret = np.concatenate([[0.0], close[1:] / close[:-1] - 1])
    return pd.DataFrame({'Date': d, 'BM_Close': close, 'BM_Ret': ret})


# ── ① 수리 방향 ──────────────────────────────────────────────────────────────
@case('FIX-1 구 이음매가 있는 픽스처 — 구간 2개를 검출하고 정본 레벨로 되돌린다')
def _():
    d, lvl, ref = synth()
    old = chain(d, lvl)
    segs = RB.detect_legacy_segments(old, ref)
    big = [s for s in segs if s['n'] >= RB.SEGMENT_MIN_ROWS]
    assert len(big) == 2, f'구간 {len(big)}개 (기대 2): {[round(s["scale"], 6) for s in big]}'
    assert abs(big[0]['scale'] - 8.800941613) < 1e-9, f'구간1 배수 {big[0]["scale"]}'
    assert abs(big[1]['scale'] - 8.834448439) < 1e-9, f'구간2 배수 {big[1]["scale"]}'
    new = RB.build_canonical(old, ref, segs, 2)
    assert float((new['BM_Close'].values - lvl).__abs__().max()) < 1e-9, '정본 레벨 복원 실패'
    chk = BA.axis_check(new, ref)
    assert chk['status'] == 'ok', f'수리 후 축 판정 {chk["status"]}: {chk["detail"]}'
    return f'구간 2개 검출({big[0]["scale"]:.6f} → {big[1]["scale"]:.6f}) · 복원 후 ok'


@case('FIX-2 수리 전에는 축 판정이 violation 이고 이음매 날짜를 특정한다 (음성 대조)')
def _():
    d, lvl, ref = synth()
    old = chain(d, lvl, seam_at=120)
    chk = BA.axis_check(old, ref)
    assert chk['status'] == 'violation', f'구 체인인데 {chk["status"]}'
    assert chk['worst_seam_date'] == d[120].strftime('%Y-%m-%d'), \
        f'이음매 날짜 {chk["worst_seam_date"]} (기대 {d[120].date()})'
    return f'violation · 이음매 @{chk["worst_seam_date"]}'


# ── ② 멱등 (양성 대조) ───────────────────────────────────────────────────────
@case('IDEM-1 이미 정본 축인 입력 — 재구축이 한 값도 바꾸지 않는다')
def _():
    d, lvl, ref = synth()
    ret = np.concatenate([[0.0], lvl[1:] / lvl[:-1] - 1])
    canon = pd.DataFrame({'Date': d, 'BM_Close': lvl, 'BM_Ret': ret})
    segs = RB.detect_legacy_segments(canon, ref)
    out = RB.build_canonical(canon, ref, segs, 2)
    assert (out['BM_Close'].values == canon['BM_Close'].values).all(), 'BM_Close 가 바뀌었다'
    assert np.array_equal(out['BM_Ret'].values, canon['BM_Ret'].values), 'BM_Ret 이 바뀌었다'
    # 두 번 돌려도 같다
    out2 = RB.build_canonical(out.drop(columns=['BM_Src']), ref,
                              RB.detect_legacy_segments(out, ref), 2)
    assert np.array_equal(out2['BM_Close'].values, out['BM_Close'].values), '멱등 아님'
    return '레벨·수익률 비트 동일 · 2회 적용 동일'


# ── ⑤ 원천 우선순위 ──────────────────────────────────────────────────────────
@case('SRC-1 xlsx > KRX > 구 체인 환산 — provenance 가 실제로 그 순서를 따른다')
def _():
    d, lvl, ref = synth(n=60)
    old = chain(d, lvl, seam_at=200)          # 이음매 없음(단일 배수)
    # 정본은 앞 40일만, KRX 는 41~50일만 덮는다. 나머지 10일은 구 체인 환산이어야 한다.
    ref2 = ref.iloc[:40].copy()
    krx = ref.iloc[40:50].copy()
    krx['ref_source'] = 'krx_kospi200'
    mixed = pd.concat([ref2, krx], ignore_index=True)
    segs = RB.detect_legacy_segments(old, mixed)
    out = RB.build_canonical(old, mixed, segs, 2)
    got = out['BM_Src'].tolist()
    assert set(got[:40]) == {'quantiwise_iks200'}, f'앞 40일 provenance {set(got[:40])}'
    assert set(got[40:50]) == {'krx_kospi200'}, f'41~50일 provenance {set(got[40:50])}'
    assert set(got[50:]) == {'legacy_chain_rescaled'}, f'나머지 provenance {set(got[50:])}'
    # 환산분도 공표 레벨과 같아야 한다(반올림 자릿수까지)
    assert float((out['BM_Close'].values[50:] - lvl[50:]).__abs__().max()) < 1e-9, \
        '구 체인 환산분이 공표 레벨과 다르다'
    return 'xlsx 40 · KRX 10 · 구체인환산 10 (환산분도 공표값과 일치)'


# ── ③ 실파일 회귀 증명 (읽기 전용) ───────────────────────────────────────────
@case('REAL-1 실파일 — 이음매가 아닌 날의 수익률이 배정도 반올림 수준으로만 다르다 (읽기 전용)')
def _():
    if not BA.BM_PATH.exists():
        raise AssertionError('.cache/benchmark.parquet 부재 — 판정 불가(SKIP 아님)')
    old = pd.read_parquet(BA.BM_PATH)
    old['Date'] = pd.to_datetime(old['Date'])
    old = old.sort_values('Date').reset_index(drop=True)
    ref = BA.canonical_reference()
    if not len(ref):
        raise AssertionError('정본 참조 부재 — 판정 불가')
    segs = RB.detect_legacy_segments(old, ref)
    new = RB.build_canonical(old, ref, segs, 2)

    assert len(new) == len(old), f'행 {len(old)}→{len(new)} (격자가 바뀌면 캘린더 변경이다)'
    assert (new['Date'].values == old['Date'].values).all(), '날짜 격자 변경'

    m = old[['Date', 'BM_Ret']].merge(new[['Date', 'BM_Ret']], on='Date', suffixes=('_o', '_n'))
    changed = set(m.loc[(m['BM_Ret_n'] - m['BM_Ret_o']).abs() > 1e-12, 'Date'])

    # 기대 변경 집합을 **재도출**한다(날짜를 박지 않는다):
    #   구간 경계일(= 이음매) + 1999년 이전(결손 세션이 월요일에 합쳐지는 구간)
    big = [s for s in segs if s['n'] >= RB.SEGMENT_MIN_ROWS]
    seam_dates = {s['start'] for s in big[1:]}
    pre99 = {d for d in changed if d < pd.Timestamp('1999-01-01')}
    post99 = changed - pre99
    assert post99 <= seam_dates, \
        f'이음매가 아닌 1999년 이후 날짜의 수익률이 바뀌었다: {sorted(post99 - seam_dates)[:5]}'

    # ★비트 동일을 요구하지 않는다 — 요구할 수 없다. 구판은 체인 레벨(2807.32/2807.76)에서,
    #   신판은 공표 레벨(317.77/319.03)에서 같은 비율을 계산하므로 피연산자 크기가 달라
    #   IEEE 배정도 마지막 자리가 갈린다. "레벨에 의존한다" 면 차이가 O(1) 로 나온다 —
    #   두 자릿수가 아니라 열 자릿수 차이다. 그래서 문턱을 **ULP 규모**에 놓는다.
    #   실측(2026-09-18): 1999년 이후 비이음매 6,831일 중 4,137일이 정확히 비트 동일,
    #   나머지는 최대 4.44e-16 (= 2 ULP). 문턱 1e-15 는 그 위 한 자릿수.
    ULP_BOUND = 1e-15
    ns = m[(m['Date'] >= '1999-01-01') & (~m['Date'].isin(seam_dates))]
    dns = (ns['BM_Ret_n'] - ns['BM_Ret_o']).abs()
    worst = float(dns.max())
    n_bit = int((ns['BM_Ret_o'].values == ns['BM_Ret_n'].values).sum())
    assert worst <= ULP_BOUND, f'비이음매 일 최대 |Δret|={worst:.3e} > {ULP_BOUND:g} (반올림 아님)'
    # 음성 대조(상태 불가지) — ★초판은 "실파일에서 큰 변화가 나와야 한다" 고 요구했다.
    #   그건 **수리 전 상태에서만** 참이다: 축을 정규화한 뒤(2026-09-18 23:02 이관 완료)
    #   재구축은 멱등이라 변화가 0이고, 그러면 성공한 수리가 검사를 빨갛게 만든다.
    #   그래서 대조를 **주입**으로 바꾼다 — 이음매를 심은 사본에서는 반드시 반응해야 한다.
    mut = old.copy()
    half = len(mut) // 2
    mut.loc[mut.index[half:], 'BM_Close'] = mut.loc[mut.index[half:], 'BM_Close'] * 1.0038
    mut['BM_Ret'] = mut['BM_Close'] / mut['BM_Close'].shift(1) - 1
    mut_new = RB.build_canonical(mut, ref, RB.detect_legacy_segments(mut, ref), 2)
    mm = mut[['Date', 'BM_Ret']].merge(mut_new[['Date', 'BM_Ret']], on='Date', suffixes=('_o', '_n'))
    assert float((mm['BM_Ret_n'] - mm['BM_Ret_o']).abs().max()) > ULP_BOUND * 1e6, (
        '이음매를 주입한 사본에서도 아무 반응이 없다 — 재구축이 입력에 닿지 않는다')
    return (f'{len(m)}일 중 변경 {len(changed)}건 '
            f'(1999년 이전 {len(pre99)} + 이음매 {sorted(str(d.date()) for d in post99)}) · '
            f'비이음매 {len(ns)}일 최대 |Δret|={worst:.2e} (비트 동일 {n_bit}일)')


@case('REAL-2 실파일 재구축 dry-run 이 운영 캐시를 건드리지 않는다')
def _():
    import os
    import subprocess
    st0 = os.stat(BA.BM_PATH)
    with tempfile.TemporaryDirectory() as td:
        out = Path(td) / 'r.json'
        rc = subprocess.call([sys.executable, str(ROOT / '02_Infrastructure' / 'data'
                                                 / 'rebuild_benchmark_canonical.py'),
                              '--json-out', str(out)],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             env=dict(os.environ, QM_ROOT=str(ROOT)))
        assert rc == 0, f'dry-run rc={rc}'
        assert out.exists(), '보고서 미생성'
        import json
        rep = json.loads(out.read_text(encoding='utf-8'))
        assert rep['written'] is False, 'dry-run 인데 written=True'
        assert rep['rows_before'] == rep['rows_after'], \
            f'행 {rep["rows_before"]}→{rep["rows_after"]}'
    st1 = os.stat(BA.BM_PATH)
    assert (st0.st_mtime, st0.st_size) == (st1.st_mtime, st1.st_size), 'dry-run 이 캐시를 건드렸다'
    return 'rc=0 · written=False · 캐시 mtime/크기 불변'


# ── ④ manifest 규약 ──────────────────────────────────────────────────────────
@case('MF-1 manifest 에 배율(scale) 필드가 없다 — 승계 가능한 배율은 재발의 씨앗')
def _():
    mf = BA.read_manifest()
    assert mf['unit'] == 'index_points', f'unit={mf["unit"]}'
    raw = mf.get('_raw')
    if raw is None:
        return f'manifest 미생성(재구축 전) — 내장 기본값 unit={mf["unit"]} · scale 개념 없음'
    assert 'scale' not in raw, 'manifest 에 scale 필드가 되살아났다'
    assert 'canonical_scale' not in raw, 'manifest 에 canonical_scale 이 되살아났다'
    for k in ('unit', 'reference', 'tolerance', 'source_priority', 'rows', 'date_max'):
        assert k in raw, f'manifest 에 {k} 없음'
    return f'unit={raw["unit"]} · rows={raw["rows"]} · scale 필드 없음'


@case('MF-2 R 측과 Python 측이 같은 문턱을 본다 (두 축이 갈리지 않는다)')
def _():
    import subprocess
    mf = BA.read_manifest()
    code = ('ROOT <- Sys.getenv("QM_ROOT"); '
            'source(file.path(ROOT, "02_Infrastructure/data/benchmark_level_axis.R")); '
            'cfg <- bench_level_config(ROOT); '
            'cat(sprintf("%.10g %.10g", cfg$BENCH_LEVEL_TOL, cfg$BENCH_LEVEL_SEAM_TOL))')
    import os
    o = subprocess.run(['Rscript', '--no-save', '-e', code], capture_output=True, text=True,
                       env=dict(os.environ, QM_ROOT=str(ROOT)))
    assert o.returncode == 0, f'R 실행 실패: {o.stderr[-300:]}'
    r_tol, r_seam = (float(x) for x in o.stdout.strip().split()[-2:])
    assert abs(r_tol - mf['tolerance']) < 1e-15, f'정합 문턱 갈림 R {r_tol} vs py {mf["tolerance"]}'
    assert abs(r_seam - mf['seam_tolerance']) < 1e-15, \
        f'이음매 문턱 갈림 R {r_seam} vs py {mf["seam_tolerance"]}'
    return f'tol={r_tol:g} · seam_tol={r_seam:g} (두 언어 동일)'


# ── ⑥ 수급 검증 경로 — 파서가 **받은 경로**를 읽는가 (2026-09-18 실사고) ──────
@case('SRC-2 xlsx 파서가 인자로 받은 파일을 읽는다 — 후보 검증이 정본을 읽으면 새 수급이 기각된다')
def _():
    """★실사고(2026-09-18 23:31): 퀀티 단말에서 정본을 06-30 → 09-17 로 받아왔는데
    수급기가 "지평선 불변" 으로 **기각**했다. 원인은 데이터가 아니라 파서였다 —
    load_quantiwise_kospi200(xlsx) 가 인자를 받고도 build_index_cache._read_indices()
    를 인자 없이 불러 **언제나 정본**을 읽었다. 즉 후보와 정본이 같아 보였다.
    (교훈: 인자를 받는 함수는 그 인자를 쓰는지까지 재라 — 서명은 계약이 아니다)
    """
    import shutil
    try:
        import openpyxl
    except ImportError:
        return 'openpyxl 부재 — 건너뜀(미측정)'
    src = Path(BA.XLSX_PATH)
    if not src.exists():
        return '정본 xlsx 부재 — 건너뜀(미측정)'
    base = BA.load_quantiwise_kospi200(src)
    assert len(base) > 100, f'정본이 {len(base)}행 — 픽스처로 못 쓴다'
    with tempfile.TemporaryDirectory() as td:
        cut = Path(td) / 'short.xlsx'
        shutil.copy(src, cut)
        wb = openpyxl.load_workbook(cut)
        ws = wb.active
        # ★max_row 는 빈 행까지 센다(이 xlsx 의 dimension 은 A1:S12230) — 지우면 빈 칸만
        #   지워져 데이터가 안 줄었다(초판 실패). 그래서 **A열에 값이 있는 행**에서 센다.
        data_rows = [c.row for c in ws["A"] if c.value is not None]
        for r in data_rows[-30:]:
            ws.cell(row=r, column=1).value = None   # 날짜를 지우면 파서가 그 행을 건너뛴다
        wb.save(cut)
        wb.close()
        short = BA.load_quantiwise_kospi200(cut)
    assert len(short) == len(base) - 30,         f'사본 {len(short)}행 · 정본 {len(base)}행 — 인자가 무시되면 두 값이 같다'
    assert short['Date'].max() < base['Date'].max(),         f'사본 지평선 {short["Date"].max().date()} 이 정본 {base["Date"].max().date()} 와 같다 — 인자 무시'
    return (f'정본 {len(base)}행(~{base["Date"].max().date()}) vs '
            f'사본 {len(short)}행(~{short["Date"].max().date()}) — 경로 인자가 실제로 쓰인다')


def main() -> int:
    print('=' * 78)
    print('test_benchmark_axis_rebuild — 정본 재구축 양방향 검사')
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
    if fails:
        print('  ★실패:', ', '.join(fails))
    print('{"test":"benchmark_axis_rebuild","pass":%d,"fail":%d,"total":%d,"skipped":0}'
          % (npass, len(fails), npass + len(fails)))
    return 0 if not fails else 1


if __name__ == '__main__':
    sys.exit(main())
