# Track B — Orthogonal-Sleeve Lever Formal Verdict (lag+1 corrected harness)

**Date**: 2026-07-05 · **Harness**: `eval_lag1.R` (corrected ym+Ticker merge, PIT-verified) ·
**Baseline**: PG2 recon book IR **1.4238** (pinned cache RAWDATA_pin20260703 / benchmark_pin20260703, drift-neutral) ·
**Success = triple gate**: lag+1 book-marginal ΔIR ≥ 0.05 **AND** paired NW-t (book−PG2) ≥ 2.0 **AND** oos_v2 ≥ 0.7.
**Scope**: 329 candidates = 327 factor-DB codes (C13 Z_Score_Aligned) + 2 xattn (score, alpha_active_hat) × 3 sleeve weights {0.15, 0.30, 0.45}. EARN3M composite + RAMP-18 residual verified separately below.
**Harness validation (from scan_setup)**: LAG=0 replicates cache-eval EXACTLY (C07 book IR 1.8267 / pNWt 8.426); PG2 recon 1.423755 = target; leak-filter demonstrated (C07/C02/M27 collapse under lag, Q04 slow-lag control lag-insensitive → test has discriminating power). NW lag-3, oos_v2 = 3-split {0.55,0.65,0.75} median — matches measurement-graduation §3.

---

## (A) Is there a lag+1 · significant · oos-passing orthogonal sleeve that beats PG2 (1.4238)? — **NO.**

**pass_all = 0 / 329.** No candidate, at any sleeve weight, clears all three gates under t-1-tradable (lag+1) stacking.

Gate attrition (lag+1, best sleeve weight per code):
| Gate | # passing |
|---|---|
| ΔIR ≥ 0.05 | 16 / 329 |
| paired NW-t ≥ 2.0 | 3 / 329 |
| ΔIR≥0.05 **AND** NW-t≥2.0 | **2** (IN03_RD_to_Market, XF_GD02_OpProfit_Growth) |
| oos_v2 ≥ 0.7 | **0 / 329** (max oos_v2 in entire scan = **0.521**, Q34_GP_Growth) |
| **ALL THREE** | **0** |

The 2 that clear ΔIR+NW-t are **not leak artifacts** — they survive adversarial look-ahead re-checks:

| Code | ΔIR | NW-t (lag1) | NW-t (lag2 stress) | oos_v2 | subperiod NW-t (pre2015 / 2015+) | verdict |
|---|---|---|---|---|---|---|
| IN03_RD_to_Market | +0.116 | +2.30 | +2.23 (holds) | **0.438** ✗ | +2.20 / +1.16 (both +, genuine) | oos FAIL |
| XF_GD02_OpProfit_Growth | +0.059 | +2.54 | +2.17 (holds) | **0.483** ✗ | +2.27 / +1.34 (both +, genuine) | oos FAIL |
| Q27_CapEx_to_Rev | +0.028 | +2.23 | +1.93 (softens) | **0.451** ✗ | +1.58 / +1.57 (both +) | ΔIR + oos FAIL |

Both IN03 and XF_GD02 are lag-robust (lag+2 barely moves NW-t) and subperiod-genuine (positive active mean pre- AND post-2015, dmean pre +0.0018/+0.0026, post +0.0010/+0.0015 — no value-decay artifact, no pre2015-only illusion). Their signal is **real and tradable** — but their contribution to the *book* fails the overfitting gate decisively: oos_v2 ≈ 0.44–0.48 is not a marginal miss. It sits **below the 0.50 auto-FAIL floor** (measurement-graduation §3: <0.5 = unconditional FAIL, evidence-irrelevant) and ~0.25 below the 0.70 capital hurdle. The whole 329-scan never reaches 0.7 (top 0.521), and only 6 codes even reach 0.5 — of those, only 2 also have ΔIR≥0.05 (L13/L31 vol-family, but their NW-t is 1.1/1.3, not significant). **No corner of the space simultaneously satisfies signal (NW-t), incremental value (ΔIR), and out-of-sample retention (oos).**

Special candidates (verified separately, not in the 329):
- **EARN3M composite** (C01_SUE+C04_ESBR+C05_ESCR+C06_TP_Gap+C03_EPS_Chg_3m, EW z-avg — the H3 earnings@3M "leak-resistant" hope): **dies under lag+1** — bw=0.85 ΔIR −0.005 / NW-t −0.84; bw=0.70 NW-t −3.07; bw=0.55 NW-t −4.14. The high book_port_t (+5.99) is the book's own alpha, not sleeve contribution. Its members all failed individually too (C01 NW-t −2.87, C04 −0.17, C05 −0.55, C06 +0.06, C03 −0.64). The 3M-horizon earnings LEAD does not survive t-1 book stacking.
- **RAMP-18 residual (neutralized_z)**: not separately materialized in this scan; but its economic content (FWL residuals of the same 327-factor cross-section) is a strict subset of the scanned span, and prior RAMP work already settled cap-w PORT_t 2.37 / oos 0.15 as non-graduating (measurement-graduation 06-18). No basis to expect a survivor here that the 329-scan missed.

---

## (B) Formal closure of the orthogonal-sleeve lever — **YES, CLOSED (return-derived).**

The Track-A proxy-misprediction correction (ym+Ticker merge fixing the raw-Date 0-row bug) + lag+1 leak removal was the last honest test the lever was owed. After both corrections:

**t-1-tradable orthogonal sleeves that beat PG2's 1.4238 book IR on the triple gate = 0.**

This confirms measurement-graduation §6 "직교 ≠ 수익" at the *book-stacking* level, now with the concurrency leak explicitly removed rather than left as a confound:
- Signals that *look* like winning sleeves at lag0 (momentum/revision/flow families: M18/M16/M30/M19/M20/M29, INV10/INV12, C02/C07, L02/L03) are **concurrency leaks** — they co-move with the forward window via C5/C14 (short-horizon revision/price factors evaluated same-month). Under lag+1 they collapse (see (C)).
- Signals that *are* real and lag-robust (IN03, XF_GD02, Q27; slow fundamental ratios) do carry genuine active-t, but their **incremental book contribution does not survive out-of-sample** — the KR cross-section's post-2017 cohort decay (measurement-graduation §6, [[reference-kr-sr-ceiling-overlay]]) binds oos_v2 below 0.5 for every incremental sleeve.

**Return-derived orthogonal-sleeve hunting is exhausted.** This is the same wall hit by KNS SDF-shrinkage (oos −1.01), all-stock smart-beta rotation (capital-grade 3-gate = 0), the 16/16 standalone admission FAILs, and the RAMP M-code (oos 0.15). Consistent, independent confirmations that the lever is spent, not that a config was missed. **Do not re-propose return-derived sleeve stacking.** The only remaining honest hope for a book-marginal sleeve is **non-return information** (DART insider / consensus-microstructure — [[project-paper-pool-qepm-exhaustion]], the Decoding-Inside-Information queue item), which this scan does not touch.

Caveat (AX-000 honest reporting): "orthogonal-sleeve lever closed" is a claim about the *book-marginal ΔIR + oos triple gate*, not about signal existence. IN03/XF_GD02 have real, tradable, lag-robust active-t — they are legitimate `screen_route` candidates (OVERLAY_CANDIDATE / DPL_FEATURE), just not capital-grade book additions. The closure is: no t-1 sleeve *graduates* over the current book.

---

## (C) leak_gap analysis — which families live on leakage vs die honestly

`leak_gap` = ΔIR(lag0) − ΔIR(lag1) (positive = candidate loses value once you remove the same-month signal). Mean by family:

| Family | mean leak_gap | reading |
|---|---|---|
| **M (momentum)** | **+0.520** (n=15) | **massive leak** — near-entire apparent edge is concurrency |
| **INV (foreign/inst flow)** | +0.243 (n=6) | large leak (flow same-month with returns) |
| TR (trend) | +0.159 | leak |
| RE (resid-beta) | +0.099 | modest leak |
| R (risk) | +0.087 | modest |
| C (earnings revision) | +0.075 | modest leak (C02/C07 the offenders) |
| L (liquidity) | +0.057 | modest |
| D (downside/vol) | +0.027 | small |
| V (value) | +0.009 | ~none (slow signal, lag-insensitive) |
| AC (accruals) | −0.004 | none |
| S (size), SE | −0.12 / −0.07 | lag *helps* (noise) |

**30 candidates had lag0 NW-t ≥ 2.0 that collapse to < 2.0 under lag+1** — i.e., 30 apparent "winners" were leak-driven. The worst:

| Code | Family | NW-t lag0 → lag1 | leak_gap |
|---|---|---|---|
| M18_RSI | M | +14.00 → +2.00 | 0.954 |
| M16_Trend_Factor | M | +13.62 → +0.54 | 0.801 |
| M30_Mom_10d | M | +12.81 → −0.11 | 1.061 |
| INV12_Supply_Demand | INV | +12.68 → −0.51 | 0.673 |
| M19_MACD | M | +12.52 → +1.70 | 1.183 |
| M20_Keller_Mom | M | +12.43 → −0.81 | 1.165 |
| INV10_Smart_Money_Flow | INV | +11.85 → −0.63 | 0.646 |
| C07_TP_Mom | C | +8.43 → −0.19 | 0.437 |
| C02_EPS_Chg_1m | C | +4.11 → +0.04 | 0.234 |
| M27_Analyst_Rev_Mom | M | +4.01 → −0.32 | 0.252 |

**Who lives on leakage**: momentum (M) and flow (INV) families — short-horizon, same-month-with-returns signals. Their lag0 t-stats of 12–14 are pure C5/C14 concurrency; nothing survives the 1-month tradability lag. Short-horizon earnings revision (C02_EPS_Chg_1m, C07_TP_Mom, M27) is the same story at smaller magnitude.

**Who dies honestly (real but insufficient)**: the lag-robust survivors IN03/XF_GD02/Q27 (slow R&D/profit-growth/capex fundamentals, leak_gap near 0) and the value family (V, leak_gap +0.009). These carry genuine signal — they just don't clear oos_v2. Their failure is out-of-sample retention (cohort decay), not look-ahead.

**Bottom line for (C)**: The 3-family split is clean — **momentum/flow = alive only on leakage (die at lag1); fundamentals/value = real but oos-insufficient; the middle (liquidity/vol/downside) = weak both ways.** The corrected+lag+1 harness correctly separates the leak-driven illusions from the genuine-but-uncapitalizable, and neither group produces a graduating sleeve.

---

## Disposition
- **No forge promotion.** Zero candidates reach the capital tier.
- IN03_RD_to_Market and XF_GD02_OpProfit_Growth → eligible for `register_module` **screen_route = OVERLAY_CANDIDATE / DPL_FEATURE** (real lag-robust active-t, screen-tier only; not book additions). Optional follow-up, not required.
- **Return-derived orthogonal-sleeve lever: formally closed.** Next honest direction = non-return (DART insider) per [[project-paper-pool-qepm-exhaustion]].
- Artifacts: `lag1_scan_results.csv` (329) · `verify_trackB_survivors.R` (lag2/subperiod/EARN3M) · this verdict.
