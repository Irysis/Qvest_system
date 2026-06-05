# Forge Challenge Note — WT-D20260529_001 FLOW

**Codex stance: REJECT (veto_flag=FALSE). AX-008 triangulation: Codex FAIL.**
**Disposition: 6 ACCEPT + 1 PARTIAL + 2 REBUTTAL. No silent override (Charter §8).**

Forge concurs with the substance: this FLOW sleeve is **NOT admission-grade**. The Codex round materially improved the package (5-spec Harvey, same-period baseline, DSR penalty, turnover fix, three-window split). The E2E *measurement objective* (does the proxy survive?) is answered: **NO on the full realized basis; the proxy reproduces only on its own truncated/benchmark-only basis.**

---

## C1 — 5-spec Harvey absent (HIGH) → PARTIAL ACCEPT

**Codex**: package gives only single KOSPI200 portfolio-alpha t; needs CAPM/C3/C4/FF5/FF6.

**Disposition: PARTIAL.**
- **ACCEPT (emitted)**: 5-spec Harvey NW-HAC now in `forge_remediation.json`. Result is *more damning* than the single t-stat:
  - FULL 2005-2026: **0/5 PASS** (CAPM t=2.53, FF5 t=1.90, FF6 t=1.94).
  - PRE-LB (proxy basis): **1/5 PASS** (CAPM 3.32 only; Carhart-3 2.86, FF5 2.47, FF6 2.44 — all FAIL).
- **REBUTTAL (scope)**: The v8.x **graduation Gate C authoritative metric IS `portfolio_alpha_t_nw_lag3`** (forge_package_schema.json line 22; Charter §8 SR Provenance), not the 5-spec. The 5-spec Harvey regression Gate is **judge's domain** (Gate 13/Harvey). Forge emits it as supporting evidence, not as the forge gate.
- **Quant insight (accept the lesson)**: the gap between PRE-LB portfolio-alpha t (3.66, vs KOSPI200 only) and PRE-LB FF5 t (2.47, style-adjusted) shows the FLOW edge is **partly SMB/HML/WML beta**, not pure residual alpha. The benchmark-only portfolio-alpha t *overstates* tradeable alpha. This strengthens REJECT.

## C2 — MDD 58.79% breaches 45% hard cap (HIGH) → ACCEPT

**ACCEPT.** Elevated to a first-class rejection reason. MDD (daily NAV basis) = **58.79%**; monthly-basis MDD = **49.14%**. Both breach the 45% base hard constraint. Driver: 2008 GFC on a beta≈1.0–1.16 long-only sleeve. Recorded in `mdd_hard_constraint`. This is an independent hard-fail beyond Gate C.

## C3 — No same-period recomputed baseline (HIGH) → ACCEPT

**ACCEPT.** Same-period STR_1715 baseline now computed (`same_period_baseline`), realized monthly, **same 219-month overlap (2008-02~2026-04), same net basis**:
- STR_1715: SR 0.829, portfolio-alpha t **3.20**, IR 0.679, DSR_post **3.66**.
- FLOW (same period, n_cands=26 penalty): SR 0.741, portfolio-alpha t **2.43**, IR 0.614, DSR_post **1.82**.
- **FLOW underperforms the incumbent on every axis as a standalone.** Its only documented value is as a *blended diversifier* (optimizer: book IR +0.33), not as a replacement. No "PG2 documented baseline" in, only same-period recompute (RF-F4 satisfied).

## C4 — Realized DSR + candidates_tried penalty absent (HIGH) → ACCEPT

**ACCEPT.** Realized DSR with penalty `n_cands = 26 × 0.05` (alpha 15 factor-level + optimizer 11 sleeve configs, disclosed) now in all three windows + baseline. FLOW FULL DSR_post 2.26, same-period 1.82 vs STR_1715 3.66. Penalty applied to FLOW; STR_1715 incumbent labeled with 0 extra (not re-shopped here — honest label, not double-standard).

## C5 — Turnover convention inconsistent (HIGH) → ACCEPT

**ACCEPT — real bug.** `06_metrics.csv` `Annualized_Turnover = 163.296` is the **contract's `build_metrics` x252 daily-annualization applied to a quarterly per-rebal turnover** — invalid for non-daily rebalance. Reconciled:
- per-rebal one-way L1 = 0.648 → **× 4 (quarterly) = 2.59/yr one-way = 5.18/yr round-trip** (matches optimizer's 5.51 round-trip).
- `forge_package.json ann_turnover` uses the corrected 2.59/yr one-way convention; the 163.296 contract metric is flagged invalid in `turnover.contract_note`. (Upstream contract fix candidate: annualize turnover by rebal-cadence not x252.)

## C6 — Canonical artifacts / monthly_returns.parquet (HIGH) → PARTIAL/REBUTTAL

- **REBUTTAL (paths)**: Codex probed wrong paths. Canonical inputs DO exist: `stage_artifacts/WT_D20260529_001_FLOW/weights.csv` (76 dates), packages in `qepm/mailbox/worktask/WT-D20260529_001/`. Codex's guessed `qepm/.../weights.csv` and `WT_WT-` paths are not the contract paths (artifact-naming.md single-prefix).
- **ACCEPT**: `monthly_returns.parquet` now emitted (256 months) in `backtest_result/`.
- Schedule density 0.336 < 0.95 is **honest infeasibility** (optimizer INFEAS-2: quarterly FORCED by TO hard cap; alpha monthly TO 10.66 FAIL). NOT a silent skip. `schedule_density_pass=false` labeled.

## C7 — Sleeve-only vs 55/45 book max_names (HIGH) → REBUTTAL

**REBUTTAL.** This WT is explicitly a **FLOW-sleeve discovery E2E** (wt_type=discovery). The 55/45 STR_1715+FLOW book (38-name union) is the optimizer's **escalated INFEAS-3 / qlead_escalation** item — STR_1715 full historical per-date holdings are unavailable in this WT, so a combined ≤20-name book CANNOT be reconstructed honestly. Forge correctly labels the result **FLOW-sleeve-only** and does not fabricate a combined book. Resolving the book architecture (AX-007 fund-of-sleeves vs combined-20) is a **Q-Lead architecture decision**, not a Forge fabrication. Reference: optimization_package `infeasibility_report.INFEAS-3` + `qlead_escalation`. (학술: AX-007 multi-sleeve exception permits max_names 20 per sleeve.)

## C8 — Σ universe mismatch (MEDIUM) → REBUTTAL

**REBUTTAL.** The selected method is **EW hysteresis buffer, which does NOT consume Σ for sizing** (optimizer `covariance_universe_note`: "selected EW sleeve does NOT consume Sigma; Sigma entered only the disqualified MVO/HRP/ERC/MinVar/CVaR comparison"). Forge backtest is **share-based NAV reconstruction — Σ-independent**. The A014820/A112610 covariance row mismatch is immaterial to the realized backtest. `strategy_spec.risk_controls "Sigma w=1"` refers to weight-sum constraint (Σw=1), not covariance Σ consumption — wording clarified. L3 weight constraints (Σw=1, [0,0.20], max 20, long-only) all verified PASS.

## C9 — Three-way Pre-LB/Lockbox/Combined metrics absent (MEDIUM) → ACCEPT

**ACCEPT.** Three-window split now in `three_window`:
- FULL: SR 0.779, pa_t **2.350**, IR 0.540, ann excess +8.79%.
- PRE-LB (proxy basis): SR 0.781, pa_t **3.663**, IR 0.853, ann excess +13.49% (≈ proxy 3.55 / 14.13% — measurement chain VALID).
- LOCKBOX-OOS 2024+: SR 0.735 (vol-relative) but pa_t **−2.397**, IR **−1.488**, ann excess **−34.73%** — frozen weights actively destroyed relative value (FLOW +56.6% vs KOSPI200 +188.9% over 29 mo).

---

## Rationalization red-flag self-audit (Codex flagged 5)

Codex flagged "FORCED by TO hard cap", "do NOT fabricate monthly holdings", "standard multi-sleeve QEPM interpretation", "small-but-real", "entirely normal". Audit:
- "FORCED by TO hard cap" / "do NOT fabricate monthly holdings" — these are **optimizer's** infeasibility language quoted in context, and they are *correct* (Schedule Fidelity Mandate explicitly prohibits fabricating monthly holdings; quarterly is the honest resolution). NOT a forge rationalization — they are constraint-honoring statements with quantitative basis (TO 10.66 vs 5.93). Retained.
- "small-but-real" (market-residual cross-corr) / "standard multi-sleeve" — optimizer's wording, not forge's. Forge does not rely on them for any approval claim.
- **No forge approval claim rests on a rationalization.** Forge's verdict is REJECT-grade — the opposite of rationalizing toward acceptance.

## Verdict (Forge)

**FLOW sleeve = NOT admission-grade (standalone).** Independent hard-fails: (1) portfolio-alpha t FULL 2.35 < 2.95 Gate C; (2) MDD 49–59% > 45%; (3) 5-spec Harvey FULL 0/5, PRE-LB 1/5; (4) same-period < incumbent STR_1715 on every axis; (5) frozen-weights OOS pa_t −2.40.

**E2E proof DELIVERED (the actual WT objective)**: the v8.x real-computation (WS1) + graduation gate (WS2) chain **works as designed** — the alpha-stage proxy (3.55) was correctly *not* rubber-stamped; on the full realized share-based basis it down-shifts to 2.35 (near-identical to Cycle 2's D ML 4.31→2.31). The measurement chain is validated (PRE-LB forge 3.66 ≈ proxy 3.55, SR 0.78 ≈ 0.817). FLOW's documented role remains a **blended diversifier** (optimizer book IR +0.33), pending Q-Lead book-architecture decision (INFEAS-3).

**No HIGH-severity escalation beyond the existing Q-Lead INFEAS-3 escalation** (Codex 6 HIGH are all addressed/rebutted; none is a PIT C1 violation or AX hard-fail). veto_flag=FALSE.
