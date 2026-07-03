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


def patch_benchmark_parquet(start_date: str = '2026-04-01',
                              end_date: str | None = None,
                              backup: bool = True) -> dict:
    """Patch benchmark.parquet with Naver-verified KOSPI200 (KPI200) data.

    Replaces existing rows from start_date onward.
    2026-07-02 도훈 mandate: symbol 'KOSPI'(코스피 종합) → 'KPI200'(코스피200) 정정.
    북 벤치는 코스피200이어야 함 (기존 종합은 버그, IKS200과 스케일 6.75× 불일치).
    """
    if end_date is None:
        end_date = datetime.now().strftime('%Y-%m-%d')

    # Fetch Naver
    start_yyyymmdd = pd.to_datetime(start_date).strftime('%Y%m%d')
    end_yyyymmdd = pd.to_datetime(end_date).strftime('%Y%m%d')
    print(f'[naver_benchmark_update] Fetching {start_yyyymmdd} ~ {end_yyyymmdd} from Naver...')
    naver = fetch_naver_kospi(start_yyyymmdd, end_yyyymmdd, symbol='KPI200')  # ★코스피200 (구 'KOSPI' 종합 버그)
    print(f'  Naver returned {len(naver)} rows (KPI200/코스피200), latest={naver.Date.max().date()}')

    if backup:
        ts = datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_path = BM_PATH.with_suffix(f'.parquet.bak_naver_patch_{ts}')
        shutil.copy(BM_PATH, backup_path)
        print(f'  Backup: {backup_path.name}')

    bm = pd.read_parquet(BM_PATH)
    bm['Date'] = pd.to_datetime(bm['Date'])
    bm = bm.sort_values('Date').reset_index(drop=True)

    cutoff = pd.to_datetime(start_date)
    bm_pre = bm[bm.Date < cutoff].copy()[['Date', 'BM_Close']]
    naver_post = naver.rename(columns={'Close': 'BM_Close'})
    combined = pd.concat([bm_pre, naver_post], ignore_index=True)
    combined = combined.drop_duplicates(subset='Date', keep='last').sort_values('Date').reset_index(drop=True)
    combined['BM_Ret'] = combined['BM_Close'].pct_change().fillna(0.0)
    # sanity 가드: 코스피 종합(수천대) 오심볼 회귀 차단 — 코스피200은 수백~천대
    recent_max = combined[combined.Date >= cutoff]['BM_Close'].max()
    if recent_max > 3000:
        raise RuntimeError(f"[naver_benchmark] 벤치 sanity FAIL: 최근 {recent_max:.0f} — 코스피200 아닌 코스피 종합 의심 (symbol=KPI200 확인)")
    combined.to_parquet(BM_PATH)

    return {
        'patched_rows_from': len(bm_pre),
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
