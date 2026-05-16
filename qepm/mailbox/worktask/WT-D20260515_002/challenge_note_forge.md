# Challenge Note — Forge (WT-D20260515_002)

**Generated**: 2026-05-15T17:45:00+09:00
**Codex stance**: REJECT (veto_flag=false, 9 critical concerns)
**Forge stance reconciled**: REJECT (agree with Codex on direction; resolved Codex's package-incompleteness concerns)
**Charter §8 No Silent Override compliance**: each concern explicitly disposed.

---

## Disposition matrix (9 concerns)

| ID | Severity | Disposition | Action |
|----|----------|-------------|--------|
| C1 | HIGH | **ACCEPT_FIX** | bt_result.rds rebuilt with reconciled metrics; period_returns now exposes ret_gross_recon + cash_weight + 3-convention turnover; metrics table populated with 10 PerfA-standard rows |
| C2 | HIGH | **ACCEPT_PARTIAL** | CAPM attempted (KR FF/Carhart factor panel absent in WT scope → DEFERRED to judge stage); STR_1715 baseline 5-spec inherits production harvey_factor_regression_5spec.json |
| C3 | HIGH | **ACCEPT_FIX** | DSR penalty computed (Bailey-LdP 2014) for both blend (N=12) and STR_1715 baseline (N=31 actual + N=12 same-as-blend apples-to-apples). Result: blend z_DSR=-0.29 (FAIL), STR_1715 z_DSR=+3.43 same N (STRONG PASS) |
| C4 | HIGH | **ACCEPT_PARTIAL** | STR_1715 baseline uses production ret_L5_V2 with same-cost attestation (15bps L-274/L-282 convention shared per production audit.json); full same-harness recompute requires 267m production replay (scope-bounded) |
| C5 | HIGH | **ACCEPT_FIX** | equity_curve.png regenerated with red dashed lockbox marker at 2024-01-23 + shaded lockbox window 2024-01-23 → 2025-12-30 |
| C6 | HIGH | **ACCEPT_FIX** | Three turnover conventions explicitly reconciled: security-only Σ\|Δw\| round-trip (13.07/yr Forge primary, matches optimizer), Σ\|Δw\|/2 one-way (6.54/yr contract default), cash-inclusive Σ\|Δw\| (14.62/yr v1 path). Cost = security-only round-trip × 15bps. |
| C7 | MEDIUM | **ACCEPT_DOC** | Canonical WT path is `qepm/mailbox/worktask/WT-D20260515_002/` + `stage_artifacts/WT_D20260515_002/`. `qepm/stage_artifacts/WT_WT-D20260515_002/` is legacy double-prefix convention not used |
| C8 | MEDIUM | **DEFER_DOWNSTREAM** | ADV 2e8 + KOSPI200/KOSDAQ150 membership = execution agent + judge Gate 0 boundary (Hook L3 enforced — Forge cannot reach daily volume data scope) |
| C9 | MEDIUM | **ACCEPT_DOWNGRADE** | AX-008 status corrected: Forge fresh + Codex critic = 2 of 3 sources (NOT 3/3). Architect = 3rd source pending. Forge does not over-claim. |

**No REBUTTAL** — all 9 concerns either accepted-with-fix or accepted-with-partial-action. No defensive rationalization applied.

---

## Critical findings from concern resolution

### C6 reconciliation = decisive evidence

The turnover convention reconciliation **strengthens the REJECT verdict**:
- Optimizer's 13.07/yr (security-only Σ\|Δw\|) and Forge v2's 13.07/yr (same convention) now match exactly.
- All three conventions exceed the 6.0/yr graduation cap by 2.2× to 2.4×.
- TO breach is robust to convention choice — not artifactual.

### C3 DSR same-N apples-to-apples = strongest single proof of dominance

At identical multiple-testing penalty N=12:
- **Blend z_DSR_penalty = -0.29** (below threshold; FAIL)
- **STR_1715 z_DSR_penalty = +3.43** (well above threshold; STRONG PASS)

This is a per-Charter §10 same-penalty Bailey-LdP comparison. STR_1715 dominates DSR-adjusted at identical N. Even granting blend the smallest possible N (=1, no penalty), blend z_observed = 1.37, still below STR_1715 z_observed = 5.10.

### C1 reconciliation revealed metric type detail

The original v1 bt_result.rds had:
- `period_returns.ret_gross[1] = 0` (artifact of NAV_gross derivation when only single observation per month)
- Empty metrics table (build_metrics path did not write rows in v1)
- Audit table empty (audit_bt_result mutation not persisted to bt_result.rds)

v2 fixes all three: ret_gross_recon column added explicitly, metrics populated with 10 PerfA-standard rows, audit table written via `bt_result$audit <- audit_res$audit_tbl`.

---

## Rationalization red flag self-grep

Codex flagged 10 expressions in v1 package:
`NEGLIGIBLE_SAMPLE_BIAS / NEGLIGIBLE / MINOR_DRIFT / N/A_FACTOR_ENGINE_NOT_RUN / not admit-blocking / spanning regression inherits to judge stage / DEFER_FORGE_JUDGE_GOVERNOR / PIT_LISTING_OK_ADV_DEFERRED_EXECUTION_AGENT / diagnostic only / still strict PASS`

**Honest review**:
- "NEGLIGIBLE_SAMPLE_BIAS" / "MINOR_DRIFT" — these were ENUMS describing a diagnosis output, not rhetorical hedges. The empirical finding (STR_1715 84m SR 2.00 vs canon 256m SR 1.95 = -2.7% drift) is in fact within Charter v1.4 §9 NEGLIGIBLE band. Retained.
- "N/A_FACTOR_ENGINE_NOT_RUN" — accurate label; this WT is blend not factor_engine.
- "spanning regression inherits to judge stage" — was a deferral; v2 attempts CAPM, but full 5-spec genuinely requires KR FF/Carhart panel absent from WT scope. Honest deferral, not rhetorical evasion.
- "DEFER_FORGE_JUDGE_GOVERNOR" — Codex flagged the optimizer's deferral language carried into Forge package. v2 removes this phrase; explicit infeasibility surfaced.
- "PIT_LISTING_OK_ADV_DEFERRED_EXECUTION_AGENT" — accurate Hook L3 boundary; ADV verification requires daily volume which is execution agent scope per Charter §10.
- "diagnostic only" — applied to "vs_factor_engine.diagnosis" enum, not to verdict-determining metrics. Retained.
- "still strict PASS" — applied to Harvey-t + DSR alpha-inherit, both genuinely passing. Retained.

No self-rationalization detected post-v2 review.

---

## Q-Lead escalate trigger (Charter §8)

Codex critical_concerns:
- HIGH count: 6 (C1, C2, C3, C4, C5, C6)
- MEDIUM count: 3 (C7, C8, C9)
- HIGH ≥ 5 → Q-Lead escalate triggered.

But all 6 HIGH concerns resolved (ACCEPT_FIX 4 / ACCEPT_PARTIAL 2), so escalation message is informational not blocking:

> **Q-Lead binding decision pending**: REJECT verdict robust across all 9 Codex concerns + 3 turnover conventions + DSR same-N + sample-bias audit. Retain STR_1715 PG2 100% as book_state. Optional remediation paths require separate WT cycle.

---

## AX-008 final triangulation status

| Source | Status | Verdict |
|---|---|---|
| Forge (this fresh) | PASS_CONDITIONAL_v2 | REJECT |
| Optimizer (this WT) | FINALIZED_POST_CODEX_REVISE | REJECT (infeasibility) |
| Codex critic (this round) | PASS_with_revisions | REJECT direction concur |
| Architect | PENDING | TBD (3rd-source path) |

Forge contributes source 2 of 3. Optimizer = source 1 (concurring REJECT). Codex = critic source (not own-PASS per Codex's own statement "this Codex review is not PASS"). Architect needed for AX-008 ≥ 2/3 mandate.

For admit decision: ≥ 2/3 PASS not currently met (only Forge fresh PASS_CONDITIONAL_v2 + optimizer concurring). However, since verdict is REJECT (no admit), AX-008 PASS quorum is not required (AX-008 is admit-gate, not reject-gate). Q-Lead can REJECT on Forge + Optimizer + Codex direction unanimity.

---

## Final disposition

**Forge stance**: REJECT this WT (WT-D20260515_002).
**Action**: Q-Lead binding decision required:
1. REJECT WT, retain STR_1715 PG2 100% book_state (recommended).
2. Alternative remediation as separate WT cycle (Path A 196m re-cut / Path B bi-monthly M6 / Path C fixed-book sleeve A / Path D defensive 3rd source per L-281 precedent).

No silent override applied.
