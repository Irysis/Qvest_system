# -*- coding: utf-8 -*-
"""benchmark_axis.py — `.cache/benchmark.parquet` 축 규약 단일 정본 (Python 측, 2026-09-18 신설)

★왜 이 파일이 생겼나 (도훈 "도대체 몇 번째 버그냐", 2026-09-18)
  `.cache/benchmark.parquet::BM_Close` 는 **공표 코스피200 종가(포인트) 그대로**여야 한다.
  그런데 2026-07~09 내내 그 파일은 지수의 8.83배 위에 있는 **리베이스 체인**이었고,
  그래서 갱신기가 새 값을 붙일 때마다 "이 파일이 쓰던 배수" 를 추정해 되돌려야 했다.
  추정이 한 번 미끄러질 때마다 그 날 하루의 수익률이 배수비를 통째로 삼켰다 —
  같은 병이 07-27 · 07-29 · 2025-01-02 에 반복됐고, 앞의 둘만 날짜를 박은 일회성
  스크립트로 고쳐졌다(그래서 또 재발했다).

  ⇒ 이 파일은 **배율이라는 개념 자체를 없앤다.** 저장 규약은 하나다:
       BM_Close = 공표 코스피200 지수 레벨(포인트). 붙이기 = 순수 이어붙이기.
     추정할 것이 없으면 추정이 미끄러질 수도 없다.

정본 원천 우선순위 (도훈 2026-09-18 지시 — 인터넷이 아니라 인프라 안에서):
  1. `03_Universe/Benchmark_price.xlsx` (QuantiWise IKS200) — build_index_cache.py 경로.
     이미 **생 포인트 그대로** 쓴다(배율 없음). 이것이 정본이다.
  2. `.cache/krx/kospi_index/*.parquet` (KRX 공표 지수 스냅샷) — xlsx 가 못 덮는 최근 구간만.
  3. (재구축 한정) 구 체인 ÷ 실측 구간배수 — 위 둘 다 없는 날의 **구제**용이고
     provenance 에 그렇게 기록된다. 새로 만드는 축이 아니라 이미 있는 값의 환산이다.
  ※ Naver chart API 는 **정본에서 빠졌다** — 교차검증(트립와이어) 전용.

소비자: rebuild_benchmark_canonical.py · naver_benchmark_update.py
       (R 측 정본은 benchmark_level_axis.R — 같은 규약을 같은 어휘로 적는다)
"""
from __future__ import annotations

import gc
import glob
import json
import os
import time
from datetime import datetime
from pathlib import Path

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

PROJECT_ROOT = Path(
    os.environ.get('CLAUDE_PROJECT_DIR') or os.environ.get('QM_ROOT')
    or Path(__file__).resolve().parents[2]
)
CACHE = PROJECT_ROOT / '.cache'
BM_PATH = CACHE / 'benchmark.parquet'
MANIFEST_PATH = CACHE / 'benchmark_axis.json'
XLSX_PATH = PROJECT_ROOT / '03_Universe' / 'Benchmark_price.xlsx'
KRX_INDEX_DIR = CACHE / 'krx' / 'kospi_index'

# ── 축 규약 (배율 필드 없음 — 규약이 곧 '지수 그대로' 다) ─────────────────────
AXIS_UNIT = 'index_points'
AXIS_REFERENCE = 'KOSPI200 (QuantiWise IKS200 / KRX 코스피 200)'
# ★한글 리터럴을 비교식에 직접 박지 않는다 — Windows 네이티브 인코딩 세션에서
#   parquet(UTF-8) 문자열과 바이트가 갈린다(benchmark_level_axis.R 과 같은 규약).
KRX_IDX_NM_KOSPI200 = '코스피 200'

# 정합 허용오차(상대). |BM/참조 - 1| 이 이 값을 넘으면 축 이탈.
#  ★정상 상태의 배수는 실측 1.000000(오차 <1e-6)이라 문턱은 사실상 아무 값이나 잡는다.
#    1e-4 로 조인 이유: 구 문턱 1e-2 는 "8.83배" 같은 대형 위반만 잡았고, 지수 자릿수
#    반올림(2dp, 상대 ~1e-5)보다 한 자릿수만 위에 두면 작은 이음매도 걸린다.
AXIS_TOL = 1e-4
# 연속 공통일 사이 **비율 변화**(이음매) 상한. 배율 추정이 미끄러진 자리의 지문이
#  정확히 이것이다 — 레벨은 연속인데 비율이 하루 사이 계단을 탄다.
AXIS_SEAM_TOL = 1e-4
# 공표 지수의 표기 자릿수. 구 체인을 환산할 때 이 자릿수로 되돌리면 공표값과
#  **정확히** 일치한다(실측: KRX 공통 106일 106/106, indices 공통 6,430일 6,430/6,430).
AXIS_DECIMALS = 2
# 하루 수익률 상한 — 이 값을 넘으면 '하루치 등락' 으로 설명되지 않는다.
#  ★데이터 근거: KR 가격제한폭 ±30% 가 rawdata 에 그대로 보인다(2016+ |Ret| q0.9999=0.3030).
#    0.30 으로 조이면 진짜 상한가를 오검거한다. 구 seam_guard_config.json::SEAM_MAX_RET 과
#    같은 값이고, 그 파일에서 **벤치 몫만** 이리로 옮겼다(종목 배관은 그쪽에 그대로 남는다).
AXIS_MAX_ABS_RET = 0.35

SOURCE_PRIORITY = ['quantiwise_iks200', 'krx_kospi200', 'legacy_chain_rescaled']

# 원자적 교체 규약 (atomic_json.R / atomic_parquet.R 과 동일)
REPLACE_RETRIES = 8
REPLACE_SLEEP_INIT = 0.02
REPLACE_SLEEP_CAP = 0.25


# ── 원자적 쓰기 ───────────────────────────────────────────────────────────────
def atomic_write_table(table: 'pa.Table', path) -> None:
    """tmp 에 쓴 뒤 os.replace 로 교체한다 — 대상 파일을 **열지 않는다**.

    ★왜 (2026-08-29 23:32 실사고 + 2026-08-30 실측, naver_benchmark_update.py 에서 이관):
      [측정 1] 제자리 쓰기는 조용히 자른다 — 쓰기 도중 죽으면 9,017행 → 500행이 되고
        그 결과물은 **정상적으로 읽힌다**(= 침묵 실패, 이 저장소의 반복 병).
      [측정 2] 대상이 mmap 돼 있으면 Windows 가 error 1224 로 거부한다. tmp→replace 는
        대상을 열지 않으므로 쓰기는 성공하고 교체만 재시도하면 된다.
    ★copy 폴백을 쓰지 않는다: replace 가 실패하는 유일한 실전 사유가 "소비자 점유 중"인데
      그 순간이 정확히 copy 가 파일을 제자리에서 찢는 순간이다.
    """
    path = str(path)
    tmp = path + f'.tmp{os.getpid()}'
    pq.write_table(table, tmp)

    # "썼다" 와 "읽을 수 있는 것을 썼다" 는 다른 명제다 — promote 전에 되읽어 행 수를 본다.
    n_tmp = pq.read_metadata(tmp).num_rows
    if n_tmp != table.num_rows:
        os.remove(tmp)
        raise RuntimeError(f'[benchmark_axis] tmp 검증 실패 — 정본 미갱신 '
                           f'(기대 {table.num_rows}행, 실측 {n_tmp}행)')

    gc.collect()
    last = None
    for i in range(REPLACE_RETRIES):
        try:
            os.replace(tmp, path)
            return
        except OSError as e:
            last = e
            time.sleep(min(REPLACE_SLEEP_CAP, REPLACE_SLEEP_INIT * 2 ** i))
    raise RuntimeError(
        f'[benchmark_axis] 원자적 교체 실패 (replace {REPLACE_RETRIES}회) — '
        f'정본 미갱신(원본 보존): {path}\n'
        f'  기록분은 {tmp} 에 보존됨. 최종 오류: {last}')


def write_benchmark_parquet(df: pd.DataFrame, path=BM_PATH) -> None:
    """benchmark.parquet 저장 단일점 — Date 는 date32(day) 로 정규화해 기록.

    ★2026-07-18 도훈 mandate: 구 writer 가 Date 를 timestamp[ns](R 에서 POSIXct)로 써서
      date32 를 기대하는 소비자와 조인이 조용히 all-NA 가 됐다(fdb_daily 베타 파생 54팩터
      전멸 사건). build_index_cache.py `_write_parquet` 와 같은 date32 로 통일한다.
    ★BM_Src(provenance)는 **선택 열**이다 — 없으면 쓰지 않는다. 구 3열 소비자 호환.
    """
    d = pd.to_datetime(df['Date']).dt.date
    arrs = {
        'Date': pa.array(d, type=pa.date32()),
        'BM_Close': pa.array(df['BM_Close'].astype('float64')),
        'BM_Ret': pa.array(df['BM_Ret'].astype('float64')),
    }
    if 'BM_Src' in df.columns:
        arrs['BM_Src'] = pa.array(df['BM_Src'].astype(str))
    atomic_write_table(pa.table(arrs), path)


# ── manifest ─────────────────────────────────────────────────────────────────
def read_manifest(path=MANIFEST_PATH) -> dict:
    """축 선언을 읽는다. 부재/파손이면 **폴백을 알리고** 내장 기본값을 쓴다.

    ★부재를 '정상' 으로 읽지 않는다 — 폴백은 조용하지 않다(일일 배관이라 죽지는 않는다).
    """
    fb = {'unit': AXIS_UNIT, 'reference': AXIS_REFERENCE, 'tolerance': AXIS_TOL,
          'seam_tolerance': AXIS_SEAM_TOL, 'decimals': AXIS_DECIMALS,
          'max_abs_daily_return': AXIS_MAX_ABS_RET,
          'source_priority': list(SOURCE_PRIORITY), '_fallback': True}
    try:
        with open(path, encoding='utf-8') as fh:
            m = json.load(fh)
        for k in ('unit', 'reference', 'tolerance', 'seam_tolerance', 'decimals',
                  'max_abs_daily_return', 'source_priority'):
            if m.get(k) is not None:
                fb[k] = m[k]
        fb['_fallback'] = False
        fb['_raw'] = m
    except Exception as e:
        print(f'  ⚠ [benchmark_axis] manifest 미적용({e.__class__.__name__}) — '
              f'내장 기본값 사용: {path}')
    fb['tolerance'] = float(fb['tolerance'])
    fb['seam_tolerance'] = float(fb['seam_tolerance'])
    fb['decimals'] = int(fb['decimals'])
    fb['max_abs_daily_return'] = float(fb['max_abs_daily_return'])
    return fb


def write_manifest(payload: dict, path=MANIFEST_PATH) -> None:
    """manifest 원자적 기록. ★scale 필드는 두지 않는다 — 규약이 곧 '지수 그대로' 다."""
    path = Path(path)
    tmp = str(path) + f'.tmp{os.getpid()}'
    with open(tmp, 'w', encoding='utf-8') as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=2)
    os.replace(tmp, str(path))


# ── 참조 지수 로더 ────────────────────────────────────────────────────────────
def load_krx_kospi200(dirpath=KRX_INDEX_DIR) -> pd.DataFrame:
    """KRX 일별 지수 스냅샷에서 코스피200 종가를 모은다. 없으면 0행.

    returns DataFrame(Date: datetime64, ref_close: float)
    """
    empty = pd.DataFrame({'Date': pd.Series([], dtype='datetime64[ns]'),
                          'ref_close': pd.Series([], dtype='float64')})
    dirpath = Path(dirpath)
    if not dirpath.is_dir():
        return empty
    rows = []
    for f in sorted(glob.glob(str(dirpath / 'kospi_index_*.parquet'))):
        try:
            d = pd.read_parquet(f)
        except Exception:
            continue
        if 'IDX_NM' not in d.columns or 'CLSPRC_IDX' not in d.columns:
            continue
        sel = d[d['IDX_NM'].astype(str).str.strip() == KRX_IDX_NM_KOSPI200]
        if not len(sel):
            continue
        r = sel.iloc[0]
        bas = str(r['BAS_DD']) if 'BAS_DD' in d.columns else os.path.basename(f)[13:21]
        try:
            dt = pd.to_datetime(bas, format='%Y%m%d')
            v = float(str(r['CLSPRC_IDX']).replace(',', ''))
        except Exception:
            continue
        if pd.isna(dt) or not (v > 0):
            continue
        rows.append((dt, v))
    if not rows:
        return empty
    out = pd.DataFrame(rows, columns=['Date', 'ref_close'])
    return out.drop_duplicates('Date', keep='last').sort_values('Date').reset_index(drop=True)


def load_quantiwise_kospi200(xlsx=XLSX_PATH) -> pd.DataFrame:
    """정본 xlsx(QuantiWise IKS200)에서 코스피200 종가를 읽는다. 없으면 0행.

    ★파서를 복제하지 않는다 — build_index_cache.py 의 `_read_indices()` 를 그대로 쓴다.
      xlsx 레이아웃(Code 행 7 · 데이터 행 12+)을 두 곳에 적으면 다음 사람이 한쪽만 고친다.
    """
    empty = pd.DataFrame({'Date': pd.Series([], dtype='datetime64[ns]'),
                          'ref_close': pd.Series([], dtype='float64')})
    if not Path(xlsx).exists():
        return empty
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        '_qvest_build_index_cache', str(Path(__file__).with_name('build_index_cache.py')))
    if spec is None or spec.loader is None:
        return empty
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)          # ★import 시 부작용 0 (main 은 __main__ 가드 안)
    df, _cols = mod._read_indices(str(xlsx))   # ★인자를 실제로 넘긴다(무시하면 후보 검증이 정본을 읽는다)
    if 'kospi200' not in df.columns:
        return empty
    out = df[['Date', 'kospi200']].rename(columns={'kospi200': 'ref_close'}).copy()
    out['Date'] = pd.to_datetime(out['Date'])
    out = out[out['ref_close'].notna() & (out['ref_close'] > 0)]
    return out.drop_duplicates('Date', keep='last').sort_values('Date').reset_index(drop=True)


def canonical_reference(prefer_krx_tail: bool = True) -> pd.DataFrame:
    """정본 참조 레벨 = xlsx(전기간) ∪ KRX(최근). 우선순위 = SOURCE_PRIORITY.

    returns DataFrame(Date, ref_close, ref_source)
    """
    qw = load_quantiwise_kospi200()
    kx = load_krx_kospi200()
    qw['ref_source'] = 'quantiwise_iks200'
    kx['ref_source'] = 'krx_kospi200'
    if not len(qw):
        return kx.reset_index(drop=True)
    if not len(kx):
        return qw.reset_index(drop=True)
    # xlsx 가 정본 — 겹치면 xlsx 를 남기고 KRX 는 xlsx 가 못 덮는 날만 보탠다.
    kx = kx[~kx['Date'].isin(set(qw['Date']))]
    out = pd.concat([qw, kx], ignore_index=True)
    return out.sort_values('Date').reset_index(drop=True)


# ── 축 판정 (붙이기 전 트립와이어 · 재구축 사후검증 공용) ──────────────────────
def axis_check(bm: pd.DataFrame, ref: pd.DataFrame, tol: float = None,
               seam_tol: float = None, window: int = 0) -> dict:
    """BM_Close 가 참조 지수와 **같은가**(정합) + 그 관계가 **변하지 않는가**(이음매).

    배율 개념 없음 — 잴 것은 "같다" 하나이고, 이음매 축은 그 '같음' 이 하루 사이
    계단을 타는지를 본다. 배율 추정이 미끄러진 자리의 지문이 정확히 그 계단이다.

    @param window  0 이면 전 구간, >0 이면 최근 그만큼의 공통 세션만.
    @return dict(status, n, max_dev, max_seam, worst_date, worst_seam_date, detail)
            status: 'ok' | 'violation' | 'no_measure'   ★부재를 '정상' 으로 읽지 않는다.
    """
    tol = AXIS_TOL if tol is None else float(tol)
    seam_tol = AXIS_SEAM_TOL if seam_tol is None else float(seam_tol)
    out = {'status': 'no_measure', 'n': 0, 'max_dev': float('nan'),
           'max_seam': float('nan'), 'worst_date': None, 'worst_seam_date': None,
           'tol': tol, 'seam_tol': seam_tol, 'detail': ''}
    if bm is None or not len(bm) or 'BM_Close' not in bm.columns:
        out['detail'] = 'benchmark 에 BM_Close 컬럼 없음'
        return out
    if ref is None or not len(ref):
        out['detail'] = '독립 참조 지수 부재(xlsx · KRX)'
        return out
    b = pd.DataFrame({'Date': pd.to_datetime(bm['Date']),
                      'BM_Close': pd.to_numeric(bm['BM_Close'], errors='coerce')})
    b = b[b['BM_Close'].notna() & (b['BM_Close'] > 0)]
    r = pd.DataFrame({'Date': pd.to_datetime(ref['Date']),
                      'ref_close': pd.to_numeric(ref['ref_close'], errors='coerce')})
    r = r[r['ref_close'].notna() & (r['ref_close'] > 0)]
    m = b.merge(r, on='Date', how='inner').sort_values('Date').reset_index(drop=True)
    if window and len(m) > window:
        m = m.tail(window).reset_index(drop=True)
    if len(m) < 2:
        out['n'] = len(m)
        out['detail'] = f'공통 세션 {len(m)}개 (<2) — 판정 불가'
        return out

    m['ratio'] = m['BM_Close'] / m['ref_close']
    dev = (m['ratio'] - 1.0).abs()
    seam = (m['ratio'] / m['ratio'].shift(1) - 1.0).abs()
    out['n'] = int(len(m))
    out['max_dev'] = float(dev.max())
    out['worst_date'] = m.loc[dev.idxmax(), 'Date'].strftime('%Y-%m-%d')
    if seam.notna().any():
        out['max_seam'] = float(seam.max())
        out['worst_seam_date'] = m.loc[seam.idxmax(), 'Date'].strftime('%Y-%m-%d')

    bad = []
    if out['max_dev'] > tol:
        bad.append(f"정합 이탈: |BM/지수-1| 최대 {out['max_dev']:.3e} "
                   f"> {tol:g} (@{out['worst_date']})")
    if out['max_seam'] == out['max_seam'] and out['max_seam'] > seam_tol:
        bad.append(f"이음매: 연속 공통일 사이 비율이 "
                   f"{out['max_seam']:.3e} 변화 > {seam_tol:g} (@{out['worst_seam_date']})")
    if bad:
        out['status'] = 'violation'
        out['detail'] = ' | '.join(bad) + f" — 공통 {out['n']}세션"
    else:
        out['status'] = 'ok'
        out['detail'] = (f"지수 일치 (최대편차 {out['max_dev']:.3e} "
                         f"· 최대이음매 {out['max_seam']:.3e} · "
                         f"공통 {out['n']}세션)")
    return out


# ── 경보 사이드카 (스케줄러가 읽는다) ──────────────────────────────────────────
ALERT_PATH = CACHE / 'benchmark_axis_alert.json'


def write_alert(kind: str, message: str, detail: dict = None, path=ALERT_PATH) -> None:
    """차단 사유를 사이드카에 남긴다 — 로그는 흘러가지만 파일은 남는다.

    cache_freshness_audit.R 의 `.cache/freshness_alert_state.json` 와 같은 계통.
    ★해제는 쓰기 성공 경로에서 clear_alert() 가 한다 — 상시 빨강을 만들지 않는다.
    """
    try:
        payload = {'schema': 'benchmark_axis_alert_v1', 'kind': kind,
                   'message': message, 'at': datetime.now().isoformat(timespec='seconds'),
                   'detail': detail or {}}
        tmp = str(path) + f'.tmp{os.getpid()}'
        with open(tmp, 'w', encoding='utf-8') as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=2)
        os.replace(tmp, str(path))
    except Exception:
        pass          # 경보 기록 실패가 본 작업의 실패를 덮지 않는다


def clear_alert(path=ALERT_PATH) -> None:
    try:
        if Path(path).exists():
            os.remove(str(path))
    except Exception:
        pass


# ── 백업 보존 정책 ────────────────────────────────────────────────────────────
BACKUP_KEEP = 10


def prune_backups(pattern: str, keep: int = BACKUP_KEEP, cache=CACHE) -> list:
    """오래된 백업을 정리하고 **삭제한 파일 목록**을 돌려준다.

    ★왜 (2026-09-18): `.cache/benchmark.parquet.bak_naver_patch_*` 가 130개 넘게 쌓여
      있었다. 백업은 보험이지 아카이브가 아니다 — 최근 `keep` 개만 남긴다.
      ※이 함수는 **앞으로 만들어지는 백업**에만 쓰인다. 기존 적체분 처분은 도훈 판단.
    """
    fs = sorted(glob.glob(str(Path(cache) / pattern)))
    if len(fs) <= keep:
        return []
    old = fs[:len(fs) - keep]
    gone = []
    for f in old:
        try:
            os.remove(f)
            gone.append(os.path.basename(f))
        except Exception:
            pass
    return gone
