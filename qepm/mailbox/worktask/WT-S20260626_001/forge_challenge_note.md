# Forge Challenge Note — WT-S20260626_001

**Agent**: forge
**Task**: A/B realized backtest — incumbent (AR×R05 product) vs max-cash (min) overlay combine.
**Verdict**: max-cash WORSE on all metrics. dIR = **−0.0224** (book-marginal gate needs +0.05 → **FAIL**). Hypothesis FALSIFIED.

## Self-challenges (pre-empting Codex)

### C-F1: Cash leg earns 0% — is that fair to both arms?
Source STR_1715 `03_period_returns.csv` has `risk_free_ret == 0` for all 269 months and `cash_weight == 0` (base sleeve collapsed to 1 pseudo-asset). I used cash=0 for BOTH arms. This is the **production layer5 convention** and keeps the A/B apples-to-apples: the incumbent production NAV vintage was built on the same convention. Using a non-zero cash rate would (a) help max-cash slightly LESS than incumbent in co-firing months (max-cash holds less cash there), making max-cash look even worse, and (b) break comparability with the deployed book. So cash=0 is the conservative-toward-the-hypothesis AND comparability-correct choice. **Caveat surfaced**: absolute SR levels would shift modestly upward (~+0.05–0.10 region) with a real KR call rate, but the **Δ direction is robust** (cash treatment is common-mode; the sign of dIR/dSR is driven by exposure-timing in co-firing months, not the cash rate).

### C-F2: Is the dMDD=0 hiding the real risk story?
Yes, by construction global MDD is governed by the deepest book drawdown, which does NOT fall in a co-firing window — so the single combine change can't move it. The honest risk signal is the **32-co-firing-month segment MDD**: incumbent −17.13% vs max-cash −23.58% (6.45pp worse). I report both: global dMDD=0 (PASS_TIE) and segment MDD (where the change actually bites). Judge should weight the segment, not the tie.

### C-F3: PIT — does min(beta_AR, beta_R05) introduce look-ahead?
No. Both betas are t-1 lagged (decision at end of t-1, applied to month t). min of two PIT values is PIT (order-preserving on PIT inputs). Verified: `invested_maxcash = m4 × min(beta_AR, beta_R05)` reconstructs from the schedule exactly (269/269 rows, 0 mismatch). Base sleeve selection unchanged (score_eff top-20 PIT, STR_1715 frozen). audit FAIL=0 after declaring lookahead_prevention.

### C-F4: Schedule Fidelity — did forge re-select holdings via top-N?
No. Holdings are IDENTICAL both arms (STR_1715 base sleeve, unchanged). NO `setorder(.., -score) + head(.., N)` re-selection. weights.csv / overlay_combine_schedule.csv used as-is (269 monthly dates 1:1 with production). Only the cash/risky scalar split differs in 32 months. No fabricated ProductionSchedule[N]m label. `pure_function_violation=false`.

### C-F5: Self-synthesis (measurement-graduation §1)?
Portfolio returns built via PerformanceAnalytics `table.AnnualizedReturns`/`maxDrawdown`/`CalmarRatio`/`SortinoRatio`; portfolio_alpha_t via NeweyWest lag-3. `cumprod` used ONLY for NAV display path + co-firing/GFC **segment cumulative diagnostics** (not as the metric source). BM monthly = compound of daily KOSPI200 `BM_Ret` (index aggregation, not portfolio synthesis). The arm return path itself (`risk_weight × ret_orig − cashleg_cost`) is a per-period scalar product of a PIT weight and a contract-produced base return — not a `(w*r).sum()` synthesis of names.

### C-F6: portfolio_alpha_t basis
Active series = arm monthly net return − monthly KOSPI200 return (from fresh `.cache/benchmark.parquet`, NOT the all-zero STR_1715 `05_benchmark_returns.csv`). NW lag-3 t on the active mean. Incumbent 4.63 / max-cash 4.57 — both strongly significant; max-cash 0.06 LOWER. (Note: these are overlay-arm active-t; the parent's frozen-alpha PORT_t is a separate lineage measurement, not re-litigated here.)

## Concerns I am NOT resolving (out of forge scope → judge/governor)
- **TDC vs PG2 book** (replacement-vs-integration): this is a within-strategy combine swap, not a new sleeve → governor.
- **Capital admit decision**: governor + Dohoon manual (not automatable).
- **Whether incumbent's own dIR-vs-incumbent is itself ≥0.05**: incumbent IS the book; the question is only whether the SWAP improves it. It does not.

## Bottom line for judge
max-cash combine swap should be **REJECTED/DEFERRED**. The architecture-audit B2 "compound over-defense drag" was the motivating hypothesis; realized A/B shows the compounding was **net-protective** in co-firing stress. Incumbent product overlay retained. All numbers fresh, both arms identical data/base/cost, metric_type=backtested.
