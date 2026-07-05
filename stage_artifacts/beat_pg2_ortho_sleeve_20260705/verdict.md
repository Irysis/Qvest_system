# Verdict — Multi-sleeve book vs PG2 (adversarial)

**As-of**: 2026-07-05 · **Incumbent**: `STR_1715_on_M4_R05_noLayer4_PG2` (score_eff top-20 linear-tilt × overlay m4×β_R05) · **PG2 recon IR = 1.4238** (net_active_recon_v1, pinned cache RAWDATA_pin20260703 + benchmark_pin20260703 IKS200) · **Success bar** = book-marginal ΔIR≥0.05 **AND** paired NW-t≥2.0, then oos_v2≥0.7 (capital).

---

## ⚠ FIRST: the reported experiment was INVALID (silent join bug)

The delivered `multisleeve_*.json` files were **all identical** — every candidate/blend reported `book_ir=1.4238, dIR=0, paired_nw_t=NaN, oos=0.451`, i.e. **byte-identical to PG2**. This is not "no orthogonal alpha exists"; it is a **bug**:

- **Root cause**: `eval_book()` (harness.R) merges base and sleeve on raw `Date`+`Ticker`. But base `alpha_scores.parquet` dates are **first-of-month** (`2004-01-01`) while factor_db sleeves are **month-end** (`2005-01-31`). Overlap = **0 rows** (verified: `(Date,Ticker) pair overlap = 0`). So `sz` (sleeve z) was forced to 0 everywhere → `blend = (1-w)·z(score_eff)`, a positive scalar rescale of the base → **identical top-20 ranking → book == PG2 exactly**. (Ranking-invariance confirmed: top-20 under 0.7·z identical to unscaled.)
- **Fix**: merge on `ym`(year-month)+`Ticker` → 71,504/80,879 base pairs match. Verified fast recon engine reproduces PG2 IR **1.4238 exactly** (drift 0.0000) when sleeve weight = 0, and produces genuinely different books when stacked (258/270 months differ).

All numbers below are from the **corrected** engine (grid-precompute recon, PIT-identical to `recon_book_gross`: same top-20, same t-1 ADV liquidity 2e8, same linear_tilt λ=1.5/φ=3, same overlay, same IKS200 benchmark over (start_d,end_d]).

---

## Corrected results (recon-vs-recon, same pinned cache)

| sleeve | family | best blend | book_IR | dIR | paired NW-t | oos_v2 | calmar | mdd | standalone active-IR | active-cor vs PG2 |
|---|---|---|---|---|---|---|---|---|---|---|
| **C07_TP_Mom** | estimate | 45% | **2.632** | **+1.208** | **+11.4** | **0.75** | 4.83 | 0.215 | +2.85 | 0.63 |
| **M27_Analyst_Rev_Mom** | est-revision | 45% | 1.884 | +0.461 | +4.79 | 0.48 | 3.07 | 0.208 | +1.85 | 0.67 |
| **C02_EPS_Chg_1m** | earnings | 45% | 1.877 | +0.453 | +4.80 | 0.47 | 3.06 | 0.208 | +1.82 | 0.66 |
| V24_Residual_Income | value | 15% | 1.445 | +0.021 | +1.45 | 0.43 | 1.84 | 0.246 | −0.10 | 0.48 |
| V15_NetDebt_Adj_EP | value | 15% | 1.379 | −0.045 | −0.69 | 0.40 | 1.69 | 0.261 | −0.15 | 0.41 |
| V14_EBIT_EV | value | 15% | 1.380 | −0.044 | −0.76 | 0.40 | 1.63 | 0.270 | −0.21 | 0.40 |
| V02_EP | value | 15% | 1.372 | −0.051 | −1.21 | 0.40 | 1.62 | 0.270 | −0.17 | 0.43 |
| Q04_Piotroski_F | quality | 15% | 1.458 | +0.034 | +0.68 | 0.42 | — | — | — | — |

(blend_w on base; sleeve weight = 1−blend. Full grid in `scratchpad/cache_eval_results.csv` + `eval_results.csv`.)

---

## (A) Does any multi-sleeve book beat PG2 (ΔIR≥0.05 AND t≥2.0)?

**On the raw success bar: YES — the earnings/estimate family (C07, M27, C02) clears ΔIR≥0.05 AND paired-t≥2.0 at every blend, decisively. C07 even clears the oos_v2≥0.7 capital gate (0.75 at 45% sleeve).**

**But on adversarial look-ahead scrutiny: NO — the excess is a concurrent-information artifact, not a t-1 tradable alpha.** This is the load-bearing finding.

**Lag+1 stress test** (re-run stacking with the sleeve shifted one extra month, so only *prior-month* factor values inform the current portfolio — a genuine t-1 momentum-type signal should degrade gracefully, not invert):

| sleeve (45% blend) | dIR lag+0 | marg-t lag+0 | dIR **lag+1** | marg-t **lag+1** |
|---|---|---|---|---|
| **C07_TP_Mom** | +1.208 | +11.4 | **−0.324** | **−1.14** |
| **C02_EPS_Chg_1m** | +0.453 | +4.80 | **−0.326** | **−2.85** |
| **M27_Analyst_Rev_Mom** | +0.461 | +4.79 | **−0.291** | **−2.58** |
| Q04_Piotroski_F (control) | −0.422 | −2.90 | −0.380 | −2.58 |

The entire excess of C07/C02/M27 **collapses and inverts** with one extra month of lag. The control Q04 (annual fundamental, 5-month lag) is lag-insensitive — proving the test discriminates. All three winners are **short-window revision factors** (C07 = TP change / last 35d; C02 = EPS change / last 1m; M27 = analyst-revision momentum) whose value dated `Date ≤ sig_d` co-moves mechanically with the very-recent price action, and the forward-return window (portfolio formed at first trading day ≥ sig_d) captures continuation of that same move. The factor build code (`compute_consensus.R`) does enforce `Date ≤ sig_d` at the file level — so this is not a coding bug but an **intrinsic concurrency/PIT-in-spirit leak (C5/C14)**: the signal is not exploitable at t-1.

**Verdict (A): No genuine PG2-beating multi-sleeve book found. The candidates that clear the statistical bar fail the look-ahead falsification.**

## (B) How close, and what blocked it

- **Earnings/estimate family (C07, M27, C02)**: got the closest — headline dIR +0.45 to +1.21, paired-t +4.8 to +11.4, and C07 cleared oos 0.75. **Blocker = look-ahead** (lag+1 collapse to negative dIR). Not sleeve-PORT_t weakness, not overlay saturation, not orthogonality — the alpha simply isn't there at t-1.
- **Value family (V02/V14/V15/V24)**: genuinely failed on merit. **Standalone active-IR is negative (−0.10 to −0.21)** — as a top-25 tilt these dilute PG2 (dIR ≤ +0.02, none clear t≥2.0), worsening as sleeve weight rises. This confirms `[[reference-kr-value-factor-decay]]` + AX-003: the original scan's high `standalone_port_t` (2.4-3.0, canonical EW) was a **pre-2015 artifact masking post-2015 decay**; as an overlaid linear-tilt sleeve they are dead. The scan's ranking metric (canonical top-25 EW PORT_t) did not predict stacked marginal value.
- **Orthogonality note (④)**: the original scan's `active_cor < 0.30` (e.g. V15 0.010, M27 0.064) is **misleading** — it measured the raw factor's canonical top-25 active vs book active. The *stacked-book* active-cor vs PG2 is **0.40-0.67** (earnings family 0.63-0.67). These sleeves are **not** orthogonal to PG2 on active basis. Consistent with §6 "직교 ≠ 수익": orthogonality was never the binding constraint — and here neither orthogonality nor raw PORT_t predicts real marginal contribution; only the lag-robust t-1 alpha does, which is absent.
- **oos / decay (②)**: the sub-0.7 oos_v2 of M27/C02 (~0.48) is a **cohort-wide decay pattern, not overfit** — PG2 itself decays identically (PG2 active SR pre-2017 1.90 → 2017+ 0.87, retention 0.46, *worse* than the stacked books). So oos<0.7 alone would not have disqualified marginal admission; the look-ahead did.
- **Benchmark/alignment sanity (⑤)**: PASS. PG2 recon IR 1.4238 vs target 1.416 (drift +0.008, pinned-cache reproduction). BM = IKS200 over (start_d,end_d] compounding (no realized_ym misalignment, no IKS001 mis-select, no by-group global-vector). Pure-base fast-engine reproduces PG2 exactly.

## (C) Next levers

1. **Retire short-window revision sleeves for the book.** C07/C02/M27 (and the earnings@1m family generally) are look-ahead traps at monthly rebalance — do **not** promote. This aligns with, and sharpens, `[[project-earnings-revision-3m-horizon-lead]]`: the *3-month-horizon* earnings signal may be real, but the *1-month/35-day* revision momentum used here is concurrency leakage. **Re-test the earnings family exclusively at a 3M formation→hold horizon with mandatory lag+1 falsification** before any stacking claim.
2. **Fix the scan's selection metric.** The delivered scan ranked by canonical top-25 EW `standalone_port_t` + `active_cor<0.30`; both **failed to predict stacked marginal value** (value's high port_t → negative stacked-IR; earnings' low active_cor → 0.66 stacked cor). Future sleeve hunts must score on **corrected `eval_book` marginal ΔIR + mandatory lag+1** directly, not proxy port_t/cor.
3. **The value sleeve direction is settled-negative for stacking** (standalone active-IR negative across V02/V14/V15/V24) — do not re-propose KR value tilts into this book. Consistent with `[[reference-kr-value-factor-decay]]`.
4. **PG2 stands.** No orthogonal-sleeve stack survives adversarial verification. The SR-2.5 lever remains overlay/DPL/uncertainty (§6), not new long-only factor sleeves at monthly horizon. If any residual-orthogonal sleeve is pursued, the RAMP 18-candidate active-basis PORT_t path (with lag+1) is the remaining untested route.

---
**Bottom line**: The reported "PG2 unbeaten (dIR=0)" was a join bug. The corrected experiment *does* surface earnings/estimate sleeves that beat PG2 statistically (C07: IR 2.63, t +11.4, oos 0.75) — but **all of them are look-ahead artifacts** (lag+1 → dIR negative). **No multi-sleeve book genuinely beats PG2 (1.416) under PIT-honest t-1 measurement.** Value sleeves fail on merit. No promotion to forge/judge/governor.

*Artifacts*: `scratchpad/eval_from_cache.R` (engine, grid-based, PIT-verified), `grid.rds`, `cache_eval_results.csv`, `eval_results.csv` (M27), `adversarial_generic.R` + lag-stress logs, `run_fast_all.R`/`harness.R` fix. Pinned cache honored throughout; segfault-guarded (grid precompute isolated, per-factor single-parquet cache).
