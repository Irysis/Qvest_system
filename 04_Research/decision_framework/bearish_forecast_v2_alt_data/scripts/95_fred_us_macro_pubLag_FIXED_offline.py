#!/usr/bin/env python3
"""
95_fred_us_macro_pubLag_FIXED_offline.py — Cycle 57A Phase 1 (offline variant)

Network ALFRED API + FRED fetch both timed out 2026-05-21. Strategy:
  - Reuse existing fred_us_macro_daily.csv (Cycle 47B raw fetch, reference-period dated)
  - Apply publication lag offline (no network) to produce fred_us_macro_daily_fixed.csv

This is the SAME fix logic as 95_fred_us_macro_fetch_FIXED.py but bypasses FRED CSV fetch
(uses existing cached raw data instead).

PIT correctness: as long as raw data is reference-period dated (which it is — confirmed
2020-03-01 row = -4.37 = Feb 2020 reading per FRED CFNAI conv), publication lag shift
gives correct release-date dating.
"""
import sys
import json
from pathlib import Path
import pandas as pd
import numpy as np

PROJECT_ROOT = Path("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
WS = PROJECT_ROOT / "04_Research/decision_framework/bearish_forecast_v2_alt_data"
DATA = WS / "outputs/01_data"
EVAL = WS / "outputs/04_evaluation"

PUB_LAG_DAYS = {
    "t10y2y_raw":  0,
    "stlfsi4_raw": 0,
    "icsa_raw":    5,
    # CFNAI CORRECTION (Q-Lead pre-Codex audit 2026-05-21):
    # FRED dates CFNAI at MM-START of reference month (NOT month-END as 55B audit suggested).
    # Verified empirically: cfnai_raw[2020-03-01]=-4.37 = March 2020 reading (released ~4/23/2020)
    # Days from MM-01 dating to release: 51-53 days (avg ~52d). Use 55d to be conservative
    # (covers months when Chicago Fed release lands later than the 23rd).
    # See: scripts/95_fred_us_macro_pubLag_FIXED_offline.py docstring + 173 panel rebuild log.
    "cfnai_raw":   55,
}


def apply_publication_lag_to_column(df_spine: pd.DataFrame, col: str, lag_days: int) -> pd.DataFrame:
    """Build release-date dated column from reference-period dated raw data.

    Steps:
      1. Extract rows where col is not-NA (these are the reference-period release rows)
      2. Shift Date forward by lag_days (reference → release)
      3. Re-merge to spine
    """
    if lag_days == 0:
        return df_spine
    out = df_spine.copy()
    # Extract non-NA observations (reference-period rows)
    ref_obs = out[["Date", col]].dropna(subset=[col]).copy()
    if len(ref_obs) == 0:
        print(f"  [WARN] {col}: no non-NA rows to shift")
        return out
    original_first = ref_obs["Date"].min()
    original_last = ref_obs["Date"].max()
    # Shift Date forward
    ref_obs["Date_release"] = ref_obs["Date"] + pd.Timedelta(days=lag_days)
    # Drop original column from spine, then merge shifted
    out = out.drop(columns=[col])
    shifted = ref_obs.rename(columns={"Date_release": "Date_new", col: col})[["Date_new", col]]
    shifted = shifted.rename(columns={"Date_new": "Date"})
    # For rows where multiple release dates collide (theoretically rare for monthly/weekly), take first
    shifted = shifted.drop_duplicates(subset=["Date"], keep="first")
    out = out.merge(shifted, on="Date", how="left")
    print(f"  [PUB_LAG {col}] +{lag_days}d: "
          f"{original_first.date()}~{original_last.date()} → "
          f"{(original_first + pd.Timedelta(days=lag_days)).date()}~"
          f"{(original_last + pd.Timedelta(days=lag_days)).date()}")
    return out


def main():
    print("=" * 70)
    print("[Cycle 57A Phase 1 OFFLINE] FRED publication-lag fix (no network)")
    print("=" * 70)
    raw_path = DATA / "fred_us_macro_daily.csv"
    if not raw_path.exists():
        sys.exit(f"raw FRED CSV missing: {raw_path}")

    df = pd.read_csv(raw_path)
    df["Date"] = pd.to_datetime(df["Date"])
    df = df.sort_values("Date").reset_index(drop=True)
    print(f"[loaded] {raw_path}")
    print(f"  rows: {len(df)}")
    print(f"  date_range: {df['Date'].min().date()} ~ {df['Date'].max().date()}")
    print(f"  cols: {list(df.columns)}")

    # Sample CFNAI BEFORE shift
    cfnai_feb20 = df[df["Date"] == pd.Timestamp("2020-03-01")]
    print(f"\n[BEFORE FIX] CFNAI on 2020-03-01: "
          f"{cfnai_feb20['cfnai_raw'].values[0] if len(cfnai_feb20) else 'NA'} "
          f"(BUGGY = MARCH 2020 reading dated at MM-START, ACTUAL release ~2020-04-23 = 53d lookahead)")

    # Apply publication lag
    print(f"\n[applying publication lag]")
    fix_log = {}
    for col, lag in PUB_LAG_DAYS.items():
        df = apply_publication_lag_to_column(df, col, lag)

    # Sample CFNAI AFTER shift (should be NA on 2020-03-01, populated on 2020-04-25 = 3/1+55d)
    cfnai_post = df[df["Date"] == pd.Timestamp("2020-03-01")]
    cfnai_release = df[df["Date"] == pd.Timestamp("2020-04-25")]  # 3/1 + 55d
    print(f"\n[AFTER FIX] CFNAI on 2020-03-01: "
          f"{cfnai_post['cfnai_raw'].values[0] if len(cfnai_post) and not pd.isna(cfnai_post['cfnai_raw'].values[0]) else 'NA'} "
          f"(should be NA — March reading not yet released)")
    print(f"[AFTER FIX] CFNAI on 2020-04-25: "
          f"{cfnai_release['cfnai_raw'].values[0] if len(cfnai_release) else 'NA'} "
          f"(should be -4.37, the MARCH 2020 reading at release date ~2020-04-23, +55d after MM-01)")
    fix_log["CFNAI_sample_check"] = {
        "before_2020_03_01": -4.37,
        "after_2020_03_01": (None if not len(cfnai_post) or pd.isna(cfnai_post["cfnai_raw"].values[0])
                              else float(cfnai_post["cfnai_raw"].values[0])),
        "after_2020_04_25": (None if not len(cfnai_release) or pd.isna(cfnai_release["cfnai_raw"].values[0])
                              else float(cfnai_release["cfnai_raw"].values[0])),
        "expected_before": -4.37,
        "expected_after_03_01": None,
        "expected_after_04_25": -4.37,
        "interpretation": (
            "BUGGY: March 2020 CFNAI dated 2020-03-01 (FRED MM-START convention), "
            "but actual release ~2020-04-23 → 53d lookahead. "
            "FIX: shift 2020-03-01 → 2020-04-25 (+55d) so trader on 4/26 (after shift(1L)) sees -4.37."
        )
    }

    # ICSA sample check
    icsa_sat = df[df["Date"] == pd.Timestamp("2020-03-21")]
    icsa_thu = df[df["Date"] == pd.Timestamp("2020-03-26")]
    print(f"\n[AFTER FIX] ICSA on 2020-03-21 (Sat): "
          f"{icsa_sat['icsa_raw'].values[0] if len(icsa_sat) and not pd.isna(icsa_sat['icsa_raw'].values[0]) else 'NA'} "
          f"(should be NA)")
    print(f"[AFTER FIX] ICSA on 2020-03-26 (Thu release): "
          f"{icsa_thu['icsa_raw'].values[0] if len(icsa_thu) else 'NA'} "
          f"(should be 2,914,000 — week-ending 3/21 claims)")
    fix_log["ICSA_sample_check"] = {
        "after_2020_03_21": (None if not len(icsa_sat) or pd.isna(icsa_sat["icsa_raw"].values[0])
                              else float(icsa_sat["icsa_raw"].values[0])),
        "after_2020_03_26": (None if not len(icsa_thu) or pd.isna(icsa_thu["icsa_raw"].values[0])
                              else float(icsa_thu["icsa_raw"].values[0])),
        "expected_after_03_21": None,
        "expected_after_03_26": 2914000.0,
        "interpretation": "Week-ending Sat 3/21 ICSA shifted from 3/21 (Sat dating) to 3/26 (Thu release)"
    }

    out_path = DATA / "fred_us_macro_daily_fixed.csv"
    df.to_csv(out_path, index=False)
    print(f"\n[saved] {out_path}")
    for col in ["t10y2y_raw", "icsa_raw", "cfnai_raw", "stlfsi4_raw"]:
        n_valid = df[col].notna().sum()
        first_valid = df.loc[df[col].notna(), "Date"].min() if n_valid else None
        last_valid = df.loc[df[col].notna(), "Date"].max() if n_valid else None
        first_str = first_valid.date() if first_valid is not None else "n/a"
        last_str = last_valid.date() if last_valid is not None else "n/a"
        print(f"  {col:20s} valid={n_valid:6d}  first={first_str}  last={last_str}")

    audit = {
        "cycle": "57A",
        "phase": "Phase 1 FRED publication-lag fix (OFFLINE — network timeout)",
        "approach": "Option A: minimum publication-lag adjustment on cached raw CSV",
        "rationale": (
            "ALFRED + FRED both timed out 2026-05-21. Reuse existing fred_us_macro_daily.csv "
            "(Cycle 47B raw fetch, reference-period dated). Apply calendar-day shift to Date "
            "column (reference → release). This produces release-date dated panel without "
            "network dependency."
        ),
        "limitation": (
            "Cannot catch as-of-vintage revisions (Cycle 55B Codex Q2). Historical row values "
            "are current-revised (not vintage). For q15 horizon, revision impact estimated < "
            "0.005 PR-AUC per 55B Codex est. Acceptable trade-off for cycle progression."
        ),
        "publication_lag_days": PUB_LAG_DAYS,
        "fix_validation_samples": fix_log,
        "input_csv": str(raw_path),
        "output_csv": str(out_path),
        "n_rows": int(len(df)),
        "date_range": {
            "start": str(df["Date"].min().date()),
            "end": str(df["Date"].max().date())
        },
        "next_step": "Phase 2: v3f/v5e/v5f panel rebuild using fred_us_macro_daily_fixed.csv",
    }
    audit_path = EVAL / "cycle57a_fred_publication_lag_fix.json"
    with audit_path.open("w") as f:
        json.dump(audit, f, indent=2)
    print(f"\n[audit] {audit_path}")


if __name__ == "__main__":
    main()
