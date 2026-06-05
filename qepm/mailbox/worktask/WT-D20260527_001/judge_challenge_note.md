# Judge Challenge Note — WT-D20260527_001 STR_1719_WT001_DCA_v7

**Agent**: judge
**Codex Round**: 1 (v6.0 mandate)
**Date**: 2026-05-27
**Codex stance**: **APPROVE_CONDITIONAL** (1 HIGH + 4 MEDIUM concerns; REJECT verdict validated)
**Codex weakest_assumption**: "The weakest assumption is that the MDD hard fail makes every deferred Judge statistical, baseline, and scenario-rule gate safely non-decisive even if Q-Lead later considers a waiver or partial alpha-library path."

Codex APPROVE_CONDITIONAL means the REJECT verdict itself is correct but the draft has presentation defects to fix before final publication. This note documents ACCEPT / PARTIAL / REBUTTAL classification per Charter §8 No Silent Override.

---

## C1 — RF-J2/RF-J8 Deferred 5-spec Harvey + ad hoc DSR/1.05

**Codex** (HIGH, RF-J2 / RF-J8 / AX-002):
> "Judge defers 5-spec portfolio Harvey regressions and substitutes a rough DSR adjustment of 0.998/1.05. That is acceptable only because MDD already forces REJECT; it is not an approval-grade statistical gate."

**Verdict: ACCEPT-full**

Codex is technically correct. The Pre-LB MDD hurdle FAIL is decisive, but the Judge draft's "Gate 12-16 DEFERRED_VERDICT_DECISIVE" wording, combined with the ad hoc 0.998/1.05 DSR estimate, leaves the statistical robustness audit incomplete on paper.

**Action**:
- Mark Gate 12-16 as `DEFERRED_REJECT_PRIMARY` (not "DEFERRED_VERDICT_DECISIVE") — clearer that the gates were not run, not that they were judged invalid.
- Replace ad hoc DSR estimate with: `dsr_post_penalty: "NOT_COMPUTED_REJECT_PRIMARY"` (explicit non-computation, not pseudo-computation).
- Document that any future waiver / partial alpha-library admission path REQUIRES full 5-spec + valid DSR re-run.

**Cross-citation**:
- AX-002 process honesty: explicit non-computation > faux computation
- RF-J2 (Harvey 5-spec) / RF-J8 (DSR method shopping) per codex base context

---

## C2 — Lockbox Date Inconsistency

**Codex** (MEDIUM, RF-J3 / PIT-C1 / AX-002):
> "Lockbox dates are inconsistent across artifacts: base context says 2024-01-23, request uses 2024-01-01, Judge lockbox audit starts 2024-01-02, while the official hurdle window extends to 2024-01-30."

**Verdict: ACCEPT-full**

Codex correctly identifies that 4 different "lockbox start" candidates exist across artifacts:
1. **2023-12-31** — alpha_signal_cutoff in alpha_package.json
2. **2023-12-28** — last sig_date in weights.csv (optimizer cutoff)
3. **2024-01-01** — alpha_package window_isolation.lockbox_window.start
4. **2024-01-02** — Judge harness Lockbox audit execution (first trading day post-cutoff)
5. **2024-01-23** — qepm_codex_base_context.md default lockbox_start (judge_lockbox_harness.R default arg)
6. **2024-01-30** — Forge backtest end_date (1-month forward MTM through last business day)

**Normalization** (Judge final verdict adopts):
- **Pre-LB hurdle measurement window**: 2016-01-04 to 2024-01-30 (Forge bt_result.rds, 1986 trading days, 8.07 years). This is the OFFICIAL hurdle window.
- **Judge Lockbox forward measurement window**: 2024-01-02 to 2026-04-30 (566 trading days). Used for post-hoc forward validation only.
- **Strategy alpha/risk/opt signal cutoff**: 2023-12-28 (last sig_date in weights.csv). PIT lockbox 2024-01-01+ never accessed during alpha/risk/optimizer computation.

The window 2024-01-02 to 2024-01-30 (21 trading days) is BOTH within Forge bt and within Judge Lockbox — this is the natural "1-month forward MTM" zone. Per lockbox-scope.md (forge=폐기), Forge legitimately extends through 2024-01-30. Judge Lockbox excludes this overlap by starting at 2024-01-02 (different measurement methodology: frozen vs Forge MTM).

**Action**: Add `lockbox_date_normalization` block to final verdict explicitly listing all 6 candidates + the canonical 3 (Pre-LB hurdle / Judge Lockbox forward / signal cutoff).

---

## C3 — Discovery Scenario Rule Audit Implicit, Not Explicit

**Codex** (MEDIUM, RF-J6 / AX-002 / L-219):
> "RF-J6 scenario classification is implicit rather than explicit. This is a discovery WT, not Replacement or Sequential Admission, yet Judge discusses STR_1715 baseline and possible partial alpha-library treatment without a formal scenario-rule block."

**Verdict: ACCEPT-full**

Per request.json `wt_type=discovery` and `discovery_of=null`, this WT is NOT:
- Replacement scenario (not replacing STR_1715 in active book)
- Sequential Admission (PG2 already admit; STR_1719 not seeking PG2 entry per request)
- Integration scenario (no blender request)

Judge's secondary use of STR_1715 baseline in Gate 18 is **comparative reference only** (same-period comparable benchmark for context), NOT a Sequential Admission TDC threshold application.

**Action**: Add `scenario_rule_audit` block to final verdict:
```json
{
  "wt_type_per_request": "discovery",
  "scenario_classification": "discovery_only",
  "is_replacement": false,
  "is_sequential_admission": false,
  "is_integration": false,
  "STR_1715_baseline_role": "comparative_reference_for_context_not_TDC_threshold",
  "sequential_admission_TDC_misapplied": false
}
```

---

## C4 — AX-007 "MARGINAL" Should Be "FAIL"

**Codex** (MEDIUM, AX-007 / RF-J7 / L-484):
> "AX-007 is left as 'MARGINAL' with a 15-name M06 portfolio described as closer to a multi-sleeve exception. AX-007 exceptions do not cleanly include a 15-name single portfolio; final rejection avoids admission error, but Gate 5 AX should be marked FAIL rather than ambiguous."

**Verdict: PARTIAL (acknowledge, mark differently)**

Codex argues 15-name single portfolio does not cleanly satisfy any AX-007 exception (multi-sleeve / long-short / 50+ / ML sizing). I partially agree.

**However**, technical AX-007 reading:
> "structure=single_sleeve_long_only_top20, signal-portfolio translation 메커니즘 단절. 예외 4종 (multi-sleeve / long-short / 50+ 분산 / ML sizing)."

DCA v7 is structurally:
- 4-family alpha composite (4 factor families weighted equally)
- M06_MVO_Breadth optimizer with breadth constraint (n=15, HHI 0.088)
- NOT pure "top-20 long-only single sleeve"

This is closer to **multi-axis composite tilt** (one of the implicit AX-007 spirit exceptions) than pure single-sleeve top-20. But 15 names < 50+ doesn't satisfy the literal "50+ 분산" exception either.

**Resolution**: Update verdict to label AX-007 as `FAIL_LITERAL_BORDERLINE_INTERPRETIVE`:
- Literal reading: 15 names is single-sleeve-ish, FAIL on 50+ test
- Interpretive reading: 4-family composite mechanism, multi-axis composite tilt
- Final: classified FAIL per Codex C4 strict reading. Even interpretive PASS doesn't rescue from MDD hurdle FAIL.

**Action**: Change AX-007 status from "MARGINAL" to `FAIL_LITERAL_15_NAMES_BELOW_50_PLUS_EXCEPTION`.

---

## C5 — RF-J5 Echo Chamber Risk on AUTO_SELF_REBUT

**Codex** (MEDIUM, RF-J5 / AX-008 / AX-002):
> "Judge accepts several AUTO_SELF_REBUT resolutions while risk-side TDC/PG2 crowding, tail-cap interpretation, and true P3 marginal contribution remain only partially verified. This does not overturn the hard-fail REJECT but weakens any future waiver path."

**Verdict: ACCEPT-full**

Three AUTO_SELF_REBUT events in this WT:
1. Alpha agent: AUTO_SELF_REBUT to Codex REJECT via Iter5-7 fixes
2. Risk agent: AUTO_SELF_REBUT to Codex REJECT via rev2 fixes
3. Optimizer agent: AUTO_SELF_REBUT to Codex REJECT via v2 fix of C1 (weights.csv M04→M06 mismatch)

Each AUTO_SELF_REBUT was independently valid (HIGH count < 5 + no PIT C1 violation + no AX hard FAIL per Decision Protocol). However, the cumulative pattern (3 of 4 agents AUTO_SELF_REBUT, only Forge submit_with_flag) raises RF-J5 echo risk.

**Mitigation acknowledgment**:
- Forge did NOT AUTO_SELF_REBUT — Forge correctly forwarded HARD_HURDLE_FAIL flag.
- Codex (this judge_critic) provides independent cross-model REVIEW.
- Judge's verdict is therefore based on:
  - Forge's explicit hurdle FAIL flag (NOT auto-rebut)
  - Codex's cross-model judge_critic REVIEW (NOT auto-rebut)
  - Realized backtest numbers (deterministic, NOT rebut-able)

**Action**: Add `echo_chamber_mitigation` block:
```json
{
  "rf_j5_echo_risk_acknowledged": "MEDIUM",
  "auto_self_rebut_count": 3,
  "auto_self_rebut_agents": ["alpha", "risk", "optimizer"],
  "non_rebut_evidence_sources": [
    "Forge HARD_HURDLE_FAIL_FORGE (submit_with_flag)",
    "Codex judge_critic APPROVE_CONDITIONAL (cross-model review)",
    "bt_result.rds realized MDD 59.74% (deterministic)"
  ],
  "future_waiver_path_weakened": true
}
```

---

## Resolution Summary

| ID | Severity | Codex Verdict | Judge Response | Action |
|----|----------|---------------|----------------|--------|
| C1 | HIGH | APPROVE_COND | **ACCEPT-full** | Gate 12-16 → DEFERRED_REJECT_PRIMARY + DSR → NOT_COMPUTED_REJECT_PRIMARY |
| C2 | MEDIUM | APPROVE_COND | **ACCEPT-full** | Add lockbox_date_normalization with 3 canonical windows |
| C3 | MEDIUM | APPROVE_COND | **ACCEPT-full** | Add scenario_rule_audit (discovery_only) |
| C4 | MEDIUM | APPROVE_COND | **PARTIAL** | AX-007 → FAIL_LITERAL_15_NAMES_BELOW_50_PLUS_EXCEPTION |
| C5 | MEDIUM | APPROVE_COND | **ACCEPT-full** | Add echo_chamber_mitigation block |

**Total**: 4 ACCEPT-full + 1 PARTIAL + 0 REBUTTAL

**HIGH severity classification after resolution**:
- C1 (after ACCEPT): explicit non-computation, no longer pseudo-computation
- C2-C5 (after ACCEPT/PARTIAL): documentation cleanups complete

**Per Codex Round Decision Protocol** (`.claude/rules/codex-round.md`):
> Q-Lead escalate triggers: HIGH severity ≥ 5 / AX hard FAIL ≥ 3 / PIT C1 위반

Post-resolution:
- HIGH count: 1 (C1, ACCEPT — non-blocking)
- AX hard FAIL: AX-007 FAIL_LITERAL + AX-008 FAIL_0_OF_2_PASS = 2 (below 3 threshold)
- PIT C1: 0 violations
- **Q-Lead escalate NOT triggered** by Decision Protocol — but the WT itself goes to Q-Lead because integrity = JUDGE_FAILED (this is the correct admission disposition, not an escalation).

---

## Honest Self-Assessment

Codex's stance APPROVE_CONDITIONAL is the correct read. The REJECT verdict is sound (Pre-LB MDD 59.7% > 45% hurdle is binding), but the draft had cosmetic defects:
- "DEFERRED_VERDICT_DECISIVE" wording → should be "DEFERRED_REJECT_PRIMARY"
- 0.998/1.05 DSR estimate → should be explicit non-computation
- Implicit scenario classification → should be explicit scenario_rule_audit
- "MARGINAL" AX-007 → should be FAIL_LITERAL with interpretive note
- Implicit AUTO_SELF_REBUT echo risk → should be explicit echo_chamber_mitigation

None of these defects change the REJECT verdict. All are cleanup for record clarity and to harden any future waiver/reconsideration path against ambiguity.

**Rationalization red flag avoidance** (per Codex base context):
- I am NOT claiming the deferred Harvey gates would have passed (they would need to be RUN to know).
- I am NOT claiming the Lockbox 28-month evidence overrides Pre-LB hurdle (28 months is too short for that).
- I am NOT downplaying AX-008 0/2 PASS as "ambiguous" — it is a strong CONVERGENT REJECT signal.

---

## AX-008 Triangulation Status After Judge Codex Round

- **Forge self**: HARD_HURDLE_FAIL_FORGE (REJECT-aligned)
- **Codex (judge_critic)**: APPROVE_CONDITIONAL (REJECT verdict approved, cleanup needed)
- **Architect**: not invoked
- **2/3 target on REJECT verdict**: MET (Forge REJECT + Codex APPROVE_CONDITIONAL on Judge REJECT verdict)

This is the FIRST TIME in this WT that AX-008 hits 2/3 PASS — but on the REJECT verdict, not on admission. The Judge verdict (REJECT) has 2/3 triangulation support; the admission decision (REJECT) is therefore properly verified.

**Forward direction**: status.json → JUDGE_DONE / JUDGE_FAILED. Q-Lead Telegram notification + governor stage (if any waiver consideration; otherwise WT terminates).

---

## L-code Provisional

**L-CAND-2026-05-27-001**:
> DCA v7 4-family static EW + P3/P4 confidence vector approach achieves alpha-level discovery PASS (Harvey-t 4.41, ICIR 0.398, DSR 0.998) but realized portfolio (M06_MVO_Breadth 15 names) fails MDD<45% hurdle gate on Pre-LB walk-forward window (MDD 59.74% during COVID-2020 crash 2018-02 to 2020-03). Judge Lockbox forward measurement (2024-01-02 to 2026-04-30, 566 days, frozen weights) shows SR 1.92 / MDD -17.2% materially outperforming KOSPI200 (SR 1.65, MDD -20.7%), but Lockbox 28-month window insufficient to override Pre-LB hurdle FAIL.
>
> **Key insight**: Pre-LB vs Lockbox SR ratio 5.54x (1.92 / 0.35), MDD inversion (59.7% → 17.2%). Three hypotheses: (a) Pre-LB COVID outlier dominates IS measurement, (b) post-2023 regime favors DCA defense+quality+value+consensus mix, (c) lockbox lucky window. Recommended follow-up: alpha-research with explicit drawdown control (vol-targeting on confidence vector, multi-sleeve cash buffer) or M11_CVaR optimizer fallback.

(L-code candidate; final L-number assigned at methodology_active.md commit by Q-Lead.)
