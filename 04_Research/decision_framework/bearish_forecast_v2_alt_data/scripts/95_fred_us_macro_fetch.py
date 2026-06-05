#!/usr/bin/env python3
"""
95_fred_us_macro_fetch.py — Cycle 47B precondition

Fetches 4 US macro series from FRED public API and caches to CSV:
  T10Y2Y     daily  (10Y - 2Y Treasury spread)            1976+
  ICSA       weekly (Initial Claims)                       1967+
  CFNAI      monthly (Chicago Fed National Activity Index) 1967+  [NAPM 대체]
  STLFSI4    weekly (St. Louis Fed Financial Stress Index) 1993+

Output:
  outputs/01_data/fred_us_macro_daily.csv
    Date | t10y2y | icsa | cfnai | stlfsi4 (raw)

PIT-safe lag-1 conversion + forward-fill는 build script (96)에서 처리.
"""
import sys
import urllib.request
import urllib.error
from pathlib import Path
import pandas as pd
import numpy as np

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
DATA = WS / "outputs/01_data"
DATA.mkdir(parents=True, exist_ok=True)

START = "1995-01-01"
END = "2026-05-19"


def fetch_fred_csv(series_id: str) -> pd.DataFrame:
    """Fetch FRED series via public CSV endpoint (no API key required)."""
    url = f"https://fred.stlouisfed.org/graph/fredgraph.csv?id={series_id}&cosd={START}&coed={END}"
    print(f"[fetch] {series_id}: {url}")
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=120) as resp:
            text = resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        sys.exit(f"FRED fetch failed for {series_id}: {e}")
    rows = []
    lines = text.strip().splitlines()
    header = lines[0].split(",")
    date_col = header[0]
    val_col = header[1]
    for ln in lines[1:]:
        parts = ln.split(",")
        if len(parts) < 2:
            continue
        d = parts[0].strip()
        v = parts[1].strip()
        if v in ("", "."):
            continue
        try:
            rows.append((pd.Timestamp(d), float(v)))
        except ValueError:
            continue
    df = pd.DataFrame(rows, columns=["Date", series_id.lower()])
    df = df.sort_values("Date").reset_index(drop=True)
    print(f"  obs: {len(df)} / range: {df['Date'].min()} ~ {df['Date'].max()}")
    return df


def main():
    print("=" * 60)
    print("[Cycle 47B] FRED US Macro fetch")
    print("=" * 60)

    series_ids = ["T10Y2Y", "ICSA", "CFNAI", "STLFSI4"]
    dfs = {}
    for sid in series_ids:
        dfs[sid] = fetch_fred_csv(sid)

    # Build a daily Date spine from 1995-01-01 to today
    spine = pd.DataFrame({
        "Date": pd.date_range(start=START, end=END, freq="D")
    })

    out = spine.copy()
    for sid in series_ids:
        df = dfs[sid].rename(columns={sid.lower(): sid.lower()})
        out = out.merge(df, on="Date", how="left")

    # Raw values only (no shift, no forward-fill) — handled in 96 R script
    out = out.rename(columns={
        "t10y2y": "t10y2y_raw",
        "icsa": "icsa_raw",
        "cfnai": "cfnai_raw",
        "stlfsi4": "stlfsi4_raw",
    })

    out_path = DATA / "fred_us_macro_daily.csv"
    out.to_csv(out_path, index=False)
    print(f"\n[saved] {out_path}")
    print(f"  rows: {len(out)}")
    print(f"  date_range: {out['Date'].min()} ~ {out['Date'].max()}")
    for col in ["t10y2y_raw", "icsa_raw", "cfnai_raw", "stlfsi4_raw"]:
        n_valid = out[col].notna().sum()
        first_valid = out.loc[out[col].notna(), "Date"].min() if n_valid else "n/a"
        last_valid = out.loc[out[col].notna(), "Date"].max() if n_valid else "n/a"
        print(f"  {col:20s} valid={n_valid:6d}  first={first_valid}  last={last_valid}")


if __name__ == "__main__":
    main()
