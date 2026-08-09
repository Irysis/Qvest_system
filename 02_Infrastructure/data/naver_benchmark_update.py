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
import shutil
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
    pq.write_table(table, str(path))


SCALE_LOOKBACK_DAYS = 150   # naver 재조회 여유 — canonical 스케일 추정 + 앵커 후퇴용
SCALE_TOL = 1e-6            # 스케일 일치 판정 허용오차 (상대)
SEAM_MAX_RET = 0.35         # 이음매 하루 수익률 상한 (2026-07-31 실측 +19.98% 통과, 스케일 단절 -89% 차단)


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
    ok = ov[(ov.ratio / canon - 1.0).abs() < SCALE_TOL]
    pre_ok = ok[ok.Date < cutoff]
    if len(pre_ok) == 0:
        raise RuntimeError(f"[naver_benchmark] cutoff({cutoff.date()}) 이전에 스케일 {canon:.4f} "
                           f"정합 앵커 없음 — 중단 (lookback 확대 필요)")
    anchor_date = pre_ok.Date.max()
    anchor_close = float(bm.loc[bm.Date == anchor_date, 'BM_Close'].iloc[0])
    n_offscale = int((ov.Date > anchor_date).sum())
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
