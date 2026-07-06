# INSIDER cap-tier ESCAPE test — VERDICT (directional, NOT graduation)

**Date**: 2026-07-06 · Q-Lead findings-driven · analysis-only (parallel session owns backfill)
**metric_type**: `directional_read` (event-cohort active + cross-sec rank-IC; NOT canonical_screen_bt / forge PORT_t)
**Power caveat**: 42 distinct signal-months, GAPPY (2005-06 backfill + 2015 + 2024-03~2026-03). Underpowered — a directional read, not a capital-graduation test.

## THE QUESTION
Does exec insider net-buy ESCAPE the cap-tier trap (picking skill among mega/large-caps) or is it another mid/small-cap alpha?

## CORE RESULT — cap-tier decomposition (exec-only, major-shareholder excluded)

| Tier | rank-IC (NW-t) | long buy-active bps/mo (NW-t) | buy−sell spread bps (NW-t) |
|---|---|---|---|
| **MEGA (top-10)** | +0.070 (**+1.01**) | +71 (+0.94) | +341 (**+1.94**) |
| MID (11-30) | −0.006 (−0.08) | −66 (−0.96) | −100 (−0.68) |
| LARGE (11-50) | +0.062 (+1.48) | +10 (+0.17) | +149 (+0.89) |
| BIGCAP (top-50) | +0.078 (+1.83) | +10 (+0.21) | +127 (+0.94) |
| **REST (>50)** | **+0.159 (+4.96)** | **+330 (+5.19)** | **+386 (+5.92)** |
| ALL universe | +0.101 (+4.62) | +200 (+4.85) | +247 (+3.92) |

**The signal is overwhelmingly a SMALL-CAP (REST >50) phenomenon** — same cap-tier trap as price signals, NOT an escape. In the deployable large-cap universe (top-50 = K200-ish core), the long-active is ~+10bps NW-t 0.2 (dead).

## THE ONE NUANCE — MEGA is NOT fully dead (unlike price signals which are t≈0.6)
- MEGA **buy−sell spread +341bps NW-t +1.94** (full), and the **sign-only signal** (buy=+1/sell=−1, robust to amount outliers) in MEGA = **rank-IC +0.22, NW-t +3.18 over 25 months**.
- MEGA buy-only long-active: +122bps NW-t +1.65 (full), +160bps NW-t +1.93 (recent 25-mo), positive in 58% of months.
- BUT: only **~3 buy-names/month in MEGA** (thin) — cannot form a standalone top-N sleeve; sign-IC t=3.18 rides on a 25-month series.

## CANONICAL long-only active (metric_type=directional_read, 42-mo gappy)
- All-universe exec-net-buy **top-25 EW long-only: +243bps/mo, NW-t +5.78** — driven by REST small-cap tilt (not deployable in large-cap).
- **BIGCAP (top-50) restricted: +24bps/mo, NW-t +0.53** — the escape COLLAPSES in large-caps.

## VERDICT: escape thesis is DIRECTIONALLY REFUTED as a clean large-cap sleeve, with ONE live residual
1. Exec insider net-buy does **NOT** escape the cap-tier trap as a portfolio: its portfolio edge lives in small-caps (REST t≈+5), and the large-cap (top-50) long-only edge is ~0 (t≈0.5). Same trap as price signals at the **portfolio** level.
2. BUT it is **not signal-DEAD in MEGA the way price signals are** — the MEGA directional (sign) content is real-ish (sign-IC t=+3.18, buy−sell +341bps t=+1.94). This is a genuine directional distinction from momentum/reversal (mega t≈0.6). The problem is **breadth** (~3 names/mo), not zero information — so it can't (yet) be a standalone mega sleeve, but it is a candidate **conditioning/overlay feature** on big-caps rather than a discard.

## Honest bottom line
- **As a stand-alone active-PORT_t escape: NO** (directionally). The deployable large-cap long-only edge is ~0 (t=0.5); the strong t comes from small-cap REST — the trap, not the escape.
- **As "does insider carry ANY mega-cap picking content the price signals lack": weak YES, directionally** (MEGA sign-IC t=3.18) — but too thin (3 names/mo) and too gappy (25-42 mo) to graduate; a feature, not a sleeve.
- The full historical test (≥60 mo signed officer, ~10 mo out) will resolve: (i) whether MEGA sign-IC t=3.18 survives out of the 2024-26 mega-cap-semi regime and into 2010-19; (ii) whether a canonical_screen_bt large-cap long-only clears PORT_t 2.95 (today 0.53 — very unlikely) vs. remains a feature.

## Data / PIT notes
- Exec filter: officer position (등기/비등기임원), EXCLUDE 주요주주/10%이상주주/사실상지배주주 (pension/holding noise, e.g. 국민연금공단 confirmed as major-shareholder rows).
- Sign convention verified: `sp_stock_lmp_irds_cnt` / `qty_change` signed = +buy/−sell share count.
- PIT t-1 confirmed: F1[ym] = mret[ym+1]; signal from filings known at month-end t, held during t+1. No look-ahead.
- Cap-tier = PIT Size rank WITHIN K200∪KQ150 each month (MEGA≤10 / MID 11-30 / LARGE50 31-50 / REST >50).
- No prod(1+r)/cumprod self-synthesis; active = signal EW − universe EW, NW lag-3 t.

## Harness readiness (definitive test on backfill completion)
- Currently **50 reliable signed-officer months** available; need **≥60** → **~10 months short** (matches ~10-day backfill ETA).
- `build_insider_signal.py` (parallel): integrates backfill CSVs + clean parquet → exec net-buy scores + forward IC; auto-flags "canonical_screen_bt 가능" at ≥60 mo.
- Helper `run_definitive_when_backfill_lands.py` (this dir) polls reliable-month count and gates the definitive run.
- On completion: re-run `build_captier_panel.py` (auto-ingests new months) + `captier_decomp.py` for powered cap-tier NW-t/IC, then hand cap-tier-restricted scores to `canonical_screen_bt.R` for forge-authoritative MEGA/BIGCAP PORT_t + oos_retention/placebo/holdout.

## Artifacts (this dir)
- `build_captier_panel.py`, `exec_captier_panel.parquet`, `universe_monthly.parquet`
- `captier_decomp.py` → `captier_decomp.csv`, `captier_decomp_recent.csv`, `coverage_by_tier_month.csv`
- `captier_decomp_hifi.py` → `captier_decomp_hifi.csv` (5-mo cross-check, underpowered)
- `mega_probe.py` (MEGA focused), `run_definitive_when_backfill_lands.py` (readiness helper)
