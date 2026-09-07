"""
naver_benchmark_update.py — benchmark.parquet 정확한 Naver chart API 기반 갱신

도훈 mandate 2026-05-27:
- benchmark.parquet의 Date label mislabel bug 발견 (5/27 row가 사실 5/26 데이터)
- xlsx (QuantiWise) 5/15까지만 가용, 그 이후는 mislabel
- Solution: Naver chart API (https://api.finance.naver.com/siseJson.naver) 직접 사용

Cron 통합:
- daily_refresh.sh에 추가 step (build_cache.R 후 또는 별도)
- 매일 0:03 KST 실행, latest KOSPI 종합 종가 patch

Source 우선순위 (도훈 mandate 2026-05-27):
1. Naver chart API (한국 데이터)
2. yfinance (차선)
3. QuantiWise xlsx (영업일 판단만)
"""
from __future__ import annotations
import argparse
import ast
import gc
import shutil
import time
from pathlib import Path
from datetime import datetime

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
import requests


import os
PROJECT_ROOT = Path(os.environ.get('CLAUDE_PROJECT_DIR') or os.environ.get('QM_ROOT') or Path(__file__).resolve().parents[2])
BM_PATH = PROJECT_ROOT / '.cache' / 'benchmark.parquet'
NAVER_API = "https://api.finance.naver.com/siseJson.naver"


def fetch_naver_kospi(start_yyyymmdd: str, end_yyyymmdd: str, symbol: str = 'KOSPI') -> pd.DataFrame:
    """Fetch KOSPI 종합 (or KPI200) daily Close from Naver chart API.

    Args:
        start_yyyymmdd: 'YYYYMMDD' format
        end_yyyymmdd: 'YYYYMMDD' format
        symbol: 'KOSPI' (코스피 종합) | 'KPI200' (코스피 200) | 'KOSDAQ'

    Returns:
        DataFrame with Date, Close (BM_Close), BM_Ret columns
    """
    url = f"{NAVER_API}?symbol={symbol}&requestType=1&startTime={start_yyyymmdd}&endTime={end_yyyymmdd}&timeframe=day"
    headers = {'User-Agent': 'Mozilla/5.0 (Linux; rv:109.0) Gecko/20100101'}
    resp = requests.get(url, headers=headers, timeout=15)
    resp.raise_for_status()
    raw = resp.text.strip()
    arr = ast.literal_eval(raw)
    df = pd.DataFrame(arr[1:], columns=arr[0])
    df = df.rename(columns={'날짜': 'Date', '시가': 'Open', '고가': 'High',
                            '저가': 'Low', '종가': 'Close', '거래량': 'Volume'})
    df['Date'] = pd.to_datetime(df['Date'].astype(str), format='%Y%m%d')
    df = df[['Date', 'Close']].sort_values('Date').reset_index(drop=True)
    df['Close'] = df['Close'].astype(float)
    return df


def _write_bm_parquet(df: pd.DataFrame, path) -> None:
    """benchmark.parquet 저장 단일점 — Date를 date32(day)로 정규화해 기록.

    ★2026-07-18 도훈 mandate (writer 단일점 수리):
      기존 df.to_parquet(...)은 Date를 datetime64(=timestamp[ns], R에서 POSIXct
      09:00:00)로 저장했는데, build_index_cache.py는 date32(R에서 Date class)로 저장한다.
      두 writer가 번갈아 쓰면서 벤치 Date 타입이 실행 순서에 따라 바뀌었고,
      Date-class를 기대하는 소비자가 벤치를 Date로 재조인하면 "Ops.POSIXt vs Ops.Date"
      불일치로 조인이 조용히 all-NA가 됐다(fdb_daily phase7 베타 파생 팩터 ~54개 전멸 사건).
      → build_index_cache.py `_write_parquet`와 동일하게 date32로 통일한다.
      combined 컬럼은 [Date, BM_Close, BM_Ret]로 고정(patch_benchmark_parquet 참조).
    """
    d = pd.to_datetime(df['Date']).dt.date  # datetime64/Timestamp → python date → date32
    table = pa.table({
        'Date': pa.array(d, type=pa.date32()),
        'BM_Close': pa.array(df['BM_Close'].astype('float64')),
        'BM_Ret': pa.array(df['BM_Ret'].astype('float64')),
    })
    _atomic_write_table(table, str(path))


# ── 원자적 교체 (2026-08-30 신설) ──────────────────────────────────────────────
REPLACE_RETRIES = 8          # atomic_json.R / atomic_parquet.R 과 동일 규약
REPLACE_SLEEP_INIT = 0.02
REPLACE_SLEEP_CAP = 0.25


def _atomic_write_table(table: 'pa.Table', path: str) -> None:
    """tmp 에 쓴 뒤 os.replace 로 교체한다 — 대상 파일을 **열지 않는다**.

    ★왜 (2026-08-29 23:32 실사고 + 2026-08-30 실측):
      구 구현은 `pq.write_table(table, path)` 로 **정본 경로에 직접** 썼다. 두 가지가 깨진다.

      [측정 1] **제자리 쓰기는 조용히 자른다.** 쓰기 도중 죽으면 파일은 남는데 내용이
        절단된다 — 실측 9,017행 → 500행, 그리고 그 결과물은 **정상적으로 읽힌다**.
        소비자는 오류가 아니라 짧은 벤치 시리즈를 본다(= 침묵 실패, 이 저장소의 반복 병).
        같은 죽음에서 tmp 경유는 원본 9,017행 불변.

      [측정 2] **대상이 매핑돼 있으면 열리지 않는다.** 다른 프로세스가 이 파일을 mmap 한
        채면 Windows 가 `error 1224 (ERROR_USER_MAPPED_FILE)` 로 거부한다 — 2026-08-29
        23:27 [1pre] 가 정확히 이 오류로 죽었다. tmp→replace 는 대상을 열지 않으므로
        쓰기 자체는 성공하고, 마지막 교체만 재시도하면 된다.
        (※같은 실측에서 이 프로세스 자신의 `pd.read_parquet` 은 매핑을 남기지 않았다 —
          매핑 보유자는 외부다. 그래도 우리 쪽 참조를 먼저 놓아 조건을 줄인다.)

    ★copy 폴백을 쓰지 않는다: replace 가 실패하는 유일한 실전 사유가 "소비자가 점유 중"인데
      그 순간이 정확히 copy 가 파일을 제자리에서 찢는 순간이다.
      근거 카드: reference-windows-atomic-write-copy-fallback-is-the-tear
    ★선삭제도 하지 않는다: os.replace 는 대상이 있어도 덮어쓰므로 이득이 0이고,
      삭제~교체 사이에 **파일 부재 창**을 만든다(같은 사고의 R 측 기전).

    실패 시 원본은 **손대지 않은 채** 남고 tmp 가 보존된다 — 페이로드 회수 가능.
    """
    tmp = path + f'.tmp{os.getpid()}'
    pq.write_table(table, tmp)

    # "썼다" 와 "읽을 수 있는 것을 썼다" 는 다른 명제다 — promote 전에 되읽어 행 수를 본다.
    n_tmp = pq.read_metadata(tmp).num_rows
    if n_tmp != table.num_rows:
        os.remove(tmp)
        raise RuntimeError(f'[naver_benchmark] tmp 검증 실패 — 정본 미갱신 '
                           f'(기대 {table.num_rows}행, 실측 {n_tmp}행)')

    gc.collect()   # 우리 쪽 arrow 참조를 먼저 놓는다(교체 거부 조건 축소)
    last = None
    for i in range(REPLACE_RETRIES):
        try:
            os.replace(tmp, path)
            return
        except OSError as e:      # PermissionError(WinError 5) / WinError 1224 계열
            last = e
            time.sleep(min(REPLACE_SLEEP_CAP, REPLACE_SLEEP_INIT * 2 ** i))
    raise RuntimeError(
        f'[naver_benchmark] 원자적 교체 실패 (replace {REPLACE_RETRIES}회) — '
        f'정본 미갱신(원본 보존): {path}' + chr(10) +
        f'  기록분은 {tmp} 에 보존됨. 대개 소비자가 대상 핸들/매핑을 점유 중이다. 최종 오류: {last}')


# ── 이음매 상수 = seam_guard_config.json 단일 정본 (2026-09-07 도훈 승인 A안) ──────
#   같은 병(수출본 조정기준 단절)이 종목 배관에도 있어 그쪽에 가드를 이식하면서
#   상수를 두 곳에 적으면 다음 사람이 또 한쪽만 고친다 → 파일 하나로 합쳤다.
#   ★폴백은 남긴다: 이 스크립트는 daily_refresh 0:03 배관이라 설정 부재로 죽으면 안 된다.
#     (R 정본 seam_scale_guard.R 은 반대로 설정 부재 = stop — 그쪽은 신규 코드라
#      하드코딩 문턱이 되살아나는 것을 막는 쪽이 옳다.)
SEAM_GUARD_CONFIG = PROJECT_ROOT / '02_Infrastructure' / 'data' / 'seam_guard_config.json'
_SEAM_FALLBACK = {
    'SCALE_LOOKBACK_DAYS': 150,   # naver 재조회 여유 — canonical 스케일 추정 + 앵커 후퇴용
    'SCALE_TOL': 1e-6,            # 스케일 일치 판정 허용오차 (상대)
    'SEAM_MAX_RET': 0.35,         # 이음매 하루 수익률 상한 (2026-07-31 실측 +19.98% 통과, 스케일 단절 -89% 차단)
}


def _load_seam_consts() -> dict:
    import json
    try:
        with open(SEAM_GUARD_CONFIG, encoding='utf-8') as fh:
            cfg = json.load(fh)
        return {k: type(v)(cfg[k]) for k, v in _SEAM_FALLBACK.items()}
    except Exception as e:                       # 부재/파손 — 침묵하지 않고 폴백을 알린다
        print(f'  ⚠ [seam_guard] 설정 미적용({e.__class__.__name__}) — 파일 내 폴백값 사용: '
              f'{SEAM_GUARD_CONFIG}')
        return dict(_SEAM_FALLBACK)


_SEAM = _load_seam_consts()
SCALE_LOOKBACK_DAYS = _SEAM['SCALE_LOOKBACK_DAYS']
SCALE_TOL = _SEAM['SCALE_TOL']
SEAM_MAX_RET = _SEAM['SEAM_MAX_RET']


def patch_benchmark_parquet(start_date: str = '2026-04-01',
                              end_date: str | None = None,
                              backup: bool = True) -> dict:
    """Patch benchmark.parquet with Naver-verified KOSPI200 (KPI200) data.

    Replaces existing rows from start_date onward.
    2026-07-02 도훈 mandate: symbol 'KOSPI'(코스피 종합) → 'KPI200'(코스피200) 정정.
    북 벤치는 코스피200이어야 함 (기존 종합은 버그, IKS200과 스케일 6.75× 불일치).

    ★2026-08-09 수리 — **레벨 접합 → 수익률 접합** (도훈 적발 "어제 고쳤는데 또"):
      구 구현은 `bm_pre`(리베이스 체인 스케일)와 `naver_post`(생 KPI200 레벨)를
      **레벨로 이어붙인 뒤** 전체에 `pct_change()`를 걸었다. 두 구간의 스케일이
      상수배(실측 8.834×)만큼 다르므로 **경계 하루의 수익률이 스케일비를 그대로 삼킨다**
      — 2026-07-29 에 -89.38% (참값 -6.185%). 그리고 호출부가
      `--start_date "$(date -d '10 days ago')"`(daily_refresh.sh:122 / morning_briefing.sh:124)
      이므로 **이음매가 매일 하루씩 전진한다** → 날짜를 박은 국소 수리는 원리적으로 못 버틴다
      (08-08 repair_benchmark_scale_break_20260727.R 이 07-27 을 고쳤으나 08-09 에 07-29 로 재발).

      수리: 접합을 **수익률에서** 한다. 수익률은 스케일 불변이므로 이음매가 생길 수 없다.
        1. canonical 스케일 = 겹치는 최근 구간의 median(BM_Close / naver_Close) — 오염 구간이
           소수여도 median 이 흡수한다(실측: 150일 중 오염 8일 → median 불변 8.834).
        2. 앵커 = 그 스케일과 일치하는 **마지막** 날짜. 직전 구간이 오염돼 있으면 자동으로
           그 앞까지 후퇴한다 = **기존 이음매도 같은 경로로 치유**된다(별도 수리 스크립트 불요).
        3. 앵커 다음날부터 BM_Ret := naver 수익률, BM_Close := 앵커종가 × cumprod(1+ret).
           앵커 이전 행은 한 값도 건드리지 않는다.
    """
    if end_date is None:
        end_date = datetime.now().strftime('%Y-%m-%d')

    cutoff = pd.to_datetime(start_date)
    # ★스케일 추정·앵커 후퇴를 위해 cutoff 보다 넉넉히 앞에서부터 조회 (호출 1회, 비용 동일)
    fetch_from = cutoff - pd.Timedelta(days=SCALE_LOOKBACK_DAYS)
    start_yyyymmdd = fetch_from.strftime('%Y%m%d')
    end_yyyymmdd = pd.to_datetime(end_date).strftime('%Y%m%d')
    print(f'[naver_benchmark_update] Fetching {start_yyyymmdd} ~ {end_yyyymmdd} from Naver '
          f'(cutoff={cutoff.date()}, lookback={SCALE_LOOKBACK_DAYS}d)...')
    naver = fetch_naver_kospi(start_yyyymmdd, end_yyyymmdd, symbol='KPI200')  # ★코스피200 (구 'KOSPI' 종합 버그)
    print(f'  Naver returned {len(naver)} rows (KPI200/코스피200), latest={naver.Date.max().date()}')

    # sanity 가드 ①: 코스피 종합(수천대) 오심볼 회귀 차단 — **생 naver 레벨**에서 검사한다.
    #   (구 구현은 재척도 후 combined 에서 검사했는데, 수익률 접합 후 그 값은 정당하게 수천대다.)
    naver_max = float(naver.Close.max())
    if naver_max > 3000:
        raise RuntimeError(f"[naver_benchmark] 벤치 sanity FAIL: naver 최근 {naver_max:.0f} — "
                           f"코스피200 아닌 코스피 종합 의심 (symbol=KPI200 확인)")

    bm = pd.read_parquet(BM_PATH)
    bm['Date'] = pd.to_datetime(bm['Date'])
    bm = bm.sort_values('Date').reset_index(drop=True)
    n0, cols0 = len(bm), list(bm.columns)

    # ── canonical 스케일 + 앵커 결정 ────────────────────────────────────────────
    ov = bm.merge(naver.rename(columns={'Close': 'nv'})[['Date', 'nv']], on='Date', how='inner')
    ov = ov[(ov.nv > 0) & ov.BM_Close.notna()]
    if len(ov) < 20:
        raise RuntimeError(f"[naver_benchmark] 스케일 추정 불가: 겹치는 날짜 {len(ov)}개 (<20) — 중단")
    ov['ratio'] = ov.BM_Close / ov.nv
    canon = float(ov.ratio.median())

    # sanity 가드 ②: **정체 검사** — 받아온 시리즈가 정말 이 파일이 쓰던 그 지수인가.
    #   ①의 >3000 은 레벨 크기 휴리스틱이라 지수가 낮은 국면에서 오심볼을 놓친다(위반 주입 INJ-2 적발).
    #   수익률은 스케일 불변이므로, cutoff 이전 겹치는 날의 **저장된 BM_Ret 과 일치하는지**로
    #   심볼 정체를 직접 검사한다. 종합↔200 은 일간 수익률이 갈리므로(실측 07-28: -11.553% vs
    #   -10.837%) 즉시 발화한다. 기존 이음매 1~2일은 허용치(90%)가 흡수한다.
    nvr = naver.copy()
    nvr['nret'] = nvr.Close.pct_change()
    idc = bm.merge(nvr[['Date', 'nret']], on='Date', how='inner')
    idc = idc[(idc.Date < cutoff) & idc.nret.notna() & idc.BM_Ret.notna()]
    if len(idc) >= 20:
        agree = float(((idc.nret - idc.BM_Ret).abs() < 1e-6).mean())
        if agree < 0.90:
            raise RuntimeError(
                f"[naver_benchmark] 벤치 sanity FAIL(정체): 받아온 시리즈의 일간수익률이 "
                f"기존 BM_Ret 과 {agree:.1%}만 일치 (cutoff 이전 {len(idc)}일 대조, 기준 90%). "
                f"symbol=KPI200 이 맞는지 / benchmark.parquet 이 다른 지수로 만들어졌는지 확인.")
    else:
        agree = float('nan')
        print(f'  ⚠ 정체 검사 생략 — cutoff 이전 대조 가능일 {len(idc)}개 (<20)')

    ok = ov[(ov.ratio / canon - 1.0).abs() < SCALE_TOL]
    pre_ok = ok[ok.Date < cutoff]
    if len(pre_ok) == 0:
        raise RuntimeError(f"[naver_benchmark] cutoff({cutoff.date()}) 이전에 스케일 {canon:.4f} "
                           f"정합 앵커 없음 — 중단 (lookback 확대 필요)")
    anchor_date = pre_ok.Date.max()
    anchor_close = float(bm.loc[bm.Date == anchor_date, 'BM_Close'].iloc[0])
    # ★앵커 **이후로 실제 스케일을 이탈한** 행만 센다. 재체인 대상 전부를 세면 정상 입력에서도
    #   "치유했다"고 보고해 오염 유무를 구분 못 한다(위반 주입 POS-1 적발).
    n_offscale = int(((ov.Date > anchor_date) & ((ov.ratio / canon - 1.0).abs() >= SCALE_TOL)).sum())
    print(f'  canonical scale = {canon:.6f}× (n_ok={len(ok)}/{len(ov)})  '
          f'anchor = {anchor_date.date()} @ {anchor_close:.3f}')
    if n_offscale:
        print(f'  ★기존 이음매 감지 — {anchor_date.date()} 이후 {n_offscale}행이 스케일 이탈, 재체인으로 치유')

    # ── 수익률 접합: 앵커 다음날부터 naver 수익률로 재체인 ──────────────────────
    nv = naver[naver.Date >= anchor_date].sort_values('Date').reset_index(drop=True).copy()
    nv['ret'] = nv.Close.pct_change()
    tail = nv[nv.Date > anchor_date].copy()
    if len(tail) == 0:
        raise RuntimeError(f"[naver_benchmark] 앵커({anchor_date.date()}) 이후 naver 행 없음 — 중단")
    tail['BM_Ret'] = tail['ret'].astype('float64')
    tail['BM_Close'] = anchor_close * (1.0 + tail['ret']).cumprod()

    head = bm[bm.Date <= anchor_date][['Date', 'BM_Close', 'BM_Ret']].copy()
    combined = pd.concat([head, tail[['Date', 'BM_Close', 'BM_Ret']]], ignore_index=True)
    combined = combined.drop_duplicates(subset='Date', keep='last').sort_values('Date').reset_index(drop=True)

    # ── 가드: 하나라도 어긋나면 쓰지 않는다 ─────────────────────────────────────
    seam_ret = float(tail.BM_Ret.iloc[0])
    worst_ret = float(tail.BM_Ret.abs().max())
    if worst_ret > SEAM_MAX_RET:
        raise RuntimeError(f"[naver_benchmark] 이음매 가드 FAIL: 갱신구간 max|ret|={worst_ret:.4f} "
                           f"> {SEAM_MAX_RET} (스케일 단절 의심, seam_ret={seam_ret:.4f})")
    # 앵커 이전은 완전 불변
    h0 = bm[bm.Date <= anchor_date].reset_index(drop=True)
    h1 = combined[combined.Date <= anchor_date].reset_index(drop=True)
    if not (len(h0) == len(h1)
            and h0.BM_Close.equals(h1.BM_Close)
            and h0.BM_Ret.fillna(-9e9).equals(h1.BM_Ret.fillna(-9e9))):
        raise RuntimeError("[naver_benchmark] 가드 FAIL: 앵커 이전 구간이 변경됨 — 중단")
    # 내부 정합: BM_Ret == BM_Close 전일대비 (갱신구간)
    chk = combined[combined.Date >= anchor_date].reset_index(drop=True)
    rec = chk.BM_Close.pct_change().iloc[1:]
    if float((rec - chk.BM_Ret.iloc[1:]).abs().max()) > 1e-9:
        raise RuntimeError("[naver_benchmark] 가드 FAIL: 갱신구간 BM_Ret ↔ BM_Close 불일치 — 중단")
    # 스케일 연속성: 갱신구간이 canonical 스케일 위에 있다
    ck = combined.merge(naver.rename(columns={'Close': 'nv'})[['Date', 'nv']], on='Date', how='inner')
    ck = ck[ck.Date > anchor_date]
    if len(ck) and float((ck.BM_Close / ck.nv / canon - 1.0).abs().max()) > 1e-6:
        raise RuntimeError("[naver_benchmark] 가드 FAIL: 갱신구간 스케일이 canonical 이탈 — 중단")
    if len(combined) < n0 or list(combined.columns) != cols0:
        raise RuntimeError(f"[naver_benchmark] 가드 FAIL: 행/열 축소 ({n0}→{len(combined)}) — 중단")

    if backup:
        ts = datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_path = BM_PATH.with_suffix(f'.parquet.bak_naver_patch_{ts}')
        shutil.copy(BM_PATH, backup_path)
        print(f'  Backup: {backup_path.name}')

    _write_bm_parquet(combined, BM_PATH)  # ★date32 정규화 (build_index_cache와 통일, POSIXct 회귀 차단)

    return {
        'anchor_date': anchor_date.strftime('%Y-%m-%d'),
        'anchor_close': anchor_close,
        'canonical_scale': canon,
        'identity_agreement': agree,
        'healed_offscale_rows': n_offscale,
        'rechained_rows': len(tail),
        'seam_ret': seam_ret,
        'total_rows': len(combined),
        'latest_date': combined.Date.max().strftime('%Y-%m-%d'),
        'naver_latest': naver.Date.max().strftime('%Y-%m-%d'),
        'naver_latest_close': float(naver.Close.iloc[-1]),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--start_date', type=str, default='2026-04-01',
                        help='Patch from this date onward (default 2026-04-01)')
    parser.add_argument('--end_date', type=str, default=None,
                        help='Patch until this date (default today)')
    parser.add_argument('--no-backup', action='store_true', help='Skip backup creation')
    args = parser.parse_args()

    result = patch_benchmark_parquet(args.start_date, args.end_date, backup=not args.no_backup)
    print(f'\nPatch complete:')
    for k, v in result.items():
        print(f'  {k}: {v}')


if __name__ == '__main__':
    main()
