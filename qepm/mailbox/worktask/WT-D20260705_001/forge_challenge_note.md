# Forge Self-Adversarial Challenge Note — WT-D20260705_001

**Agent**: forge (Pure Function v6.1 R12) | **Model**: Opus 4.8 native adversarial (v8.2, no external Codex)
**Date**: 2026-07-05 | **Strategy**: XATTN 5-seed Cross-Sectional Attention super-factor
**AX-008 role**: Forge实测 source (3-source triangulation: Forge + Self-Adversarial + Architect, 2/3 PASS).

Authoritative result: **portfolio_alpha_t_nw_lag3 = 2.3616** (net active vs cap-w KOSPI200, NW lag-3),
net_IR 0.622, CAGR 21.8%, MDD 37.7%, Calmar 0.580, oos_retention 0.037.
Verdict: **SCREEN_TIER_FAIL** (HARD 3-gate all fail: PORT_t 2.36<2.95, oos 0.037<0.7, calmar 0.58<0.64).

Below I adversarially attack my own forge_package to surface fabrication risk, measurement-basis weakness, and interpretation traps.

---

## Challenge 1 (SR provenance / divergence basis) — MINOR_DRIFT, is the -0.27pp benign or masking a basis mismatch?

**Attack**: Optimizer claims net_port_t 2.633; Forge realizes 2.3616. I labeled this MINOR_DRIFT (-0.27pp, <0.6 threshold). But the optimizer used "RAWDATA monthly-compounded total returns + corrected IKS200 benchmark, walk-forward 197 dates" — *the same reconstruction basis I used*. If the basis is identical, why any drift at all? A -0.27pp gap between two supposedly-identical methods could indicate a hidden discrepancy (weight-drift handling, first-period entry, benchmark window alignment) rather than harmless discretization.

**Self-defense / evidence**:
- Cost reconciles **exactly**: Forge annual cost 163.7 bps == optimizer 163.7 bps (delta-based v2.4, 15bps × sum|dw|). Turnover reconciles exactly: mean(sum|dw|)*12 = 10.911 == optimizer 10.911. So the *net* return basis is provably identical.
- `Return.portfolio` composition verified against direct sum(w·r): max abs diff **2.4e-16**, cor 1.000. No composition artifact.
- The residual -0.27pp is most plausibly the optimizer's t-stat being computed on its own internally-reconstructed active series (possibly a slightly different NW lag or benchmark-window edge), vs my contract `build_benchmark_compare` NW lag-3 on the merged monthly series. Both are legitimate; neither is authoritative except **Forge (build_bt_result) = admission-binding by mandate**. The drift is well inside MINOR (|0.27|<0.6) and does NOT flip the verdict (both < 2.95).
- **Residual risk kept visible**: I did not run a lockbox daily-harness cross-check (sr_lockbox_daily_harness = null) because this is screen-tier and not admission-bound. If this alpha were ever re-attempted as capital-grade, that third SR source should be run to close the -0.27pp fully. Flagged, not resolved.

**Verdict**: MINOR_DRIFT is honest. The E2E pattern (proxy 2.63 → forge 2.36) reproduces the documented measurement-graduation reference (FLOW proxy 3.55 → forge 2.35). This is exactly the "rank-IC/optimizer proxy overstates realized alpha" mechanism the whole graduation system exists to catch.

## Challenge 2 (oos_retention collapse 0.037 vs optimizer 0.137 vs alpha -0.2) — which is right, and does my split choice fabricate a number?

**Attack**: Three agents report three different oos_retention: alpha -0.20, optimizer 0.137, forge 0.037. My v2 (median of 55/65/75 anchored splits) gives {0.037, 0.079, -0.129} → median 0.037. A reader could accuse me of split-shopping — picking a split scheme that happens to produce the most damning number, or of the metric being so unstable (spanning -0.13 to +0.08) that any point estimate is noise.

**Self-defense / evidence**:
- The *sign and magnitude* are unanimous across all three agents and all three of my splits: **oos_retention is deeply below the 0.7 gate, near zero or negative, under every split.** There is no split scheme that rescues it. The disagreement (0.037 vs 0.137 vs -0.20) is 2nd-decimal noise around a value that is unambiguously a FAIL. So the split choice cannot fabricate a PASS.
- The economic driver is not a measurement artifact: subperiod PORT_t is pre2018 **3.50** → post2018 **0.41** → post2022 **-0.31**. The alpha is entirely a pre-2018 phenomenon. This is the KR post-2017 cohort-wide decay (§6 decay-pattern), documented across all 6 super-factor methods and confirmed by the alpha agent's own challenge_flags (POST2022_DECAY, HIGH).
- Per measurement-graduation §3: oos_retention <0.5 is **unconditional FAIL** regardless of corroborating evidence, AND the sub-window post-2018 PORT_t is not >0 in a way that would even trigger the [0.5,0.7) band escalation. So no band-evidence path exists. FAIL is correct and over-determined.

**Verdict**: The metric is noisy in the 2nd decimal but the FAIL is robust to every split. I report all three splits transparently in forge_package (oos_splits field) so no cherry-picking is possible.

## Challenge 3 (benchmark vintage / alignment — is the KOSPI200 the right one, correctly lagged?) — MEDIUM residual

**Attack**: The alpha agent's BENCHMARK_ALIGNMENT_FIX flag documents that an ad-hoc bench was 1-month early-shifted, corrupting active returns (lag0 port_t 1.01 vs aligned 1.41). Memory also records the recent IKS200 vs IKS001 bug (benchmark.parquet was KOSPI-*all* not KOSPI200 until a 2026-07-02 fix). If my forge inherited a wrong-vintage or mis-lagged benchmark, my PORT_t 2.36 is on sand.

**Self-defense / evidence**:
- I load the **fresh `.cache/benchmark.parquet` (rebuilt 2026-07-05)** which is the corrected IKS200 (post-bug-fix per [[reference-benchmark-iks200-bug-fix]]). I compound BM_Ret over the **same (d_i, d_{i+1}] daily windows** as the asset returns and align by *realization date* — so the strategy's period-t return and the benchmark's period-t return cover the identical calendar window. This is the "signal-month → realization(t+1)" alignment the alpha agent used, not the corrupted lag0 or early-shift.
- Beta_to_benchmark = 0.867 (sane for a long-only 25-name growth-tilted book vs KOSPI200; a mis-lagged bench would give an impossible β like the 0.08 diagnostic in [[reference-book-benchmark-alignment-realized-ym]]). The β sanity-check passes.
- **Residual risk kept visible**: I did NOT independently re-verify the benchmark.parquet against an external KOSPI200 series (e.g., yfinance) this run — I trust the 2026-07-05 rebuild. If a benchmark regression were later found, PORT_t would move, but the verdict has margin: even the alpha agent's clean-vintage EW gives 1.41 and my AlphaProp 2.36, both < 2.95. A benchmark error large enough to flip to >2.95 (a ~+0.6pp swing) is implausible given the β sanity-check. Flagged as MEDIUM, not fully closed.

## Challenge 4 (deploy-extension OOS / last-period frozen window) — LOW

**Attack**: The last signal date is 2010-01..2026-05; I extended the final holding period to raw_max 2026-07-03 (deploy-extension mandate: frozen weights buy-and-hold to today). If that final ~1-month stub has an anomalous return, it could distort the tail of the series and the post-2022 subperiod.

**Self-defense**: The extension is a single ~34-day stub on 1 of 197 periods. It cannot move the full-series NW lag-3 t-stat materially. The post-2022 PORT_t (-0.31) is negative *with or without* it — the decay is structural, not a stub artifact. LOW severity, no verdict impact.

---

## Triangulation summary (AX-008)
- **Forge (this run)**: PORT_t 2.3616, SCREEN_TIER_FAIL. metric_type=backtested, audit integrity=WARNING (0 FAIL / 0 critical; 2 WARN = C15/lookahead self-scan skipped because Forge owns no factor_engine_path — expected).
- **Self-Adversarial**: 4 challenges raised; none flips the verdict. 2 residual risks kept visible (lockbox daily-harness not run; benchmark not externally re-verified) — both immaterial to a screen-tier FAIL with margin.
- **Convergence**: alpha (1.41 EW / SCREEN_TIER_FAIL), optimizer (2.633 proxy / SCREEN_TIER_FAIL), forge (2.36 authoritative / SCREEN_TIER_FAIL) — **all three agents independently reach SCREEN_TIER_FAIL**. The alpha does not transfer to realized net active at capital grade; it is a valid DPL-feature / factor-rotation RCMA-input candidate (screen-tier routing), not a capital-admission strategy.

**Fabrication check**: hash_integrity PASS (3-package byte-identical start→end), schedule_fidelity weights-as-is (no alpha_scores re-selection, no schedule fabrication), pure_function_violation=FALSE.
