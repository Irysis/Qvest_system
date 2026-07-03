"""
332_fetch_leading_macro.py — fetch LONG-HISTORY forward-looking leading macro series.

도훈 mandate 2026-06-26 (forward-macro thread resume, "새 데이터원 사용 허용").

Motivation: the 331 sweep's "macro" features were dominated by US coincident series
(Init_Claims, VIX, fin-stress indices) and the cached ICE-BofA credit spreads
(HY_Spread/BBB_Spread) only cover 2023+ on the public FRED API (ICE license restriction).
A faithful test of the v0.6 D.3 hypothesis ("forward-looking macro = root cause")
requires genuinely *leading* long-history credit/financial-condition signals.

Series fetched (all PIT-safe long history, covering 2001-2024 backtest window):
  - BAA10YM   (1953, M) : Moody's Baa - 10Y Treasury credit spread (Gilchrist-Zakrajsek style, forward credit stress)
  - T10Y3M    (1982, D) : 10Y-3M yield curve (Estrella-Hardouvelis preferred recession predictor; > T10Y2Y)
  - NFCICREDIT (1971, W): Chicago Fed NFCI credit subindex
  - NFCILEVERAGE (1971,W): Chicago Fed NFCI leverage subindex
  - NFCIRISK  (1971, W) : Chicago Fed NFCI risk subindex
  - STLFSI4   (1993, W) : St. Louis Fed Financial Stress Index (current vintage)

ICE-BofA OAS (BAMLH0A0HYM2 / BAMLC0A4CBBB) deliberately EXCLUDED — public FRED API
returns them only from 2023-06-26 (license), so they cannot cover the backtest window.

PIT: lagging/publication delay handled downstream in the sweep loader (t-1 shift +
forward-fill). Output is a wide daily panel ffill'd to daily granularity.

Output: .cache/fred_leading_macro.parquet  (Date + 6 leading cols)
"""
from __future__ import annotations
import json
import urllib.request
import urllib.parse
from pathlib import Path

import numpy as np
import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[4]
CACHE = PROJECT_ROOT / ".cache"
OUT = CACHE / "fred_leading_macro.parquet"

SERIES = {
    "BAA10YM": "Credit_Baa10Y",          # credit spread (forward credit stress)
    "T10Y3M": "YC_10Y3M",                # recession yield curve (Estrella)
    "NFCICREDIT": "NFCI_Credit",         # NFCI credit subindex
    "NFCILEVERAGE": "NFCI_Leverage",     # NFCI leverage subindex
    "NFCIRISK": "NFCI_Risk",             # NFCI risk subindex
    "STLFSI4": "StL_Fin_Stress4",        # financial stress (current vintage)
}


def _key() -> str:
    for line in open(PROJECT_ROOT / ".env", encoding="utf-8", errors="ignore"):
        if line.startswith("FRED_API_KEY="):
            return line.split("=", 1)[1].strip()
    raise RuntimeError("FRED_API_KEY not in .env")


def fetch_series(sid: str, key: str, start="2000-01-01", end="2025-01-31") -> pd.DataFrame:
    params = urllib.parse.urlencode({
        "series_id": sid, "api_key": key, "file_type": "json",
        "observation_start": start, "observation_end": end, "sort_order": "asc",
    })
    url = f"https://api.stlouisfed.org/fred/series/observations?{params}"
    d = json.load(urllib.request.urlopen(url, timeout=60))
    rows = []
    for o in d.get("observations", []):
        v = o["value"]
        if v in (".", "", None):
            continue
        rows.append((pd.to_datetime(o["date"]), float(v)))
    df = pd.DataFrame(rows, columns=["Date", sid])
    return df


def main():
    key = _key()
    # daily date spine over the full window
    spine = pd.DataFrame({"Date": pd.date_range("2000-01-01", "2025-01-31", freq="D")})
    panel = spine.copy()
    for sid, name in SERIES.items():
        df = fetch_series(sid, key)
        n = len(df)
        first = df["Date"].min().date() if n else "NONE"
        last = df["Date"].max().date() if n else "NONE"
        df = df.rename(columns={sid: name})
        panel = panel.merge(df, on="Date", how="left")
        # ffill to daily granularity (monthly/weekly series carried forward)
        panel[name] = panel[name].ffill()
        print(f"  {sid:14s} -> {name:18s}: {n:5d} raw obs, {first} .. {last}, "
              f"daily non-null after ffill={panel[name].notna().sum()}")
    # keep only dates with at least one series populated
    panel = panel.dropna(how="all", subset=list(SERIES.values())).reset_index(drop=True)
    panel.to_parquet(OUT, index=False)
    print(f"\nSaved: {OUT}")
    print(f"Shape: {panel.shape}, range {panel['Date'].min().date()} .. {panel['Date'].max().date()}")
    # coverage in backtest window
    win = panel[(panel["Date"] >= "2001-04-06") & (panel["Date"] <= "2024-12-31")]
    print("\nBacktest-window (2001-04-06 .. 2024-12-31) coverage:")
    for name in SERIES.values():
        print(f"  {name:18s}: {win[name].notna().sum()}/{len(win)} non-null")


if __name__ == "__main__":
    main()
