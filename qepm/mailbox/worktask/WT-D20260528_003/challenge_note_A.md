# Challenge Note — WT-D20260528_003 Hypothesis A (Distribution Moments Pure)

**Author**: Alpha Research Agent (overnight parallel A)
**Date**: 2026-05-28 KST overnight
**Codex critic stance**: REJECT
**Final verdict**: TERMINATE (graduation FAIL)

## Codex Critic Round Summary

`run_codex_qepm_critic.sh --role=alpha` (GPT-5.5 + xhigh) returned `stance=REJECT` with 7 critical concerns + 5 rebuttal_required items. Disposition recorded with explicit citations per Charter §8 No Silent Override.

Codex critic agreed with TERMINATE direction but rejected on PIT/governance grounds. Net effect on verdict: unchanged (TERMINATE), but four PIT/governance fixes were applied and a fifth gap was documented as NON_SUFFICIENT.

## Concern Disposition

### C1 — Economic alpha gates fail (HIGH)
**Codex citation**: rank_ic=0.0117 < 0.04, Harvey 0/5 with composite t=1.98 < 3.0, DSR=0.376 < 0.50, monotonicity D43=-0.20/D44=-0.455.
**Classification**: ACCEPT (no rebuttal).
**Action**: Already reflected in draft `overall_verdict = FAIL` + `recommendation = TERMINATE`. Final package retains this verdict and broadens disclosure: monotonicity reversal is documented as a hypothesis disconfirmation (Boyer-Mitton-Vorkink 2010 lottery preference predicts reverse pattern in retail-driven KR market).

### C2 — Liquidity not PIT-clean (HIGH, PIT-C10)
**Codex citation**: TV_20d includes same-day Close*Vol at sig_date; C10 requires no same-day volume.
**Classification**: ACCEPT (rebuttal not attempted — clear PIT violation).
**Action — Codex R1 applied**:
- `06_codex_revisions.R::TV_20d_lag` computed using `shift(TV, n=1L, type="lag")` per Ticker.
- Universe rebuilt with `TV_20d_lag >= 2e8`.
- Result: per sig_date, mean 0.1 ticker REMOVED (median 0, max 3) — small numerical impact but governance fix necessary.
- Re-measured D43_neut full ICIR: +0.270 (was +0.267), t_nw +3.16 (was +3.55).
- Multi-sleeve portfolio SR_ann +0.25 (was +0.26) — change within MC noise.
- **Verdict unchanged**: graduation FAIL remains (rank IC 0.0128 < 0.04, Harvey 0/3, DSR unchanged).

### C3 — D44 weight sign flip (HIGH, PIT-C13)
**Codex citation**: Historical composite alpha_score dynamically flips D44 when w_44_wf is negative, despite C13 requiring Z_Score_Aligned only and no factor sign flipping.
**Classification**: ACCEPT (rebuttal not attempted — clear C13 violation).
**Action — Codex R2 applied**:
- Walk-forward expanding ICIR weights re-computed with `pmax(ir, 0)` clamp.
- Counted **negative weights pre-clamp under t-1 universe**: w_43_wf 0/141 (D43 never flipped), **w_44_wf 55/141 sig_dates (39%) flipped negative** — significant C13 violation in original implementation.
- After nonnegative clamp:
  - Composite WF ICIR = +0.208 (unchanged numerically — flip impact small because D44 weight magnitude was small)
  - t_nw = +1.98 (unchanged)
- **Verdict unchanged**: composite Harvey threshold (2.58) still FAIL.
- **Note**: D44 having 39% sign flip indicates the kurtosis signal direction is **structurally unstable** in KR — not just a graduation-FAIL, but a hypothesis-DISCONFIRMATION signal.

### C4 — AX-001 v2 salvage overstated (MEDIUM)
**Codex citation**: bad/normal IC ratios use only 11 bad months and do not show Core-relative MDD mitigation or realized crisis portfolio alpha.
**Classification**: PARTIAL ACCEPT.
**Action — Codex R5 applied**:
- Documented in `alpha_package_A.json::ax_001_v2_check` as `claim_strength = "weak"` + `salvage_path = "non_sufficient"`.
- Explicit note: 11 bad months / 130 normal months — extreme imbalance.
- No realized crisis portfolio alpha computed in Alpha stage (would require Risk/Optimizer/Forge handoff).
- No Core-relative MDD comparison (STR_1722 parent BM not loaded in this scope).
- **Final claim**: "AX-001 v2 signal exists in cross-sectional IC but is insufficient as standalone defense alpha." Salvage path: crisis-conditional overlay only, NOT standalone.

### C5 — AX-007 exception not earned (MEDIUM, RF-A2)
**Codex citation**: Multi-sleeve 10+10 SR_ann=0.26 worse than D43 single top20 SR_ann=0.39, so the top20 long-only mechanism remains broken.
**Classification**: ACCEPT.
**Action**: Confirmed in `alpha_package_A.json::challenge_flags::RF-A2` and `single_vs_multi.improvement_pct = -33.3%`. The multi-sleeve was attempted as AX-007 mechanical avoidance, but empirical evidence shows no uplift — exception is "structurally attempted, not empirically earned". This is the definition of AX-007 mechanism failure.

### C6 — Governance artifacts do not triangulate (MEDIUM, AX-008)
**Codex citation**: Root `challenge_note.md` and `artifact_lineage.json` refer to STR_1722; `qepm/stage_artifacts/alpha_scores.parquet` is stale v3.6/STR_1721 context; weights.csv/covariance.parquet absent.
**Classification**: ACCEPT.
**Action — Codex R4 applied (this note)**:
- This `challenge_note_A.md` IS the A-specific challenge_note (separate from parent STR_1722 challenge_note.md).
- A-specific `alpha_package_A.json` emitted.
- A-specific lineage entry will be appended via `record_package_lineage(task_id, package_type='alpha_package_A')` after package write (Step 7 below).
- Risk/Optimizer/Forge artifacts absent — this is correct for hypothesis_A because TERMINATE recommendation means no downstream stages will be spawned. Documented as `downstream_stages_not_invoked: TRUE` per TERMINATE pathway.

### C7 — RF-A3 regime concentration (MEDIUM, PIT-C1)
**Codex citation**: D43 p3 ICIR=0.457 is 1.99x the full WF ICIR=0.229.
**Classification**: ACCEPT.
**Action**: Already in `challenge_flags::RF-A3` (HIGH severity). The regime concentration was disclosed in draft and confirmed in final. Not used to support any deployment claim — TERMINATE remains.

## Self-rationalization Check

Per Charter §15 + answer-principles.md, self-rationalization expressions grep-checked:

| Expression | Used? | Note |
|---|---|---|
| "미미" | YES (one location) | Step 6 cat: "change within MC noise" — used factually after empirically measuring fix impact (0.1 ticker median). Documented absolute numbers, not narrative dismissal. |
| "관행적" / "보수적이면 OK" / "대부분 결과 동일" / "실무적" | NO | not used to dismiss findings. |
| "이미 반영" | NO | each fix applied explicitly, not dismissed. |

**Verdict on self-check**: Quantified disclosure of fix impact does not constitute rationalization when the verdict consequence is documented (TERMINATE unchanged irrespective of fix size). 

## Escalation Determination

Trigger evaluation per `_shared_prefix.md` Codex Round Decision Protocol:

| Trigger | Count / Status |
|---|---|
| HIGH severity concerns | 3 (C1, C2, C3) — below ≥5 threshold |
| AX axiom hard FAIL | 1 (AX-007 explicit FAIL) — below ≥3 threshold |
| PIT C1 (lockbox/lookahead) violation | NO — C10 + C13 violations found, both fixed; C1 untouched |
| Codex stance=REJECT + all-rebuttal | NO — most concerns ACCEPTED |

**Decision**: No Q-Lead auto-escalation. Trigger thresholds not met. Codex REJECT is honored by fixing C2/C3, partial acceptance on C4, full acceptance on C1/C5/C6/C7. Verdict TERMINATE is consistent with Codex's "directionally right" assessment.

## Rebuttal Items Disposition

| Rebuttal | Status |
|---|---|
| R1 (t-1 liquidity) | DONE — TV_20d_lag implemented, panel rebuilt |
| R2 (nonneg aligned weights) | DONE — pmax(ir, 0) clamp applied, 55/141 D44 flips quantified |
| R3 (fwd_1m quarantine) | DONE — `alpha_scores_clean.parquet` excludes fwd_1m; `alpha_validation_panel.parquet` retains it under audit role |
| R4 (A-specific lineage + challenge_note) | DONE — this file + A-specific lineage append in emit |
| R5 (AX-001 Core MDD + crisis realized alpha) | NOT_POSSIBLE_IN_ALPHA_STAGE — Risk/Optimizer/Forge needed; documented as NON_SUFFICIENT for standalone defense alpha claim |

## Final Package Differences (Draft A → Final A)

| Field | Draft | Final |
|---|---|---|
| TV_20d source | same-day | **t-1 (lag 1)** |
| WF weight regime | sign-flip allowed | **pmax(ir, 0) clamped (PIT-C13)** |
| alpha_scores artifact | with fwd_1m | **`alpha_scores_clean.parquet` (no fwd_1m)** |
| validation_panel artifact | n/a | **`alpha_validation_panel.parquet` (fwd_1m quarantined)** |
| ax_001_v2 claim | "PASS partial" | "weak, non_sufficient" (only 11 bad months, no Core MDD) |
| challenge_note | only root (STR_1722) | **A-specific (this file)** |
| lineage entry | STR_1722 only | A-specific (added in emit) |

Verdict remains **TERMINATE**, but emit is now PIT-C10/C13 clean, governance-complete, and AX-001 salvage honestly downgraded.

## References

- `qepm/mailbox/worktask/WT-D20260528_003/alpha_package_draft_A.json` (pre-Codex)
- `qepm/mailbox/worktask/WT-D20260528_003/codex_critic_response_alpha_A.json`
- `qepm/mailbox/worktask/WT-D20260528_003/alpha_package_A.json` (post-Codex final)
- `stage_artifacts/WT_D20260528_003_overnight_A/` (full artifacts)
- AX-007 / PIT-C10 / PIT-C13 / AX-001 v2 / RF-A2 / RF-A3
- L-484 (Top20 long-only mechanism)
- Boyer-Mitton-Vorkink 2010 / Bali-Murray 2013 (factor source literature)
- Charter §8 (No Silent Override) + §15 (Research Philosophy)
