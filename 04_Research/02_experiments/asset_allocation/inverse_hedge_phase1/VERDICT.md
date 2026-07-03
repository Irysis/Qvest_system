# Track A Phase 1 — Inverse (-1x) ETF hedge sleeve — VERDICT

**Date:** 2026-06-26 · metric_type=`backtested` (build_bt_result, PerformanceAnalytics std fns, NW not needed for headline)
**Book (P0):** deployed overlay `STR_1715_AR_on_M4_R05_overlay_PG2`, realized net = `ret_L5_V2` (255m-admit panel SR 1.9253; full-269m SR 1.8968; MDD −24.81% exact match to book_state). NOT base STR_1715.
**Hedge:** KODEX inverse 114800 (-1x), daily `Ret_Inv` → monthly compound (apply.monthly). Coverage **2009-09…2026-03** only.
**Combination:** Return.portfolio (book + hedge sleeve), monthly rebal. Hedge self-trade |Δw_h|×15bps. ETF internal drag already in Ret_Inv.

## Headline (full period, net)
| Policy | CAGR | Sharpe | MDD | Calmar | CAGR bleed vs P0 |
|---|---|---|---|---|---|
| P0 book 100% | 40.88% | 1.897 | −24.81% | 1.648 | 0 |
| P1 static 5% | 38.72% | 1.852 | −24.81% | 1.561 | −2.16pp |
| P1 static 10% | 36.58% | 1.801 | −24.81% | 1.475 | −4.30pp |
| P1 static 15% | 34.45% | 1.743 | −24.81% | 1.389 | −6.43pp |
| P2 cond 15% (risk-off lag1) | 40.16% | 1.885 | −24.81% | 1.619 | −0.72pp |
| P2 cond 10% | 40.40% | 1.890 | −24.81% | 1.629 | −0.48pp |

## Two decisive facts
1. **Global MDD (−24.81%) is in 2006-07 — before the ETF existed (launch 2009-09).** Hence MDD is byte-identical across all 6 policies: the binding drawdown is structurally un-hedgeable by this instrument. The drawdown-constraint objective (MDD/Calmar) **cannot be improved** because no policy moves the global MDD.
2. **P2 conditional signal is mis-timed.** Lagged book-regime {CAUTION,CRISIS} fires mostly on *up* months (2018-12 +4.1%, 2019-02 +9.3%, 2026-01 +7.8% w/ hedge −21.2%, 2026-05 +14.3%). The book's regime label is post-decision state and does not predict next-month direction; lag-1 produces a near-random, mostly-wrong timer. P2 ≈ P0 (mean w_h 0.7%) but still net-negative.

## Crisis windows (AX-001 conditional) — within-window protection IS real but small
P1_15% lifts crisis cumulative return by +1.4 to +4.2pp (2020-COVID +3.64pp, 2022-bear +4.15pp) and shaves within-window MDD ~1–2pp. But these windows are NOT the global MDD, so the *constraint* metric is untouched. P2 contributes ~0 in real crises (signal didn't fire pre-COVID; fired wrong elsewhere).

## V-recovery give-back
2020-03→08 recovery: P1_15% gives back −6.25pp; P2_15% −2.92pp. 2025-26 mega-rally (book +297% over 18m) is where static hedge bleed concentrates.

## Verdict per policy
- **P1 static (5/10/15%):** REJECT. Pure bleed on every dimension (CAGR −2.2/−4.3/−6.4pp, Sharpe ↓, Calmar ↓). MDD unchanged. Drag dominates; crisis protection too small and in non-binding windows.
- **P2 conditional (10/15%):** REJECT. Near-neutral by accident (barely fires) but net-negative; the timing signal is wrong (lagged book regime ≠ market-direction predictor). No drawdown-constraint improvement.
- **Overall: NO IMPROVEMENT.** No inverse-ETF hedge policy improves Calmar or the drawdown-constraint objective. The book's worst drawdown predates the instrument, and the convexity benefit in genuine crises (real but ≤+4pp) is swamped by carry bleed in the up-trending majority. Bleed dominates — honest null.

## Caveats (load-bearing)
- ETF coverage starts 2009-09 → cannot test 2008 GFC or the 2006-07 global-MDD episode. Verdict on MDD is therefore conservative-favorable to the hedge (we GAVE the hedge every crisis it could possibly catch and it still didn't help the constraint).
- A *predictive* risk-off timer (not lagged post-hoc regime) was out of scope; P2's failure is partly a signal-quality failure, not proof a well-timed conditional hedge is worthless. But the structural MDD-timing problem (worst DD un-hedgeable) stands regardless.

Artifacts: `04_Research/asset_allocation/inverse_hedge_phase1/{P0_book100,P1_static_*,P2_cond_*}/bt_result.rds` + `summary_headline.csv` + `crisis_windows.csv` + `recovery_giveback.csv` + `aligned_inputs.csv`.
