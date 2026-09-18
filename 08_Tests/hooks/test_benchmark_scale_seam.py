"""test_benchmark_scale_seam.py — 벤치 축 트립와이어 검사기 (오프라인)

신설 2026-08-09 (도훈 "26년 수익률 이상 — 어제 고쳤는데 또").
**2026-09-18 전면 개정** — 검사 대상이 바뀌었다.

## 무엇이 바뀌었나
구판은 `patch_benchmark_parquet()` 가 **리베이스 체인**(지수 × 8.83)에 생 KPI200 을 이어
붙일 때 배수 추정이 미끄러지지 않는지를 쟀다. 2026-09-18 축 정규화로 그 경로 자체가
사라졌다 — `.cache/benchmark.parquet::BM_Close` 는 이제 **공표 코스피200 포인트 그대로**이고
붙이기는 순수 이어붙이기다. 추정할 것이 없으면 미끄러질 것도 없다.

## 이제 무엇을 재는가
붙이기 **전에** 서는 트립와이어가 진짜 위반에 실제로 발화하는가:
  T1 겹치는 날 레벨 불일치      T2 이음매(하루 사이 비율 계단)
  T3 경계 하루 수익률 상한      T4 심볼 정체(일간 수익률 대조)
  T5 **붙일 값**을 독립 원천(정본 xlsx · KRX)과 대조 — T1·T2 는 겹치는 날만 보므로
     단절이 이어붙임 경계에서 시작하면 구조적으로 못 본다(INJ-1b/1c 가 그 경계를 박제).
그리고 검사가 살아 있는가 — **돌연변이 대조**로 문턱을 무력화하면 INJ 가 통과해 버리는지.
(양성 대조 없는 계기는 방어선으로 세지 않는다.)

## 실행
  .venv_qvest_ml/Scripts/python.exe 08_Tests/hooks/test_benchmark_scale_seam.py
네트워크 미사용(fetch 를 monkeypatch). `.cache/benchmark.parquet` 원본 미접촉(tmpdir 사본만).
"""
from __future__ import annotations

import sys
import tempfile
import traceback
from pathlib import Path

import numpy as np
# ── (2026-08-22) 인터프리터 자기해결 — 배터리는 pandas 없는 python 으로 돈다.
#   ★없으면 SKIP 하지 않는다 — SKIP 은 "검사가 통과했다" 와 겉보기가 같다.
try:
    import pandas as _pd_probe  # noqa: F401
except ImportError:
    import os as _os, subprocess as _sp, sys as _sys
    # ★해석기 루트 ≠ 코드 루트. venv 는 main 체크아웃에만 있고 worktree 에는 없다.
    _root = _os.path.dirname(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))))
    _venv = ""
    for _cand in (_root, _os.environ.get("CLAUDE_PROJECT_DIR", ""), _os.environ.get("QM_ROOT", "")):
        if not _cand:
            continue
        _p = _os.path.join(_cand.replace("\\", "/"), ".venv_qvest_ml", "Scripts", "python.exe")
        if _os.path.exists(_p):
            _venv = _p
            break
    if _venv and _os.environ.get("_SEAM_REEXEC") != "1":
        _env = dict(_os.environ, _SEAM_REEXEC="1")
        _sys.exit(_sp.call([_venv, _os.path.abspath(__file__)] + _sys.argv[1:], env=_env))
    raise

import os
import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '02_Infrastructure' / 'data'))
import benchmark_axis as BA           # noqa: E402
import naver_benchmark_update as nbu  # noqa: E402

CASES = []


def case(name):
    def deco(fn):
        CASES.append((name, fn))
        return fn
    return deco


# ── 픽스처: 지수 포인트 그대로인 벤치 + 그 지수를 그대로 내는 가짜 Naver ────────
def mk_fixture(tmp: Path, n_hist: int = 80, n_new: int = 5, seed: int = 11):
    """returns (bm_path, naver_df, levels) — BM_Close 는 지수 레벨 **그대로**(배율 없음)."""
    rng = np.random.default_rng(seed)
    dates = pd.bdate_range('2026-05-01', periods=n_hist + n_new)
    lvl = 1000 * np.cumprod(1 + np.concatenate([[0.0], rng.normal(0.0003, 0.01, len(dates) - 1)]))
    lvl = np.round(lvl, 2)
    hist = pd.DataFrame({'Date': dates[:n_hist], 'BM_Close': lvl[:n_hist]})
    ret = hist['BM_Close'] / hist['BM_Close'].shift(1) - 1
    ret.iloc[0] = 0.0
    hist['BM_Ret'] = ret
    hist['BM_Src'] = 'quantiwise_iks200'
    p = tmp / 'benchmark.parquet'
    BA.write_benchmark_parquet(hist, p)
    naver = pd.DataFrame({'Date': dates, 'Close': lvl})       # 전 구간 (겹침 + 신규)
    return p, naver, lvl


EMPTY_REF = pd.DataFrame({'Date': pd.Series([], dtype='datetime64[ns]'),
                          'ref_close': pd.Series([], dtype='float64'),
                          'ref_source': pd.Series([], dtype='object')})


def run_updater(bm_path: Path, naver: pd.DataFrame, append: bool = True,
                ref: pd.DataFrame | None = None):
    """네트워크 없이 갱신기를 돌린다. returns (rc, rows_after, df_after).

    ★독립 원천(T5)도 **주입**한다 — 기본은 '원천 없음'. 검사가 운영 상태(.cache 의 실제
      xlsx/KRX)를 빌리면 그 상태를 고칠 때 픽스처가 깨진다(합성 레벨 1000 vs 실제 지수).
      원천을 재는 케이스는 자기 원천을 명시적으로 준다.
    """
    orig_fetch, orig_path, orig_ref = nbu.fetch_naver_kospi, nbu.BM_PATH, BA.canonical_reference
    nbu.fetch_naver_kospi = lambda *a, **k: naver.copy()
    nbu.BM_PATH = bm_path
    BA.canonical_reference = lambda *a, **k: (EMPTY_REF if ref is None else ref.copy())
    try:
        rc = nbu.run(start_date='2026-05-01', end_date='2026-12-31',
                     do_append=append, backup=False, quiet=True)
    finally:
        nbu.fetch_naver_kospi, nbu.BM_PATH = orig_fetch, orig_path
        BA.canonical_reference = orig_ref
    df = pd.read_parquet(bm_path)
    return rc, len(df), df


# ── 양성 대조 ────────────────────────────────────────────────────────────────
@case('POS-1 항등 이어붙이기 — 정상 입력은 통과하고 생 포인트가 그대로 들어간다')
def _():
    with tempfile.TemporaryDirectory() as td:
        p, naver, lvl = mk_fixture(Path(td))
        n0 = len(pd.read_parquet(p))
        rc, n1, df = run_updater(p, naver)
        assert rc == 0, f'rc={rc} (정상 입력인데 차단)'
        assert n1 == n0 + 5, f'행 {n0}→{n1} (기대 +5)'
        # 붙인 값이 **naver 레벨 그대로**인가 (배율 0)
        tail = df.tail(5).reset_index(drop=True)
        exp = naver.tail(5)['Close'].reset_index(drop=True)
        assert float((tail['BM_Close'] - exp).abs().max()) < 1e-12, '붙인 값이 생 레벨이 아니다'
        # 기존 구간 불변
        assert float((df.head(n0)['BM_Close'].values - lvl[:n0]).__abs__().max()) < 1e-12, '기존 구간 변경'
        return f'{n0}→{n1}행 · 붙인 값 = 생 KPI200 포인트 (배율 없음)'


@case('POS-2 기본 모드는 검증만 — 파일을 쓰지 않는다')
def _():
    with tempfile.TemporaryDirectory() as td:
        p, naver, _ = mk_fixture(Path(td))
        n0 = len(pd.read_parquet(p))
        rc, n1, _df = run_updater(p, naver, append=False)
        assert rc == 0 and n1 == n0, f'rc={rc} rows {n0}→{n1} (verify 인데 썼다)'
        return f'verify 모드 rc=0 · 행 {n0} 불변'


# ── 위반 주입 ────────────────────────────────────────────────────────────────
@case('INJ-1 스케일 이음매(겹치는 구간부터 ×1.0038) — 차단 + 캐시 미접촉')
def _():
    with tempfile.TemporaryDirectory() as td:
        p, naver, _ = mk_fixture(Path(td))
        before = pd.read_parquet(p)
        nv = naver.copy()
        # 실측 재발 배수비(2025-01-02 계단). 겹치는 구간 안에서 시작하게 둔다 —
        # 실제 축 단절은 시리즈 전체(또는 어느 날 이후 전부)에서 일어난다.
        nv.loc[nv.index[-20:], 'Close'] *= 1.0038
        rc, _n, after = run_updater(p, nv)
        assert rc == 1, f'rc={rc} — 이음매를 통과시켰다'
        assert before.equals(after), '차단했는데 캐시가 바뀌었다'
        return '차단(rc=1) + 캐시 비트 동일'


@case('INJ-1b 이어붙임 **경계에서만** 시작하는 단절 — 독립 원천(T5)이 잡는다')
def _():
    # ★이 경우가 T1·T2 의 사각이다: 겹치는 날이 하나도 안 바뀌므로 겹침 대조로는 안 보인다.
    #   그리고 그것이 재발했던 형태다(호출부가 `10 days ago` 라 이음매가 매일 전진).
    #   ⇒ 붙일 값 자체를 정본/KRX 와 대조하는 T5 가 필요하다.
    with tempfile.TemporaryDirectory() as td:
        p, naver, _ = mk_fixture(Path(td))
        before = pd.read_parquet(p)
        nv = naver.copy()
        nv.loc[nv.index[-5:], 'Close'] *= 1.0038        # 신규 5일만
        ref = naver.rename(columns={'Close': 'ref_close'}).copy()   # 정본은 원래 값을 안다
        ref['ref_source'] = 'quantiwise_iks200'
        rc, _n, after = run_updater(p, nv, ref=ref)
        assert rc == 1, f'rc={rc} — 경계 단절을 통과시켰다(T5 미발화)'
        assert before.equals(after), '차단했는데 캐시가 바뀌었다'
        return 'T5 차단(rc=1) + 캐시 비트 동일'


@case('INJ-1c 독립 원천이 그 날을 못 덮으면 — 통과하되 그것은 "미검증"이다 (정직한 한계)')
def _():
    # ★부재를 '정상' 으로 읽지 않는 것과, 없는 검증을 있는 척하지 않는 것은 같은 규율이다.
    #   원천이 아직 안 온 날은 여기서 못 잡는다 — 게이트 축 C 가 원천 도착 후에 잡는다.
    #   이 케이스는 그 한계를 **박제**한다(나중에 "잡혔어야 했는데" 라고 읽지 않도록).
    with tempfile.TemporaryDirectory() as td:
        p, naver, _ = mk_fixture(Path(td))
        nv = naver.copy()
        nv.loc[nv.index[-5:], 'Close'] *= 1.0038
        rc, _n, after = run_updater(p, nv)          # ref 미지정 = 원천 없음
        assert rc == 0, f'rc={rc} — 원천 부재인데 차단했다(그건 상시 빨강이 된다)'
        # 그러나 축 판정은 그 파일을 **미검증**으로 본다 — 초록을 만들지 않는다.
        chk = BA.axis_check(after, naver.rename(columns={'Close': 'ref_close'}))
        assert chk['status'] == 'violation', \
            f'원천이 도착하면 잡혀야 한다: {chk["status"]} — {chk["detail"]}'
        return '붙임은 통과(원천 부재) · 원천 도착 시 축 C 가 violation 으로 잡는다'


@case('INJ-2 레벨 불일치(겹치는 구간 ×8.834) — 차단')
def _():
    with tempfile.TemporaryDirectory() as td:
        p, naver, _ = mk_fixture(Path(td))
        nv = naver.copy()
        nv['Close'] = nv['Close'] / 8.834448439        # 캐시가 지수의 8.83배인 구판 상태 재현
        rc, _n, _df = run_updater(p, nv)
        assert rc == 1, f'rc={rc} — 8.83배 축 이탈을 통과시켰다'
        return '차단(rc=1)'


@case('INJ-3 하루 수익률 상한 초과(신규 첫날 -89%) — 차단')
def _():
    with tempfile.TemporaryDirectory() as td:
        p, naver, _ = mk_fixture(Path(td))
        nv = naver.copy()
        nv.loc[nv.index[-5:], 'Close'] *= 0.11          # 레벨 단절 = 큰 수익률로 드러난다
        rc, _n, _df = run_updater(p, nv)
        assert rc == 1, f'rc={rc} — 레벨 단절을 통과시켰다'
        return '차단(rc=1)'


@case('INJ-4 오심볼(코스피 종합 수천대) — 차단')
def _():
    with tempfile.TemporaryDirectory() as td:
        p, naver, _ = mk_fixture(Path(td))
        nv = naver.copy()
        nv['Close'] = nv['Close'] * 6.75                # 종합지수 스케일
        rc, _n, _df = run_updater(p, nv)
        assert rc == 1, f'rc={rc} — 종합지수를 코스피200 으로 받아들였다'
        return '차단(rc=1)'


# ── 돌연변이 대조 (검사가 살아 있는가) ────────────────────────────────────────
@case('MUT-1 트립와이어 문턱을 무력화하면 INJ-1 이 통과한다 — 검출력 실증')
def _():
    with tempfile.TemporaryDirectory() as td:
        p, naver, _ = mk_fixture(Path(td))
        nv = naver.copy()
        nv.loc[nv.index[-5:], 'Close'] *= 1.0038
        orig = nbu.tripwire
        nbu.tripwire = lambda *a, **k: []               # 돌연변이: 검사 제거
        try:
            rc, _n, _df = run_updater(p, nv)
        finally:
            nbu.tripwire = orig
        assert rc == 0, ('돌연변이에서도 차단됐다 — INJ-1 의 차단이 트립와이어 덕이 아닐 수 있다')
        return '문턱 제거 시 통과 = INJ-1 의 차단은 트립와이어가 한 일이다'


# ── 축 규약 (구판 잔재가 되살아나지 않는가) ───────────────────────────────────
@case('AXIS-1 갱신기에 배율 추정 경로가 남아 있지 않다')
def _():
    # ★소스 문자열 단정이 아니라 **모듈 표면**에서 잰다 — 이름이 살아 있으면 경로도 산다.
    dead = [n for n in ('SCALE_LOOKBACK_DAYS', 'SCALE_TOL', 'SEAM_MAX_RET',
                        'patch_benchmark_parquet') if hasattr(nbu, n)]
    assert not dead, f'구 배율 경로 잔존: {dead}'
    assert hasattr(nbu, 'tripwire'), '트립와이어 미배선'
    # ★설정 의존은 **실행 코드**에서만 본다 — docstring 이 "그 의존을 끊었다" 고 설명하므로
    #   원문 검사는 자기 설명에 걸린다(구판이 정확히 그 오탐으로 죽었다).
    import ast as _ast
    src = (ROOT / '02_Infrastructure' / 'data' / 'naver_benchmark_update.py').read_text(encoding='utf-8')
    tree = _ast.parse(src)
    body = tree.body[1:] if (tree.body and isinstance(tree.body[0], _ast.Expr)
                             and isinstance(tree.body[0].value, _ast.Constant)) else tree.body
    code = '\n'.join(_ast.unparse(n) for n in body)
    assert 'seam_guard_config' not in code, '벤치가 아직 종목-배관 설정을 읽는다(축 분리 실패)'
    # 음성 대조: docstring 제거가 검사까지 눈멀게 하지 않았는지
    assert 'seam_guard_config' in code + "\n_ = 'seam_guard_config.json'", \
        '돌연변이 무효 — 검사기가 눈멀었다'
    return '배율 상수 0 · seam_guard_config 의존 0(실행 코드) · tripwire 배선'


@case('AXIS-2 manifest 가 배율(scale)을 선언하지 않는다')
def _():
    mf = BA.read_manifest()
    assert mf['unit'] == 'index_points', f'unit={mf["unit"]}'
    raw = mf.get('_raw', {})
    assert 'scale' not in raw, 'manifest 에 scale 필드가 되살아났다 — 승계 가능한 배율은 재발의 씨앗'
    return f'unit={mf["unit"]} · tol={mf["tolerance"]:g} · scale 필드 없음'


# ── 원자성 (저장 단일점) ──────────────────────────────────────────────────────
@case('ATOM-1 tmp→replace — 대상을 열지 않는다')
def _():
    import ast as _ast
    import inspect as _inspect
    fn = _ast.parse(_inspect.getsource(BA.atomic_write_table).lstrip()).body[0]
    stmts = fn.body[1:] if (isinstance(fn.body[0], _ast.Expr)
                            and isinstance(fn.body[0].value, _ast.Constant)) else fn.body
    fbody = '\n'.join(_ast.unparse(s) for s in stmts)
    assert 'os.replace' in fbody, 'os.replace 미사용'
    assert 'copy' not in fbody, f'copy 폴백 존재 — 절단원: {fbody[:120]}'
    assert 'os.remove(path)' not in fbody and 'os.unlink(path)' not in fbody, '대상 선삭제 존재'
    # 음성 대조: 검사기가 눈멀지 않았는지
    assert 'copy' in fbody + '\n    shutil.copy(tmp, path)', '돌연변이 무효 — 검사기가 눈멀었다'
    return '본문에 os.replace · copy/선삭제 0'


@case('ATOM-2 쓰기 실패 시 원본 불변 + tmp 보존')
def _():
    with tempfile.TemporaryDirectory() as td:
        p, _naver, _ = mk_fixture(Path(td))
        n0 = len(pd.read_parquet(p))
        import pyarrow as pa
        bad = pa.table({'Date': pa.array([], type=pa.date32())})
        orig = BA.pq.read_metadata
        BA.pq.read_metadata = lambda _p: type('M', (), {'num_rows': -1})()
        try:
            BA.atomic_write_table(pa.table({'Date': bad['Date']}), p)
            raise AssertionError('tmp 검증 실패인데 통과했다')
        except RuntimeError:
            pass
        finally:
            BA.pq.read_metadata = orig
        assert len(pd.read_parquet(p)) == n0, f'원본 훼손 (기대 {n0}행)'
        return f'차단 + 원본 {n0}행 불변'


@case('ATOM-3 date32 유지 — POSIXct 회귀 차단')
def _():
    import pyarrow.parquet as _pq
    with tempfile.TemporaryDirectory() as td:
        p, naver, _ = mk_fixture(Path(td))
        run_updater(p, naver)
        t = str(_pq.read_schema(p).field('Date').type)
        assert t == 'date32[day]', f'Date 타입이 {t} (기대 date32[day])'
        return 'Date = date32[day]'


@case('ATOM-4 백업 보존 정책 — 최근 N개만 남는다')
def _():
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        for i in range(BA.BACKUP_KEEP + 4):
            (tmp / f'benchmark.parquet.bak_naver_patch_2026091{i:02d}_000000').write_text('x')
        gone = BA.prune_backups('benchmark.parquet.bak_naver_patch_*', cache=tmp)
        left = len(list(tmp.glob('benchmark.parquet.bak_naver_patch_*')))
        assert left == BA.BACKUP_KEEP, f'남은 {left} (기대 {BA.BACKUP_KEEP})'
        assert len(gone) == 4, f'정리 {len(gone)} (기대 4)'
        return f'{BA.BACKUP_KEEP + 4}개 → {left}개 (정리 {len(gone)})'


def main() -> int:
    print('=' * 78)
    print('test_benchmark_scale_seam — 벤치 축 트립와이어 검사기 (2026-09-18 개정)')
    print('=' * 78)
    npass = 0
    fails = []
    for name, fn in CASES:
        try:
            note = fn()
            npass += 1
            print(f'  PASS  {name}\n          {note}')
        except Exception as e:
            fails.append((name, e))
            print(f'  ★FAIL {name}\n          {type(e).__name__}: {e}')
            traceback.print_exc()
    print('-' * 78)
    print(f'  {npass}/{len(CASES)} PASS')
    if fails:
        print('  ★실패:', ', '.join(n for n, _ in fails))
    print('{"test":"benchmark_scale_seam","pass":%d,"fail":%d,"total":%d,"skipped":0}'
          % (npass, len(fails), npass + len(fails)))
    return 0 if not fails else 1


if __name__ == '__main__':
    sys.exit(main())
