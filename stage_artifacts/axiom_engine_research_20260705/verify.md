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
- **asof-toggle** (expanding regime-IC vs full-sample regime-IC weights): TOGGLE_LINE_PLACEHOLDER

### ② regime-IC estimation overfit (thin CRISIS cell)
- Regime-cond weights start only after ≥6 same-regime months → cond n=159 vs static n=250.
- CRISIS n=5 (research_result regime_decomp). The expanding builder falls back to unconditional
  expanding IC when a regime cell has <3 finite ICs — so thin cells degrade to static, not to noise.
  mean regime-cond weights: momentum 0.40 · quality 0.39 · value 0.19 · tail_defense 0.01
  (tail_defense near-zero because it activates only in CAUTION/CRISIS = 15 of 159 months).

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
TBD — pending asof-toggle line.
