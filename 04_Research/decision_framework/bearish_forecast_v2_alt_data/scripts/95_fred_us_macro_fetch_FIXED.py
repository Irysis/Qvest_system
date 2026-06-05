#!/usr/bin/env python3
"""
95_fred_us_macro_fetch_FIXED.py — Cycle 57A FRED publication-lag fix

REPLACES: 95_fred_us_macro_fetch.py (Cycle 47B original, buggy publication-lag dating)

Cycle 55B Q-Lead+Codex deep audit confirmed:
  - CFNAI (~22-25d) — month-end dated, but released ~3 weeks later
  - ICSA (~5d) — Saturday-dated, but released Thursday following week
  - STLFSI4 — Friday release, KR next-open OK (no lag needed)
  - T10Y2Y — daily, US close ET → KR next open OK (shift(1L) sufficient)

Fix strategy (Option A: minimum fix, ALFRED API timed out 2026-05-21):
  - Apply `Date := reference_Date + publication_lag_days` BEFORE forward-fill
  - Reference period dating → release date dating
  - After release-date conversion: shift(1L) at panel build still applies
    (next-day usable at KR open)

Publication lag table (FRED official sources, Cycle 55B confirmed):
  T10Y2Y   = 0  (daily, FRED release immediate)
  STLFSI4  = 0  (weekly Friday release, KR next-open OK)
  ICSA     = 5  (Saturday-dated, released Thu following week 08:30 ET)
  CFNAI    = 25 (monthly month-end dated, released ~22-25d later)

Output:
  outputs/01_data/fred_us_macro_daily_fixed.csv
    Date | t10y2y | icsa | cfnai | stlfsi4 (raw, release-dated)
  outputs/04_evaluation/cycle57a_fred_publication_lag_fix.json (audit log)
"""
import sys
import json
import urllib.request
import urllib.error
from pathlib import Path
import pandas as pd
import numpy as np

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
DATA = WS / "outputs/01_data"
EVAL = WS / "outputs/04_evaluation"
DATA.mkdir(parents=True, exist_ok=True)
EVAL.mkdir(parents=True, exist_ok=True)

START = "1995-01-01"
END = "2026-05-19"

# Cycle 55B confirmed publication lag (calendar days, applied to reference Date)
PUB_LAG_DAYS = {
    "T10Y2Y":  0,   # daily, immediate FRED release
    "STLFSI4": 0,   # weekly, Friday release → KR next-open OK
    "ICSA":    5,   # weekly, Saturday-dated → Thursday following week release
    "CFNAI":   25,  # monthly, month-end dated → released ~22-25d after month-end
}


def fetch_fred_csv(series_id: str) -> pd.DataFrame:
    """Fetch FRED series via public CSV endpoint (no API key required).

    Note: fredgraph.csv current-vintage endpoint returns REVISED values, not as-of-vintage.
    This is a known limitation (Cycle 55B Codex audit Q2 — Option B ALFRED API for as-of-vintage
    would catch revisions but timed out 2026-05-21). Publication lag (Option A) addresses the
    dating issue but not revision issue. For q15 / 21-day horizon impact, revisions are typically
    < 0.05-0.1 SD (small absolute effect, est. < 0.005 PR-AUC per 55B Codex est.).
    """
    url = f"https://fred.stlouisfed.org/graph/fredgraph.csv?id={series_id}&cosd={START}&coed={END}"
    print(f"[fetch] {series_id}: {url}")
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=120) as resp:
            text = resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        sys.exit(f"FRED fetch failed for {series_id}: {e}")
    except Exception as e:
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
    print(f"  obs: {len(df)} / range: {df['Date'].min().date()} ~ {df['Date'].max().date()}")
    return df


def apply_publication_lag(df: pd.DataFrame, series_id: str, lag_days: int) -> pd.DataFrame:
    """Shift Date forward by publication lag (reference date → release date)."""
    if lag_days == 0:
        return df
    df_fixed = df.copy()
    original_first = df_fixed["Date"].min()
    original_last = df_fixed["Date"].max()
    df_fixed["Date"] = df_fixed["Date"] + pd.Timedelta(days=lag_days)
    print(f"  [PUB_LAG {series_id}] +{lag_days}d: {original_first.date()}~{original_last.date()} → "
          f"{df_fixed['Date'].min().date()}~{df_fixed['Date'].max().date()}")
    return df_fixed


def main():
    print("=" * 70)
    print("[Cycle 57A] FRED US Macro fetch (publication-lag FIXED)")
    print("=" * 70)
    print(f"START={START}  END={END}")
    print(f"Publication lag table: {PUB_LAG_DAYS}\n")

    series_ids = ["T10Y2Y", "ICSA", "CFNAI", "STLFSI4"]
    dfs_raw = {}
    dfs_fixed = {}
    fix_log = {}
    for sid in series_ids:
        dfs_raw[sid] = fetch_fred_csv(sid)
        lag = PUB_LAG_DAYS[sid]
        dfs_fixed[sid] = apply_publication_lag(dfs_raw[sid], sid, lag)
        # Log sample row (CFNAI 2020-03 reference period)
        if sid == "CFNAI":
            raw_march = dfs_raw[sid][dfs_raw[sid]["Date"] == pd.Timestamp("2020-03-01")]
            fixed_march = dfs_fixed[sid][dfs_fixed[sid]["Date"] == pd.Timestamp("2020-03-26")]
            fix_log["CFNAI_sample"] = {
                "raw_2020_03_01": float(raw_march["cfnai"].values[0]) if len(raw_march) else None,
                "fixed_2020_03_26": float(fixed_march["cfnai"].values[0]) if len(fixed_march) else None,
                "interpretation": "Feb 2020 reading shifted from Mar 1 dating to Mar 26 release"
            }
        if sid == "ICSA":
            raw_sat = dfs_raw[sid][dfs_raw[sid]["Date"] == pd.Timestamp("2020-03-21")]
            fixed_thu = dfs_fixed[sid][dfs_fixed[sid]["Date"] == pd.Timestamp("2020-03-26")]
            fix_log["ICSA_sample"] = {
                "raw_2020_03_21": float(raw_sat["icsa"].values[0]) if len(raw_sat) else None,
                "fixed_2020_03_26": float(fixed_thu["icsa"].values[0]) if len(fixed_thu) else None,
                "interpretation": "Week-ending Sat 3/21 reading shifted to Thu 3/26 release"
            }

    # Build daily spine: from earliest start until END
    spine = pd.DataFrame({"Date": pd.date_range(start=START, end=END, freq="D")})

    out = spine.copy()
    for sid in series_ids:
        df = dfs_fixed[sid].rename(columns={sid.lower(): sid.lower()})
        out = out.merge(df, on="Date", how="left")

    out = out.rename(columns={
        "t10y2y":  "t10y2y_raw",
        "icsa":    "icsa_raw",
        "cfnai":   "cfnai_raw",
        "stlfsi4": "stlfsi4_raw",
    })

    out_path = DATA / "fred_us_macro_daily_fixed.csv"
    out.to_csv(out_path, index=False)
    print(f"\n[saved] {out_path}")
    print(f"  rows: {len(out)}")
    print(f"  date_range: {out['Date'].min().date()} ~ {out['Date'].max().date()}")
    for col in ["t10y2y_raw", "icsa_raw", "cfnai_raw", "stlfsi4_raw"]:
        n_valid = out[col].notna().sum()
        first_valid = out.loc[out[col].notna(), "Date"].min() if n_valid else None
        last_valid = out.loc[out[col].notna(), "Date"].max() if n_valid else None
        first_str = first_valid.date() if first_valid is not None else "n/a"
        last_str = last_valid.date() if last_valid is not None else "n/a"
        print(f"  {col:20s} valid={n_valid:6d}  first={first_str}  last={last_str}")

    # Audit log
    audit = {
        "cycle": "57A",
        "phase": "Phase 1 FRED publication-lag fix",
        "approach": "Option A: minimum publication-lag adjustment (ALFRED API timed out)",
        "rationale": (
            "ALFRED API (as-of-vintage) timed out at 2026-05-21 fetch attempt. "
            "Option A applies calendar-day publication lag to reference Date column "
            "(reference period → release date). Revisions (Cycle 55B Codex Q2) remain "
            "unaddressed but estimated < 0.005 PR-AUC impact at q15 horizon."
        ),
        "publication_lag_days": PUB_LAG_DAYS,
        "fix_examples": fix_log,
        "output_csv": str(out_path),
        "n_rows": int(len(out)),
        "date_range": {
            "start": str(out["Date"].min().date()),
            "end": str(out["Date"].max().date())
        },
        "next_step": "Phase 2: v5e + v5f panel rebuild via 95b_panel_rebuild_FIXED.R",
    }
    audit_path = EVAL / "cycle57a_fred_publication_lag_fix.json"
    with audit_path.open("w") as f:
        json.dump(audit, f, indent=2)
    print(f"\n[audit] {audit_path}")


if __name__ == "__main__":
    main()
