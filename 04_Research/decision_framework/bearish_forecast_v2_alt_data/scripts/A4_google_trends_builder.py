#!/usr/bin/env python3
"""
A4_google_trends_builder.py — Google Trends SVI for KR bearish forecast

Plan v1.0 → v1.1 Step 2 β2

학술 anchor: Da-Engelberg-Gao 2011 JoF — "In Search of Attention" (SVI Search Volume Index)

KR 검색어 (panic / bear / recession):
  "주식 폭락" / "경기침체" / "bear market" / "코스피 하락" / "주식 손절"

Method:
  pytrends weekly granularity (Google Trends default 5y window per call)
  geo="KR" (Korea region)
  combine 2010~2026 (multi-window stitch)

Output: .cache/google_trends_kr.parquet
  cols: Date, kr_panic_svi, kr_bear_svi, kr_recession_svi, kr_kospi_drop_svi
"""

import sys
import time
import pandas as pd
from pytrends.request import TrendReq
from pathlib import Path

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
CACHE_DIR = PROJECT_ROOT / ".cache"
OUT_PATH = CACHE_DIR / "google_trends_kr.parquet"

KEYWORDS = ["주식 폭락", "경기침체", "bear market", "코스피 하락", "주식 손절"]
COL_MAP = {
    "주식 폭락": "kr_panic_svi",
    "경기침체": "kr_recession_svi",
    "bear market": "kr_bear_svi",
    "코스피 하락": "kr_kospi_drop_svi",
    "주식 손절": "kr_panic2_svi",
}

# Multi-window stitching for long history (Google Trends weekly 5y limit per call)
WINDOWS = [
    ("2010-01-01 2015-12-31", "2010~2015"),
    ("2016-01-01 2020-12-31", "2016~2020"),
    ("2021-01-01 2026-05-19", "2021~2026"),
]


def fetch_window(pytrend, kw_list, timeframe, geo="KR"):
    pytrend.build_payload(kw_list=kw_list, timeframe=timeframe, geo=geo)
    df = pytrend.interest_over_time()
    if df.empty:
        return None
    df = df.drop(columns=["isPartial"], errors="ignore")
    df.index.name = "Date"
    return df.reset_index()


def main():
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    pytrend = TrendReq(hl="ko-KR", tz=540, timeout=(10, 25))

    print(f"[A4 GoogleTrends] Fetching {len(KEYWORDS)} keywords × {len(WINDOWS)} windows...")

    all_data = []
    # Single keyword per call (Google Trends best results)
    for kw in KEYWORDS:
        print(f"\n  Keyword: '{kw}'")
        kw_dfs = []
        for tf, label in WINDOWS:
            try:
                df = fetch_window(pytrend, [kw], tf)
                if df is not None and not df.empty:
                    kw_dfs.append(df)
                    print(f"    {label}: {len(df)} weekly obs")
                else:
                    print(f"    {label}: EMPTY")
                time.sleep(1.5)  # Google rate limit
            except Exception as e:
                print(f"    {label}: ERROR {e}")
                time.sleep(5)
        if not kw_dfs:
            print(f"    [skip] {kw}")
            continue
        merged = pd.concat(kw_dfs, ignore_index=True).drop_duplicates("Date").sort_values("Date")
        merged = merged.rename(columns={kw: COL_MAP.get(kw, kw)})
        all_data.append(merged)

    if not all_data:
        print("[A4] No data fetched. Abort.")
        sys.exit(1)

    # Merge by Date
    result = all_data[0]
    for d in all_data[1:]:
        result = pd.merge(result, d, on="Date", how="outer")

    result = result.sort_values("Date").reset_index(drop=True)
    print(f"\n[A4] Merged: {len(result)} rows / {result.shape[1]-1} keywords")
    print(f"     Date range: {result['Date'].min()} ~ {result['Date'].max()}")

    result.to_parquet(OUT_PATH, index=False)
    print(f"[A4] Saved: {OUT_PATH}")
    print("\nColumn non-NA:")
    for c in result.columns:
        if c != "Date":
            print(f"  {c}: {result[c].notna().sum()}")


if __name__ == "__main__":
    main()
