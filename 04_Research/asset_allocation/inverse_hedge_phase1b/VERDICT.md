# Phase 1b — PREDICTIVE-GATE inverse-ETF hedge — VERDICT

**Date:** 2026-06-26 · metric_type=`backtested` (build_bt_result, PerformanceAnalytics std fns; audit PASS=12/FAIL=0).
**What changed vs Phase 1:** Phase 1 used a *non-predictive* lagged book-regime timer (fired on up-months). Phase 1b replaces it with the **Regime Forecaster v1 CHAMPION** (`.cache/regime_forecast_series.parquet`) — a genuine *next-month* prediction. This is the clean retry of the timing problem.
**Book (P0):** deployed overlay `STR_1715_AR_on_M4_R05_overlay_PG2`, realized net `ret_L5_V2`. **Hedge:** KODEX inverse 114800 (−1x, 2009-09+) / 252670 (−2x, 2016-09+), daily→monthly compound. **All policies ex-2026** (cut 2025-12). **Combination:** Return.portfolio, monthly rebal, hedge self-trade |Δw_h|×15bps.

## PIT handling (load-bearing)
The forecaster's `ym` column is the **forecast TARGET month** (the forecaster loop assigns `fc[t+1] <- pred` where `pred` is built from ≤month-`t` data — verified in `02_Infrastructure/regime/regime_forecaster.R` L50-87). So the gate for return-month `m` uses `forecast_regime[ym==m]` **directly, with NO extra shift** (an extra shift would double-count and leak). Gate-on = `forecast_regime == CRISIS` (the champion realizes only {RISK_ON, NEUTRAL, CAUTION, CRISIS}; there is **no RISK_OFF** in the actual data — CRISIS is the defensive argmax state). Alignment guard in code: when w_h=0 the portfolio return must equal the book return exactly (enforced; passes).

## 1. Gate predictive-fit pre-check (does CRISIS-forecast predict forward weakness?)
| series (window) | n | gate-on | fwd mean ON | fwd mean OFF | neg-share ON | worst-decile capture |
|---|---|---|---|---|---|---|
| book fwd (2009-09+, −1x win) | 196 | 12 | **−0.11%** | +3.17% | 0.50 | 0.20 |
| bm fwd (2009-09+, −1x win)   | 196 | 12 | **+2.05%** | +0.52% | 0.33 | 0.10 |
| book fwd (2016-09+, −2x win) | 112 | 7  | +0.01% | +2.54% | 0.57 | 0.17 |
| bm fwd (2016-09+, −2x win)   | 112 | 7  | +2.68% | +0.68% | 0.14 | 0.08 |

**Read:** The gate is *directionally* informative on the **book** (gated months avg ~0% fwd vs +3.2% off — it selects weak months) but **NOT on the benchmark** (KOSPI200 fwd mean is *higher* on gate-on months, +2.0% vs +0.5%). It captures only 10-20% of the worst-decile months. The forecaster fires on book/MSM-stress states that frequently do **not** translate into next-month KOSPI declines — so as a *hedge timer for an index-inverse ETF* it is weakly aligned at best. **This is the core problem: the instrument (inverse KOSPI200) profits when KOSPI falls, but the gate does not predict KOSPI falls.**

## 2. Headline (ex-2026, net, in-window MDD)
| Policy | n | mean w_h | CAGR | Sharpe | **MDD** | **Calmar** | CAGR bleed |
|---|---|---|---|---|---|---|---|
| P0 book100 (−2x win, 2016+) | 112 | 0 | 30.08% | 1.564 | −17.18% | 1.750 | 0 |
| P3a inv2x gated 5/10/15% | 112 | 0.3-0.9% | 29.7/29.4/29.0% | 1.550/1.534/1.517 | −17.13/−17.09/−17.06% | 1.735/1.719/1.701 | −0.4/−0.7/−1.0pp |
| **P0 book100 (−1x win, 2009+)** | 196 | 0 | **39.17%** | **1.857** | **−17.18%** | **2.280** | 0 |
| P3b inv1x gated 5% | 196 | 0.3% | 39.04% | 1.856 | −16.90% | 2.310 | −0.13pp |
| P3b inv1x gated 10% | 196 | 0.6% | 38.91% | 1.853 | −16.62% | 2.341 | −0.27pp |
| **P3b inv1x gated 15%** | 196 | 0.9% | 38.77% | 1.850 | **−16.34%** | **2.373** | −0.40pp |

At first glance P3b *appears* to win: it lifts Calmar 2.280→2.373 and trims MDD −17.18%→−16.34% while bleeding only −0.40pp CAGR. **But this is an artifact of one episode** — see §3.

## 3. ★ FRONTIER ANSWER: does the predictive gate cut bleed while keeping protection? — **NO**
Three independent tests dismantle the apparent P3b win:

**(a) Leave-COVID-out (drop 2020-02…2020-08):** the in-window MDD of P0 and **every** P3b policy collapses to **−14.21%, byte-identical**. Once the single COVID episode is removed, no gated policy changes MDD at all, and ex-COVID **Calmar P3b_15 = 2.899 < P0 = 2.927** — the hedge becomes a *pure loss* again. The entire MDD/Calmar "improvement" lives in one month.

**(b) The binding MDD (2020-04 trough) is only partially caught.** The drawdown ran 2020-02→2020-04. The largest leg, **2020-02 (book −8.2%), is NOT gated** (forecast=RISK_ON; the forecaster fired CRISIS only from 2020-03). The hedge helped at the *tail* of the crash (2020-03, hedge +8.2% → +1.67pp), which is why MDD nudges from −17.18% to −16.34% — but it misses the worst leg entirely.

**(c) Paired statistics (P3b_15 − P0, 196 mo):** mean −2.65 bps/mo, **cumulative drag −4.62%**, paired t=−1.20 (p=0.23). Over the 12 gated months the hedge **helped in 3, hurt in 9** (sum −5.08pp, t=−1.20). The hedge is a statistically-insignificant *net drag*; the headline Calmar gain rides entirely on 2020-03 (+1.67pp).

**(d) Proxy full-window cross-check (metric_type=`proxy`, 1990+, 28 gate-on months incl. dot-com/GFC/2011/COVID):** P0 Calmar 1.525 vs P3prox_15 Calmar **1.500** — the gated hedge is net-negative *across the entire crisis history*, not just the ETF era. (Proxy = −2·futures_beta·r_kospi200 − 114bps/yr; NOT capital-grade, diagnostic only.)

## 4. AX-001 crisis-conditional (in-window)
Within-window protection is **small and inconsistent**: 2020-COVID P3b_15 protection **−0.26pp** (negative — gate-on COVID months had book *outperforming*), MDD relief +0.93pp (the lucky 2020-03 leg). 2022-bear: protection −0.04pp, MDD relief −0.02pp (hurts). 2018Q4: **0.00** (gate never fired). So even conditionally, the predictive gate does not deliver reliable crisis_alpha for this instrument.

## 5. V-recovery give-back
2020-03→08: P3b_15 gives back −0.34pp (small, because mean w_h is tiny). P3a_15 (−2x) gives back −1.91pp. The give-back is modest *only because the gate fires rarely* — not because timing is good.

## 6. Overfitting discipline
- **chain, DSR not applied** (justified): the forecaster is a pre-validated CHAMPION from a *completed* ablation (v1tune/v2/v3/v4 all lost) — that selection is closed, not a sweep in this study. The w_h ∈ {5,10,15%} grid here is a sensitivity sweep, not a selection-for-argmax (all three lose ex-COVID; no cherry-pick).
- **OOS retention (50/50):** P3b ≈ 0.65-0.66 (≈ P0 0.665 — the hedge neither adds nor destroys OOS retention; it's a near-zero-weight overlay). P3a window shows >1 because the 2016+ sub-period has a stronger second half (book property, not hedge).
- **No P-value support** for any improvement (§3c).

## VERDICT — NO IMPROVEMENT (honest null, cleaner than Phase 1)
A *predictive* gate is genuinely better than Phase 1's lagged timer — it at least selects weak **book** months and fires near COVID. But it **does not predict KOSPI200 declines** (the thing an inverse-KOSPI ETF needs), captures only the *tail* of the one big in-window crash, and is a statistically-insignificant **net drag (−4.62% cum, helped 3 / hurt 9 gated months)**. The apparent Calmar win (2.280→2.373) is a **single-episode artifact (2020-03)** that fully reverses under leave-COVID-out and under the 1990+ proxy. **No P3 policy improves the drawdown-constraint objective in any robust sense.** Phase 1's structural conclusion stands, now for the right reason: the binding drawdowns are either pre-instrument (2006-07 global MDD) or pre-gate (2020-02 leg) — un-hedgeable by a gated inverse ETF whose gate cannot foresee the index drop.

## Honest blockers / caveats
- Champion forecaster has **only argmax labels, no state probabilities** — so the task's "P(CRISIS)+P(RISK_OFF) threshold" gate could not be tuned; gate = CRISIS argmax. A probability-threshold gate might fire on more months but the §1 misalignment (gate predicts book-stress, not KOSPI-direction) would persist.
- Real −2x 2026 is penny-stock noise; handled by ex-2026 cut.
- in-window MDD (−17.18%) ≠ Phase 1 global MDD (−24.81%): the 2006-07 global trough is outside both ETF windows by construction (correct per task §2).

**Artifacts** (`04_Research/asset_allocation/inverse_hedge_phase1b/`): `run_phase1b.R`, `summary_headline.csv`, `gate_fit_precheck.json`, `crisis_windows.csv`, `recovery_giveback.csv`, `oos_retention.csv`, `robustness_leave_covid_out.csv`, `proxy_fullwindow_diagnostic.csv`, and per-policy `{P0_*,P3a_*,P3b_*}/bt_result.rds` + `diag_monthly.csv` + 14-file save_bt_result outputs.
