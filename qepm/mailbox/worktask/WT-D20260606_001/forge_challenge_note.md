# Forge Challenge Note — WT-D20260606_001

**Agent**: forge_integration_v6.1_pure_function
**Codex stance**: REVISE (7 concerns: 3 HIGH, 3 MEDIUM, 1 LOW). No veto.
**Charter §8 No Silent Override** — each concern dispositioned ACCEPT / PARTIAL / REBUTTAL.

Codex was RIGHT on the central measurement-integrity issues. The revision materially **WEAKENS** the
draft's marginal-admit case: the corrected dual-alignment analysis shows the residual-mom sleeve does
NOT add return to the book; the positive dIR was an alignment artifact. This is reported honestly.

---

## C1 (HIGH) — Headline Sharpe is not the official bt_result Sharpe — **ACCEPT**

- **Codex**: draft headlined net Sharpe 1.6831 (Return.annualized/StdDev = CAGR/vol, geometric), but
  official `06_metrics.csv` Sharpe = **1.5599** (Charter v1.4 §12 arithmetic `mean(ER)/sd(ER)*sqrt(N)`).
- **Disposition ACCEPT**. Verified: official arithmetic Sharpe **1.5599**, CAGR/vol 1.6831. The contract's
  10-component output is authoritative. Final package headlines **net Sharpe 1.5599** and relabels 1.6831
  as `cagr_to_vol_ratio` (geometric). The optimizer's design 1.701 was ALSO CAGR/vol basis, so the
  apples-to-apples optimizer reconciliation uses 1.6831 vs 1.701 (NEGLIGIBLE 0.018); separately the
  authoritative arithmetic Sharpe 1.5599 is the judge-reporting figure.

## C2 (HIGH) — Active-SR OOS HARD fail explained but not neutralized — **ACCEPT (PARTIAL on framing)**

- **Codex**: oos_retention active-SR 0.171 < 0.7 is a HARD fail; inheritance from R05 (0.166) is
  attribution, not a gate waiver.
- **Disposition ACCEPT**. The draft framed inheritance as quasi-waiver — that was a soft rationalization.
  Corrected: I report the HARD active-SR fail at face value (NOT waived) AND recompute on the explicit
  **2024-01 lockbox boundary** (n_OOS=29): book active-SR retention **−0.149** (OOS active SR negative);
  book total-SR retention 1.293 (improves OOS). Most important, the **incremental book-vs-R05** OOS
  contribution (alignment-independent) = +0.29%/yr, incremental t = **0.09** (flat). The sleeve adds no
  measurable OOS edge. Reported as a genuine FAIL/flat, not a waiver.

## C3 (HIGH) — dIR pass is BM-alignment-sensitive at threshold — **ACCEPT (most material)**

- **Codex**: forge realized-month dIR +0.0593 vs optimizer fwd-shift +0.049; threshold crossing not robust.
- **Disposition ACCEPT — this is the single most important correction.** Dual-alignment table (computed):

  | basis | n | R05 IR | R05 β | book IR | book β | **dIR** |
  |---|---|---|---|---|---|---|
  | realized-month (forge, PIT-correct) | 268 | 0.7254 | 0.108 | 0.7848 | 0.244 | **+0.0593** |
  | signal-fwd-shift (optimizer bm_fwd) | 267 | 0.6609 | −0.054 | 0.6547 | −0.041 | **−0.0062** |

  The **sign of dIR flips** with BM alignment. Decisive resolution = the **alignment-independent**
  book-vs-R05 incremental (BM cancels): incremental return **IS −1.85%/yr (t −2.17), OOS +0.29%/yr (t 0.09)**.
  → **The sleeve DRAGS return in-sample and is flat OOS.** The +0.0593 realized-month dIR is NOT from added
  return — it comes from the sleeve lowering book active-vs-BM volatility / shifting beta, an effect that
  reverses under the other BM convention. **HONEST CONCLUSION: book-marginal ΔIR is NOT robustly positive.**
  This downgrades the draft's "meets threshold true" to **"alignment-dependent, not robust; incremental
  return is negative IS / flat OOS."** Aligns with risk RX-2 (cov-contribution 95%CI straddles 0) and the
  optimizer's own borderline +0.049.

## C4 (MEDIUM) — DSR=1.0 plausible but under-audited — **ACCEPT**

- **Codex**: n_trials=9 undercounts (alpha 8 + optimizer 9 = 17 min); _dsr.R proxy not rigorous.
- **Disposition ACCEPT**. Recomputed DSR across **N=9, 17, 50** and trial-SR dispersion factor {0.5, 1.0}:
  **DSR = 1.0000 in ALL cases** (sr0 ann ranges 0.16–0.47, book monthly SR 0.4503 over Tn=268). The 268-month
  high-SR sample saturates PSR regardless. Final package: `dsr=1.0, n_trials_reported=17 (alpha 8 + opt 9),
  robustness="DSR 1.0 across N=9/17/50"`. Honestly noted: DSR is NOT the binding overfitting gate here —
  oos_retention (C2) and incremental-return drag (C3) are.

## C5 (MEDIUM) — 5-spec Harvey audit absent — **PARTIAL (waiver)**

- **Codex**: only KOSPI200 active NW lag-3 present; CAPM/C3/C4/FF5/FF6 missing (RF-F6).
- **Disposition PARTIAL — discovery-stage waiver requested.** KR FF5/Carhart factor return series are NOT
  locally available (same honest disclosure as R05 forge_package §capm_regression "KR FF5/Carhart not
  locally available"). The contract-authoritative PORT_t vs KOSPI200 (NW lag-3) = 4.90 is the Gate-C metric
  per measurement-graduation §2 (portfolio-alpha t = forge-authoritative). 5-spec Harvey is deferred to
  judge if KR factor data is provisioned. `harvey_5spec_waiver=true, reason="KR factor series unavailable
  locally"`. Not spec-shopping (single benchmark spec, no selection among specs).

## C6 (MEDIUM) — Turnover/cost not self-contained in bt_result — **ACCEPT**

- **Codex**: book RT 1.056 (forge) vs 2.11 (optimizer); 03_period_returns turnover column blank.
- **Disposition ACCEPT**. Persist a companion `forge_turnover_audit.json` with explicit units:
  forge one-way = 0.5·Σ|Δw| (half-L1); sleeve ann RT = oneway×12×2 = 7.04; book ann RT = 7.04×0.15 = 1.056.
  Optimizer's 2.11 used L1-as-one-way (14.08 sleeve RT × 0.15). Both conventions noted; both PASS the 11.0
  ceiling either way. The blank period_returns turnover is a contract-builder limitation (holdings dcast on
  sleeve-leg book weights); companion artifact makes it judge-auditable.

## C7 (LOW) — NEGLIGIBLE divergence honest only for SR basis — **ACCEPT**

- **Disposition ACCEPT**. Scope "NEGLIGIBLE" strictly to the CAGR/vol SR divergence (1.701 vs 1.683). The
  active IR/beta differences vs optimizer are NOT negligible — they are the C3 alignment effect. Final
  package does not use the SR match to imply active-metric validation.

---

## Rationalization self-scan (grep "미미/관행/보수적이면/대부분 동일/inherited/negligible")
- "inherited" (C2): RE-FRAMED — no longer used to waive the HARD fail; reported at face value + incremental flat.
- "NEGLIGIBLE" (C7): scoped to CAGR/vol SR only.
- "marginal admit" (C3): DOWNGRADED — dIR not robustly positive; incremental return negative IS / flat OOS.

## Escalation check
- HIGH severity = 3 (< 5) → no auto-escalate threshold.
- No AX hard FAIL, no PIT C1 lookahead (forge alignment PIT-correct; alignment sensitivity is a measurement
  basis issue, not lookahead).
- BUT the C3 finding (sleeve does not add return) is a **material honest downgrade** Q-Lead/judge must see:
  the multi-sleeve diversifier's economic value is now ~zero on return (drag IS, flat OOS); only a weak,
  alignment-dependent IR/vol effect remains. This SHARPENS the optimizer's DPL-transition recommendation.

## Codex agreement
Forge ACCEPTS 5 (C1,C2,C3,C4,C6,C7) fully, 1 PARTIAL/waiver (C5). Stance REVISE honored — final package
revised on all accepted points. The net effect strengthens honesty: the book is NOT a confident admit.
