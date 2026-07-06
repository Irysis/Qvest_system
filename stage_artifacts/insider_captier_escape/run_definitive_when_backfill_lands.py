"""run_definitive_when_backfill_lands.py — READINESS helper (Q-Lead's own stage dir).
Fires the DEFINITIVE cap-tier escape test once the parallel backfill reaches >=60 months of
signed officer net-buy. Does NOT modify parallel session build files — reads their outputs.

PRECONDITIONS (all must hold; script asserts and reports):
  1. Parallel panel has >=60 distinct months with reliable officer net qty:
     - stage_artifacts/dart_parser_build/data/insider_netbuy_monthly.parquet, field net_qty_officer
       non-null for the month (their meta: reliable v3+ 2010+). OR
     - .cache/dart/exec_netbuy/*.csv (signed) / insider_backfill/*.csv (qty_change) merged.
  2. RAWDATA.parquet present (Size for PIT cap-tier, K200/KQ150 universe, Ret for fwd return).

WHAT THE DEFINITIVE TEST ADDS over today's directional read:
  - >=60 months => cap-tier NW-t and rank-IC are powered (today MEGA n=25-41 gappy).
  - Enables canonical_screen_bt (R bridge) for a graduation-grade MEGA/BIGCAP long-only PORT_t
    (today we only have event-cohort active t; canonical needs enough names/month).
  - Enables oos_retention (v2 3-split median) + placebo + holdout falsification on the MEGA sleeve.

TO RUN THE GRADUATION-GRADE VERSION (not built here — documented):
  Feed the >=60-mo exec-net-buy scores parquet (Date, Ticker, score) to:
    02_Infrastructure/contracts/canonical_screen_bt.R :: canonical_screen_bt()
  restricted to each cap-tier universe, to get forge-authoritative portfolio_alpha_t_nw_lag3,
  then discovery_graduation_gate.sh (HARD: PORT_t>=2.95, oos_retention>=0.7, calmar>=0.64).
"""
import os, glob, numpy as np, pandas as pd
R = "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT = R + "/stage_artifacts/insider_captier_escape"
B = R + "/stage_artifacts/dart_parser_build"


def count_reliable_officer_months():
    """How many distinct months have signed officer net-buy across all sources."""
    months = set()
    # hifi parallel panel
    hf = B + "/data/insider_netbuy_monthly.parquet"
    if os.path.exists(hf):
        d = pd.read_parquet(hf)
        if "net_qty_officer" in d.columns:
            ok = d[pd.to_numeric(d.net_qty_officer, errors="coerce").notna()
                   & (pd.to_numeric(d.net_qty_officer, errors="coerce") != 0)]
            months |= set(ok.sig_month.unique())
    # backfill csv (qty_change signed, is_officer)
    for f in glob.glob(R + "/.cache/dart/insider_backfill/*.csv"):
        try:
            b = pd.read_csv(f, dtype=str)
            if "qty_change" in b.columns and b["is_officer"].astype(str).str.upper().eq("TRUE").any():
                months.add(os.path.basename(f)[:6])
        except Exception:
            pass
    # recent clean
    months |= {"2024-" + f"{m:02d}" for m in range(3, 13)}
    months |= {"2025-" + f"{m:02d}" for m in range(1, 13)}
    months |= {"2026-" + f"{m:02d}" for m in range(1, 4)}
    return len(months), sorted(months)


if __name__ == "__main__":
    n, months = count_reliable_officer_months()
    print(f"[readiness] reliable signed-officer months available: {n}")
    print(f"  range: {months[0]}..{months[-1]}" if months else "  (none)")
    ready = n >= 60
    print(f"[readiness] DEFINITIVE cap-tier escape test can fire: {'YES' if ready else 'NO'} "
          f"(need >=60, have {n})")
    if not ready:
        print(f"  -> {60 - n} more months of signed officer net-buy needed from parallel backfill.")
    print("[readiness] When YES: re-run build_captier_panel.py (auto-ingests new months) + "
          "captier_decomp.py, then hand cap-tier-restricted scores to canonical_screen_bt.R.")
