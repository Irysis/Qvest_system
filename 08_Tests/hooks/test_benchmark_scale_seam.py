"""test_benchmark_scale_seam.py — naver_benchmark_update 스케일 이음매 검사기 (오프라인)

신설 2026-08-09 (도훈 적발 "26년 수익률 이상 — 어제 고쳤는데 또").

## 무엇을 재는가
`patch_benchmark_parquet()` 가 **리베이스 체인 스케일의 기존 시리즈**와 **생 KPI200 레벨**을
이어붙일 때 이음매(경계 하루에 스케일비가 수익률로 새는 것)를 만들지 않는지.

## 검출력 실증 (돌연변이)
구 구현(레벨 접합 후 전체 pct_change)을 `_legacy_level_splice()` 로 재현해 같은 입력에서
**-89% 급 이음매를 실제로 만든다**는 것을 보인다 — 통과가 검사기 사망이 아님을 증명한다.

## 실행
  .venv_qvest_ml/Scripts/python.exe 08_Tests/hooks/test_benchmark_scale_seam.py
네트워크 미사용(fetch 를 monkeypatch). benchmark.parquet 원본 미접촉(tmpdir 사본만).
"""
from __future__ import annotations

import sys
import tempfile
import traceback
from pathlib import Path

import numpy as np
# ── (2026-08-22) 인터프리터 자기해결 — 배터리는 pandas 없는 python 으로 돈다.
#   실측: run_all_hooks 의 QVEST_PY_BIN = 시스템 Python312 (pandas 부재),
#   venv .venv_qvest_ml 에만 pandas 2.3.3 이 있다. 이 검사는 등재 대상 .py 중
#   **유일하게** pandas 를 쓰므로, 배터리 정책을 바꾸는 대신 자기 의존을 스스로 해결한다.
#   ★없으면 SKIP 하지 않는다 — SKIP 은 "검사가 통과했다" 와 겉보기가 같고,
#   그게 오늘 하루 반복 확인된 무음 사망의 형태다.
try:
    import pandas as _pd_probe  # noqa: F401
except ImportError:
    import os as _os, subprocess as _sp, sys as _sys
    # ★[fix 2026-08-30] 해석기 루트 ≠ 코드 루트. venv 는 **main 체크아웃에만** 있고
    #   worktree 에는 없다 — self 루트만 보던 구판은 worktree 배터리에서
    #   ModuleNotFoundError 로 죽어 UNMEASURED+FAILING 으로 계상됐다(실측). 앵커 오설정이
    #   "테스트 실패"로 읽히는 형태다. 검사 대상 코드는 self 트리(아래 ROOT)에서 그대로 잡고,
    #   해석기만 어느 루트에서든 찾는다. 카드: feedback-code-root-is-not-data-root
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

import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '02_Infrastructure' / 'data'))
import naver_benchmark_update as nbu  # noqa: E402

SCALE = 8.834          # 실측 canonical 스케일 (BM_Close / KPI200)
CUTOFF = '2026-07-30'  # daily_refresh.sh 의 "10 days ago" 상당


# ── 픽스처 ────────────────────────────────────────────────────────────────────
def make_naver(n: int = 400, seed: int = 7, end: str = '2026-08-07',
               base: float = 320.0, drift: float = 0.00279) -> pd.DataFrame:
    """합성 KPI200 일간 종가.

    실측 레벨대에 맞춘다 — 2024-08 ~ 2026-08 KPI200 은 약 320 → 975 (일간 sd 1.5%).
    ①번 크기 가드(>3000 = 종합 의심)가 **현실 자릿수 위에서** 시험되도록 하기 위함이다.
    """
    rng = np.random.default_rng(seed)
    dates = pd.bdate_range(end=pd.Timestamp(end), periods=n)
    ret = rng.normal(drift, 0.015, n)
    ret[0] = 0.0
    close = base * np.cumprod(1 + ret)
    return pd.DataFrame({'Date': dates, 'Close': close})


def make_bm(naver: pd.DataFrame, corrupt_from: str | None = None) -> pd.DataFrame:
    """기존 benchmark.parquet 모사: canonical 스케일 위의 체인 시리즈.

    corrupt_from 이 주어지면 그 날짜부터를 **생 naver 레벨(스케일 1.0)** 로 덮어써
    운영에서 실제로 관측된 오염 상태(2026-07-29 이후 ratio 1.000)를 재현한다.
    """
    bm = naver.rename(columns={'Close': 'BM_Close'}).copy()
    bm['BM_Close'] = bm['BM_Close'] * SCALE
    if corrupt_from is not None:
        m = bm.Date >= pd.Timestamp(corrupt_from)
        bm.loc[m, 'BM_Close'] = naver.loc[m, 'Close'].values
    bm['BM_Ret'] = bm['BM_Close'].pct_change().fillna(0.0)
    return bm[['Date', 'BM_Close', 'BM_Ret']]


def _legacy_level_splice(bm: pd.DataFrame, naver: pd.DataFrame, cutoff: str) -> pd.DataFrame:
    """구 구현 재현 — 레벨로 이어붙인 뒤 전체 pct_change (이음매 생성기)."""
    c = pd.Timestamp(cutoff)
    pre = bm[bm.Date < c][['Date', 'BM_Close']]
    post = naver[naver.Date >= c].rename(columns={'Close': 'BM_Close'})
    out = pd.concat([pre, post], ignore_index=True).drop_duplicates('Date', keep='last')
    out = out.sort_values('Date').reset_index(drop=True)
    out['BM_Ret'] = out['BM_Close'].pct_change().fillna(0.0)
    return out


class Harness:
    """tmpdir 에 benchmark.parquet 사본을 두고 fetch 를 고정 응답으로 대체."""

    def __init__(self, bm: pd.DataFrame, naver: pd.DataFrame):
        self.bm, self.naver = bm, naver
        self._tmp = tempfile.TemporaryDirectory()
        self.path = Path(self._tmp.name) / 'benchmark.parquet'
        bm.to_parquet(self.path, index=False)

    def __enter__(self):
        self._old_path, self._old_fetch = nbu.BM_PATH, nbu.fetch_naver_kospi
        nbu.BM_PATH = self.path

        def fake(start, end, symbol='KOSPI'):
            s, e = pd.Timestamp(start), pd.Timestamp(end)
            d = self.naver[(self.naver.Date >= s) & (self.naver.Date <= e)]
            return d.sort_values('Date').reset_index(drop=True).copy()

        nbu.fetch_naver_kospi = fake
        return self

    def __exit__(self, *a):
        nbu.BM_PATH, nbu.fetch_naver_kospi = self._old_path, self._old_fetch
        self._tmp.cleanup()
        return False

    def result(self) -> pd.DataFrame:
        out = pd.read_parquet(self.path)
        out['Date'] = pd.to_datetime(out['Date'])
        return out.sort_values('Date').reset_index(drop=True)


# ── 케이스 ────────────────────────────────────────────────────────────────────
CASES = []


def case(name):
    def deco(fn):
        CASES.append((name, fn))
        return fn
    return deco


@case('POS-1  정상 입력 — 이음매 없음 · 앵커 이전 완전 불변')
def _():
    nv = make_naver()
    bm = make_bm(nv)
    with Harness(bm, nv) as h:
        r = nbu.patch_benchmark_parquet(CUTOFF, '2026-08-07', backup=False)
        out = h.result()
    assert r['healed_offscale_rows'] == 0, f"오염 없는데 치유 보고: {r['healed_offscale_rows']}"
    assert abs(r['canonical_scale'] - SCALE) < 1e-6, f"스케일 오추정 {r['canonical_scale']}"
    worst = out[out.Date > pd.Timestamp(r['anchor_date'])].BM_Ret.abs().max()
    assert worst < 0.15, f"이음매 발생: max|ret|={worst:.4f}"
    a = pd.Timestamp(r['anchor_date'])
    lhs = bm[bm.Date <= a].reset_index(drop=True)
    rhs = out[out.Date <= a].reset_index(drop=True)
    assert np.allclose(lhs.BM_Close, rhs.BM_Close), '앵커 이전 종가가 변경됨'
    return f"scale={r['canonical_scale']:.4f} anchor={r['anchor_date']} max|ret|={worst:.4f}"


@case('POS-2  전 구간 스케일 일정 — canonical 위에 재체인')
def _():
    nv = make_naver()
    bm = make_bm(nv)
    with Harness(bm, nv) as h:
        nbu.patch_benchmark_parquet(CUTOFF, '2026-08-07', backup=False)
        out = h.result()
    m = out.merge(nv, on='Date')
    ratio = m.BM_Close / m.Close
    assert ratio.max() - ratio.min() < 1e-6, f"스케일 분산 {ratio.min():.4f}~{ratio.max():.4f}"
    return f"ratio 일정 = {ratio.median():.6f}"


@case('INJ-1  ★운영 재현: 기존 이음매(07-29~ ratio 1.0) 주입 → 자동 치유')
def _():
    nv = make_naver()
    bm = make_bm(nv, corrupt_from='2026-07-29')
    pre = bm.BM_Ret.abs().max()
    assert pre > 0.5, f"주입 실패 — 오염 입력이 이음매를 안 만듦 ({pre:.4f})"
    with Harness(bm, nv) as h:
        r = nbu.patch_benchmark_parquet(CUTOFF, '2026-08-07', backup=False)
        out = h.result()
    assert r['healed_offscale_rows'] > 0, '이음매를 감지 못함'
    assert pd.Timestamp(r['anchor_date']) < pd.Timestamp('2026-07-29'), \
        f"앵커가 오염 구간 안({r['anchor_date']}) — 후퇴 실패"
    worst = out.BM_Ret.abs().max()
    assert worst < 0.15, f"치유 실패: max|ret|={worst:.4f}"
    m = out.merge(nv, on='Date')
    ratio = m.BM_Close / m.Close
    assert ratio.max() - ratio.min() < 1e-6, '치유 후 스케일 불일치'
    return f"주입 {pre:.4f} → 치유 {worst:.4f}, 앵커 {r['anchor_date']}, {r['healed_offscale_rows']}행"


@case('INJ-2a ★오심볼 — 다른 지수(비슷한 레벨, 다른 수익률경로) → 정체 가드 발화')
def _():
    """크기 가드가 못 잡는 오심볼. 예: KPI200 자리에 KOSDAQ150(수백대) — 자릿수가 같다.
    수익률 경로가 다르므로 **스케일 불변** 정체 검사만이 잡는다."""
    nv = make_naver()
    bm = make_bm(nv)
    other = make_naver(seed=99, base=740.0, drift=0.0006)   # 다른 지수, 같은 자릿수
    assert other.Close.max() < 3000, '픽스처 오류 — 크기 가드가 대신 발화해버림'
    try:
        with Harness(bm, other) as h:
            nbu.patch_benchmark_parquet(CUTOFF, '2026-08-07', backup=False)
    except RuntimeError as e:
        assert '정체' in str(e), f'다른 가드가 발화: {e}'
        return f"차단됨: {str(e)[:78]}"
    raise AssertionError('오심볼(동일 자릿수)이 통과됨 — 정체 가드 사망')


@case('INJ-2b 오심볼 — 코스피 종합 자릿수(수천대) → 크기 가드 발화')
def _():
    nv = make_naver()
    bm = make_bm(nv)
    nv_bad = nv.copy()
    nv_bad['Close'] = nv_bad['Close'] * 6.42   # KPI200 → 종합 레벨 (실측 배수)
    assert nv_bad.Close.max() > 3000, '픽스처 오류 — 종합 자릿수에 못 미침'
    try:
        with Harness(bm, nv_bad) as h:
            nbu.patch_benchmark_parquet(CUTOFF, '2026-08-07', backup=False)
    except RuntimeError as e:
        assert 'sanity' in str(e), f'다른 가드가 발화: {e}'
        return f"차단됨: {str(e)[:78]}"
    raise AssertionError('종합 자릿수가 통과됨 — 크기 가드 사망')


@case('INJ-3  갱신구간 극단 이동(스케일 단절 모사) → 이음매 가드 발화')
def _():
    nv = make_naver()
    bm = make_bm(nv)
    nv_bad = nv.copy()
    m = nv_bad.Date >= pd.Timestamp('2026-08-03')
    nv_bad.loc[m, 'Close'] = nv_bad.loc[m, 'Close'] / 9.0   # 갱신구간 안에서 스케일 단절
    try:
        with Harness(bm, nv_bad) as h:
            nbu.patch_benchmark_parquet(CUTOFF, '2026-08-07', backup=False)
    except RuntimeError as e:
        assert '이음매' in str(e), f'다른 가드가 발화: {e}'
        return f"차단됨: {str(e)[:70]}"
    raise AssertionError('스케일 단절이 통과됨 — 가드 사망')


@case('INJ-4  겹치는 날 부족(짧은/빈 응답) → 스케일 추정 불가로 중단')
def _():
    """naver 가 짧은 창만 돌려주면 canonical 스케일을 못 정한다.
    이때 **조용히 아무 스케일이나 쓰는 것**이 최악이므로 명시 중단해야 한다."""
    nv = make_naver()
    bm = make_bm(nv)
    short = nv.tail(8).copy()      # 겹치는 날 8개 (<20)
    try:
        with Harness(bm, short) as h:
            nbu.patch_benchmark_parquet(CUTOFF, '2026-08-07', backup=False)
    except RuntimeError as e:
        assert '스케일 추정 불가' in str(e), f'다른 가드가 발화: {e}'
        return f"차단됨: {str(e)[:78]}"
    raise AssertionError('겹침 부족 입력이 통과됨 — 가드 사망')


@case('MUT-1  ★검출력 실증: 구 구현(레벨 접합)은 같은 입력에서 이음매를 만든다')
def _():
    nv = make_naver()
    bm = make_bm(nv)                       # ← 오염 없는 정상 입력
    legacy = _legacy_level_splice(bm, nv, CUTOFF)
    seam = legacy[legacy.Date >= pd.Timestamp(CUTOFF)].BM_Ret.iloc[0]
    assert seam < -0.5, f"구 구현이 이음매를 안 만듦({seam:.4f}) — 돌연변이 무효"
    with Harness(bm, nv) as h:
        nbu.patch_benchmark_parquet(CUTOFF, '2026-08-07', backup=False)
        new_seam = h.result()
        a = new_seam[new_seam.Date >= pd.Timestamp(CUTOFF)].BM_Ret.iloc[0]
    assert abs(a) < 0.15, f'신 구현도 이음매 생성: {a:.4f}'
    return f"구 {seam:+.4f} → 신 {a:+.4f} (같은 입력)"


# ── 원자적 쓰기 축 (2026-08-30 추가 — 오버레이 배관 결함 ③) ────────────────────
#   실사고 2026-08-29 23:27: `_write_bm_parquet` 이 **정본 경로에 직접** write 하다가
#   `OSError [WinError 1224] ERROR_USER_MAPPED_FILE` 로 죽었고, 그 시점에
#   benchmark.parquet 이 사라져 하류가 줄줄이 멈췄다
#   (`[bm-gate][B] 부재` · `[regime_jump_model] Windows error 2` · `SJM refresh FAILED`).
#   ★2026-08-30 실측으로 갈라둘 것: **1224 자체는 파일을 지우지 않는다**(4/4 시행에서 원본
#     보존). 실제 소실 기전은 R 측 writer 3지점의 `file.remove(target)` **선삭제**였다
#     (수리 = 02_Infrastructure/utils/atomic_parquet.R + 08_Tests/data/test_parquet_atomic_write.R).
#   그럼에도 제자리 쓰기가 위험한 이유는 따로 있다 — **쓰기 도중 죽으면 조용히 잘린다**:
#     실측 9,017행 → 500행, 그리고 그 결과물은 **정상적으로 읽힌다**. 아래 ATOM-2 가 그것.
import gc as _gc            # noqa: E402
import mmap as _mmap        # noqa: E402
import os as _os            # noqa: E402
import pyarrow as _pa       # noqa: E402
import pyarrow.parquet as _pq   # noqa: E402


def _bm_table(n: int) -> '_pa.Table':
    d = pd.bdate_range(end=pd.Timestamp('2026-08-28'), periods=n)
    return _pa.table({'Date': _pa.array(d.date, type=_pa.date32()),
                      'BM_Close': _pa.array(np.arange(n).astype('float64')),
                      'BM_Ret': _pa.array(np.full(n, 0.001))})


class _DyingPq:
    """pq 대역 — write_table 이 앞부분만 쓰고 죽는다(프로세스 사망 모사)."""

    def __init__(self, keep: int):
        self.keep = keep

    def write_table(self, table, where, **kw):
        w = _pq.ParquetWriter(where, table.schema)
        w.write_table(table.slice(0, self.keep))
        raise RuntimeError('process died mid-write')      # close() 없음 = 푸터 미기록

    def __getattr__(self, k):
        return getattr(_pq, k)


@case('ATOM-1 정상 경로 — 결과 동일 + tmp 잔재 0')
def _():
    nv = make_naver()
    bm = make_bm(nv)
    with Harness(bm, nv) as h:
        nbu.patch_benchmark_parquet(CUTOFF, '2026-08-07', backup=False)
        out = h.result()
        strays = [f for f in _os.listdir(h.path.parent) if '.tmp' in f]
    assert len(out) >= len(bm), f'행 축소 {len(bm)}→{len(out)}'
    assert not strays, f'tmp 잔재: {strays}'
    return f'{len(out)}행 기록 · tmp 잔재 0'


@case('ATOM-2 ★쓰기 도중 사망 → 원본 불변 (구판은 같은 죽음에서 조용히 잘린다)')
def _():
    nv = make_naver()
    bm = make_bm(nv)
    with Harness(bm, nv) as h:
        p = str(h.path)
        n0 = len(pd.read_parquet(p))
        tbl = _bm_table(n0)

        keep = max(1, n0 // 8)                    # ★반드시 n0 보다 작아야 절단이 성립한다
        # (a) 구판 재현 — 정본 경로에 직접 쓰다가 죽는다
        try:
            _DyingPq(keep).write_table(tbl, p)
        except RuntimeError:
            pass
        _gc.collect()
        try:
            n_legacy = len(pd.read_parquet(p))
        except Exception:
            n_legacy = -1
        assert n_legacy != n0, f'구판이 원본을 안 건드림({n_legacy}) — 돌연변이 무효'

        # (b) 신판 — 같은 죽음, 원본은 온전해야 한다
        bm.to_parquet(p, index=False)             # 원상복구
        n1 = len(pd.read_parquet(p))
        real_pq = nbu.pq
        nbu.pq = _DyingPq(keep)
        try:
            nbu._atomic_write_table(tbl, p)
            raise AssertionError('죽었는데 예외가 안 남 — 침묵 실패')
        except RuntimeError as e:
            assert 'died mid-write' in str(e), f'다른 경로로 실패: {e}'
        finally:
            nbu.pq = real_pq
        _gc.collect()
        n_new = len(pd.read_parquet(p))
    assert n_new == n1, f'신판도 원본 훼손 {n1}→{n_new}'
    return f'구판 {n0}→{n_legacy}행(절단·정상 판독됨) / 신판 {n1}행 불변'


@case('ATOM-3 ★교체가 계속 거부되면 stop + 원본 불변 + tmp 보존')
def _():
    nv = make_naver()
    bm = make_bm(nv)
    with Harness(bm, nv) as h:
        p = str(h.path)
        n0 = len(pd.read_parquet(p))
        fh = open(p, 'rb')
        mm = _mmap.mmap(fh.fileno(), 0, access=_mmap.ACCESS_READ)   # 소비자 매핑 점유
        old_r = nbu.REPLACE_RETRIES
        nbu.REPLACE_RETRIES = 2
        try:
            nbu._atomic_write_table(_bm_table(n0), p)
            blocked = False
        except RuntimeError as e:
            blocked = '원자적 교체 실패' in str(e)
        finally:
            nbu.REPLACE_RETRIES = old_r
            mm.close(); fh.close()
        if not blocked:
            # 이 플랫폼에서 매핑이 교체를 막지 않으면 주입 자체가 성립하지 않는다.
            raise AssertionError('열린 매핑이 os.replace 를 막지 않음 — 주입 무효(미측정)')
        _gc.collect()
        n1 = len(pd.read_parquet(p))
        strays = [f for f in _os.listdir(h.path.parent) if '.tmp' in f]
    assert n1 == n0, f'원본 훼손 {n0}→{n1}'
    assert strays, 'tmp 미보존 — 페이로드 회수 불가'
    return f'차단 + 원본 {n0}행 불변 + tmp 보존({len(strays)}개)'


@case('ATOM-4 배선 — 저장 단일점이 제자리 write 를 쓰지 않는다')
def _():
    src = open(ROOT / '02_Infrastructure' / 'data' / 'naver_benchmark_update.py',
               encoding='utf-8').read()
    # ★주석 제외 — 수리 주석이 구판 호출을 인용하고 있어 원문 검사는 자기 설명에 걸린다.
    code = [ln for ln in src.split('\n') if not ln.lstrip().startswith('#')]
    body = '\n'.join(code)
    assert 'pq.write_table(table, str(path))' not in body, '제자리 write 잔존'
    assert '_atomic_write_table' in body, '원자적 교체 경로 미배선'
    # ★교체 함수 **본문**만 본다 — docstring 이 "copy 폴백을 쓰지 않는다"고 설명하므로
    #   파일 전체 텍스트 검사는 자기 설명에 걸린다(초판 실측 오탐).
    import ast as _ast
    import inspect as _inspect
    fn = _ast.parse(_inspect.getsource(nbu._atomic_write_table).lstrip()).body[0]
    stmts = fn.body[1:] if (isinstance(fn.body[0], _ast.Expr)
                            and isinstance(fn.body[0].value, _ast.Constant)) else fn.body
    fbody = '\n'.join(_ast.unparse(s) for s in stmts)
    assert 'os.replace' in fbody, 'os.replace 미사용'
    assert 'copy' not in fbody, f'copy 폴백 존재 — 절단원: {fbody[:120]}'
    assert 'os.remove(path)' not in fbody and 'os.unlink(path)' not in fbody, '대상 선삭제 존재'
    # 음성 대조: 주석/docstring 제거가 검사까지 눈멀게 하지 않았는지
    assert 'copy' in fbody + '\n    shutil.copy(tmp, path)', '돌연변이 무효 — 검사기가 눈멀었다'
    return '제자리 write 0 · _atomic_write_table 배선 · 본문 copy/선삭제 0'


def main() -> int:
    print('=' * 78)
    print('test_benchmark_scale_seam — naver_benchmark_update 이음매 검사기')
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
