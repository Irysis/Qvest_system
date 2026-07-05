# Self-Developing Cycle 1 — Benchmark-Aware Construction: VERDICT

**Date**: 2026-07-06 | **metric_type**: `weighted_screen` (screening-tier; a milestone requires Cycle-2 forge-authoritative re-measure) | **Governor**: NOT touched (measurement only).

## Fixed setup
Universe K200∪KQ150, monthly, 2005-01…2026-06 (258 usable months), long-only ≤25 names, w∈[0,0.20], Σw=1, 15bps one-way delta, liquidity ≥2e8 KRW. Base alpha FIXED = **12-1 skip-1 momentum** (PIT: cumret t-12..t-1). Anchor = top-K by **lagged** market cap (Size at month-end t) — we pick by size KNOWN at t, never the winners. Active denominator = cap-weighted KOSPI200 total return (real `BM_Ret`). BM proxy validated: reconstructed cap-w K200 vs real KOSPI200 cor **0.971**, mean ann 12.76% vs 12.54%.

## Construction menu (active PORT_t vs cap-weighted BM)
| variant | PORT_t | post2017_t | pre2020_t | post2020_t | oos_ret | max_wt | top2_wt | turnover | IR | active_share | milestone |
|---|---|---|---|---|---|---|---|---|---|---|---|
| V1 EW-top25 (the wall) | 1.42 | −0.14 | 1.88 | −0.06 | −0.13 | 0.040 | 0.080 | 7.10 | 0.31 | 0.934 | ✗ |
| V2 CapW-top25 | 1.47 | 0.47 | 1.47 | 0.55 | 0.21 | 0.183 | 0.331 | 8.36 | 0.31 | 0.923 | ✗ |
| V3 BM-weight-hold | 1.47 | 0.47 | 1.47 | 0.55 | 0.21 | 0.183 | 0.331 | 8.36 | 0.31 | — | ✗ |
| **V4 Anchor2 + EW-fill** | **2.91** | 1.68 | 2.60 | 1.38 | **0.60** | 0.200 | 0.400 | 4.67 | 0.58 | 0.712 | ✗ (near-miss) |
| V5 Anchor2 + alpha-fill | 1.60 | 0.56 | 1.56 | 0.70 | 0.51 | 0.200 | 0.400 | 5.33 | 0.32 | 0.726 | ✗ |
| V6a Anchor1 + alpha-fill | 1.22 | −0.07 | 1.66 | 0.15 | 0.00 | 0.200 | 0.361 | 6.58 | 0.26 | — | ✗ |
| V6b Anchor3 + alpha-fill | 0.98 | 0.51 | 0.67 | 0.72 | 1.22 | 0.200 | 0.400 | 4.38 | 0.20 | — | ✗ |
| V6c Anchor5 + alpha-fill | −1.59 | −0.21 | −2.23 | −0.05 | 0.18 | 0.200 | 0.400 | 2.33 | −0.34 | — | ✗ |
| VN NULL-alpha EW (3-seed) | −0.62 | −1.75 | 0.61 | −1.42 | −2.01 | 0.040 | 0.080 | 21.84 | −0.13 | — | ✗ |
| VN NULL-alpha Anchor2 EW-fill | 0.88 | 0.21 | 1.14 | −0.03 | 0.13 | 0.200 | 0.400 | 13.54 | 0.17 | — | ✗ |

**Milestone candidates: 0.** Gate = PORT_t≥2.95 ∧ post2017>0 ∧ oos≥0.7. Best (V4) misses on BOTH PORT_t (2.91<2.95) and oos (0.60<0.7).

## (A) Mega-cap drag decomposition (EW baseline, Brinson allocation vs cap-w K200 proxy)
- EW top-25 momentum book holds **0.6%** on the top-2 mega-caps vs BM's **25.4%** → a **24.7pp structural underweight**.
- This underweight is a **−2.2%/yr drag** (anchor names contribute −0.266 of total reconstructed active). The residual selection contributes **+10.3%/yr**. → The wall is **construction (mega-cap underweight), not selection** — selection is fine; the diversified EW structure loses the mega-cap allocation.
- K=3 version: 27.8pp underweight, −1.6%/yr anchor drag.

## (B) Anchor-vs-alpha separation
- **Anchor is the lever, fill wants to be EW not alpha.** Anchor2+EW-fill (2.91) >> Anchor2+alpha-fill (1.60). Alpha-tilting the fill *hurts* post-2017 (EW-fill post2017 0.49 vs alpha-fill −0.62 in the real-BM subperiod cut).
- **NULL-alpha anchor2** (random fill) already gives PORT_t 0.88 vs EW's 1.42 — the anchor mechanically recovers benchmark tracking; the momentum fill adds the rest to reach 2.91.
- K generalization: **K=2 is special, NOT a broader rule.** K=1 (1.22) < K=2 (2.91) > K=3 (0.98) > K=5 (−1.59, negative). The peak at exactly 2 matches the top-2 (Samsung+Hynix ≈ 30% of universe cap) dominance — beyond 2, anchoring forces low-cap names to benchmark weight and destroys value.

## Adversarial checks
- **Closet-index?** Partially. V4 active-share = **0.712** (vs EW 0.934) — 40% of the book sits on benchmark mega-caps, dropping active-share ~22pp. Still 71% active (not a full closet index), but the "active" t is inflated by benchmark tracking: momentum selection holds a top-2 mega-cap in only **33/258 months (12.8%)**, so the anchor forces exposure the alpha would never choose. The lift is a **benchmark-tracking effect, not an alpha edge.**
- **Hynix-2023 AI-run artifact?** No — V4 improves in BOTH 2017-22 (t 0.49) and 2023-26 (t 1.92) subperiods, and pre-2020 (2.60). Not a single-run artifact. But full-period t is carried heavily by 2011-16 (t 2.45); post-2017 remains weak (0.49-1.68 depending on NW window).
- **Concentration risk**: V4 runs 40% in two single names (Σ blowup / capacity risk). Real deployment single-name risk.

## VERDICT
**No deployment-grade milestone. Benchmark-aware construction (mega-cap anchor) closes MOST of the post-2017 wall but does NOT clear the graduation gate, and does it substantially by closet-indexing the mega-caps rather than by alpha.** The wall is confirmed to be **largely a cap-weighted-benchmark / construction artifact** (24.7pp mega-cap underweight = −2.2%/yr drag), NOT a selection failure — but the fix (anchor) buys back benchmark tracking, not edge. Anchor2+EW-fill is the near-miss (PORT_t 2.91, oos 0.60).

## What Cycle 2 should test
1. Re-measure V4 (Anchor2+EW-fill) **forge-authoritative** (canonical_screen→build_bt_result) — screening 2.91 may move either way.
2. Attack the concentration/closet-index problem: **partial anchor** (e.g. anchor top-2 at 10-12% not 20%, halving the 40% concentration) to test if edge survives with less benchmark hugging — find the anchor-weight that maximizes *residual* (over-BM) alpha, not raw active-t.
3. The **residual over-benchmark** metric: measure active t AFTER removing the mechanical mega-cap allocation (regression of port active on the anchor over/under-weight) — isolate whether ANY genuine alpha survives once benchmark tracking is netted out. If it does not, benchmark-aware construction is settled as closet-indexing.
4. Non-momentum base alpha (earnings, as the parallel session used) hit PORT_t 4.76 / post2017 2.61 on V4-equivalent but still oos 0.55 — cross-check whether base-alpha choice changes the oos ceiling.
