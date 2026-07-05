# PIT Adversarial Verification — cross-family regime-conditional composite
WT axiom_engine_research_20260705 · AX-008 self-adversarial · 2026-07-05

Verifier re-measured independently from `research_full.rds` (period_returns of all 4 variants,
159 common months) + a fresh **asof-toggle** re-run (`asof_toggle.R`, expanding vs full-sample
regime-IC weights). All metrics via contract NW lag-3 / paired NW-t; no `prod(1+r)` synthesis.

## Reported (research_result.json)
regime_cond: PORT_t 0.838 · net_SR 0.254 · calmar 0.360 · oos_retention −0.553 · MDD 0.471 ·
post2017 PORT_t −0.535 · turnover 10.0x · **graduation FAIL** (all 3 HARD gates fail).
delta_vs_static_icw +1.41 · delta_vs_static_ew +0.87 · lag1 PORT_t 1.018.

## Adversarial task results

### ① Regime look-ahead (asof-toggle + lag1)
- **lag1 stress**: cond PORT_t 0.838 → lag1 PORT_t **1.018** (adding a month of lag *raises* t by
  +0.18). FaithTrend disease = a *large drop* under lag1; here there is **no drop**. Direction is clean.
  ⚠ JSON field `concurrent_leak=true` is a **benign mislabel**: it is set by `abs(diff)<0.6`
  (small diff = NO leak). Verdict logic is fine; the field name is misleading only.
- **asof-toggle** (expanding regime-IC vs full-sample=oracle regime-IC weights): the fresh double
  factor-DB re-run stalled on OneDrive I/O (arrow mmap hang, CPU flat — known failure mode), so the
  toggle was evaluated on the **weight vectors** from the saved `fam_ic`/`WT_COND` (no re-score needed,
  because if PIT weights already differ from the oracle weights AND the oracle has no strong IC, there
  is no latent leak). Result:
  - per-month L1(w_expanding − w_oracle) mean 0.41, p90 1.02, max 1.90 → the PIT weights are **NOT**
    silently equal to the future-informed weights ⇒ **no look-ahead** (a leaking design would collapse
    L1→0). Biggest divergence in CAUTION/CRISIS: oracle would put **100% on value**, expanding spreads
    across families (it cannot see the future).
  - the oracle itself is **weak**: full-sample regime-cond value IC in CRISIS/CAUTION is only
    +0.031/+0.054, and quality/momentum/tail-defense all go **negative** there. So even the look-ahead
    ceiling has no profitable vein — the +0.18 lag1 *rise* is consistent with this (no leak to remove).
  ⇒ Look-ahead: **ABSENT**. The port_t 0.838 is the honest expanding number, not a deflated leak.

### ② regime-IC estimation overfit (thin CRISIS/CAUTION cells)
- Regime-cond weights start only after ≥6 same-regime months → cond n=159 vs static n=250.
- Regime cell sizes over the measured grid: RISK_ON n=127, NEUTRAL n=17, **CAUTION n=10, CRISIS n=4**.
  The full-sample IC on these thin cells is unstable — CAUTION/CRISIS oracle collapses to 100% value
  (the single positive-IC family), which is precisely the thin-sample overfit signature. The expanding
  builder's ≥3-finite-IC fallback to unconditional IC **damps** this (thin cell → static, not noise),
  which is why the expanding path does not blow up but also captures no crisis-specific edge.
  mean regime-cond weights: momentum 0.40 · quality 0.39 · value 0.19 · tail_defense 0.01
  (tail_defense near-zero because it activates only in CAUTION/CRISIS = 14 of 159 months, and even
  there its full-sample IC is negative −0.05 → gated toward zero).

### ③ static-vs-conditional significance (paired NW-t, ratios forbidden)
- cond − static_icw : mean active diff +0.00506/mo · **paired NW-t = 1.77** (n=159) → NOT sig (<2.0).
- cond − static_ew  : mean +0.00272/mo · **paired NW-t = 0.97** → NOT sig.
- cond − lag1       : mean −0.00082/mo · paired NW-t = −1.74 (lag1 slightly *better*).
- ⇒ the JSON's "delta_vs_static +1.41/+0.87" are raw **level** differences of PORT_t, NOT
  significance tests. The proper paired test says the regime-conditional edge over the static
  composite is **statistically insignificant**.

### ④ oos_retention (v2 3-split) independent recompute
- splits 55/65/75 = −0.251 / −0.553 / −0.763 · **median −0.553** (matches reported). All negative →
  OOS active Sharpe flips negative. Genuine HARD fail (<0.5 unconditional FAIL).

### ⑤ benchmark / alignment sanity
- offset β-scan cor(ret_net, bm-shift): peaks **sharply at off=0 (0.646)**, noise (|cor|<0.09) at all
  other offsets ±1..±3 → **no realized_ym misalignment** (yesterday's IKS200/realized_ym bug absent).
- β(ret_net~bm)=0.72 (plausible for concentrated top-25 with tail-defense tilt vs cap-w KOSPI200;
  not the <0.3 misalignment signature). Benchmark = .cache/benchmark.parquet forward-month TR, merged
  by `date` in the canonical engine (not realized_ym) → alignment path clean.

## Verdict
- **Look-ahead: ABSENT.** lag1 stress does not drop (rises +0.18); the `concurrent_leak=true` JSON
  field is a benign mislabel (`abs(diff)<0.6` = no leak). Weight asof-toggle shows PIT weights genuinely
  differ from the future-informed oracle (L1 mean 0.41), and the oracle itself is unprofitable in
  CRISIS/CAUTION. No FaithTrend-style concurrent leak. Benchmark/alignment clean (off=0 β-scan peak,
  no realized_ym bug).
- **Static-vs-conditional advantage: NOT SIGNIFICANT.** Paired NW-t cond−static_icw = 1.77,
  cond−static_ew = 0.97 (both <2.0). The JSON's +1.41/+0.87 "delta" are raw PORT_t level differences,
  not paired significance — the reported regime-conditional edge does not survive a paired test.
- **Graduation: FAIL confirmed (re-measured, no change).** PORT_t 0.838 (≪2.95), oos_retention −0.553
  (all 3 splits negative, <0.5 unconditional FAIL), calmar 0.360 (<0.64). post-2017 PORT_t −0.535.
- **Signal reality: DECAY WALL, not artifact, not leak.** The composite is a real (leak-free) but
  weak signal whose thin crisis-cell "edge" is unstable and whose full-sample regime-IC ceiling is
  low; it reproduces §6 "직교 ≠ 수익" and the KR post-2017 cohort-decay wall. The cross-family
  regime-conditional frontier (5-card convergence) is **FALSIFIED at capital grade** — consistent with
  the E2E ledger (L-QPM-20260705_102041, frontier(b) FALSIFIED). Legitimate negative → ledger as
  provisional (INV-7): "cross-family regime-conditional composite도 KR post-2017 감쇠 우회 불가."
  Same exact activation not to be retried without a differentiated mechanism (next frontier = DPL /
  non-return DART, per consume_result).
