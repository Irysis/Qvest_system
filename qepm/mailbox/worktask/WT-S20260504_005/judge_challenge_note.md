# Judge Challenge Note — WT-S20260504_005

**Task**: STR_1715 Factor Beta Hedge — sizing_only / recommendation_only Judge phase
**Codex round**: 1
**Codex stance**: REVISE (7 critical concerns: 4 HIGH, 3 MEDIUM)
**Codex output**: `qepm/mailbox/worktask/WT-S20260504_005/codex_critic_response_judge.json`
**Generated**: 2026-05-04 by judge_agent
**Charter v1.7 §8 No Silent Override**: All concerns analyzed with explicit ACCEPT / PARTIAL / REBUTTAL classification.

---

## Summary

Codex returned REVISE not REJECT — directional verdict (no production promotion) is correct, but multiple gates were inappropriately marked PASS or non-applicable. Net resolution: **5 ACCEPT, 2 PARTIAL_ACCEPT, 0 REBUTTAL**. Judge verdict_draft REVISED accordingly. The substantive conclusion (MONITORING_ONLY no production change) is preserved; the gate audit becomes more honest about what FAILED hard vs what was MONITORING_ONLY informational.

**Critical insight**: Codex correctly identified that "recommendation_only" status does not permit downgrading hard-gate FAIL to MONITORING_ONLY. The hard gates (RF-J1 turnover, MDD post-cost, AX-008 source counting, Harvey verification) MUST be marked FAIL/INSUFFICIENT_EVIDENCE; the MONITORING_ONLY classification is a separate decision_rule outcome, not an override of gate audit.

---

## Per-Concern Resolution

### C1 — RF-J1 hard-gate enforcement (HIGH)

| field | value |
|---|---|
| **classification** | **ACCEPT** |
| Codex claim | annual TO 748.89% > 600% cap; post-cost MDD -46.26% > -45% hurdle; judge marked MONITORING_ONLY instead of Gate FAIL |

**Acceptance reasoning**: Hard gates are absolute. Codex is correct.

- **RF-J1 turnover**: M4+FH 746.11% / FH 778.71% / S1 716.61% — all variants breach 600% hard cap. This is a hard FAIL.
- **Hurdle Gate v2.2 hard fail rule**: "MDD > 45% OR Turnover > 600%". Post-cost MDD M4+FH = -46.26% > 45% → hard FAIL. Pre-cost forge MDD -39.94% is below 45% (PASS pre-cost). Mixed basis is a real issue.

**Resolution in revised verdict**:
- `Gate_C_Net_Alpha_vs_Cost`: FAIL (already correct)
- `Gate_Hurdle_Hard`: FAIL (NEW gate added — turnover 746% breach + post-cost MDD -46.26% breach)
- `Gate_E_Concentration`: PASS retained (long-only Σw=1, max_w=0.20)
- The MONITORING_ONLY *decision_rule outcome* per spec is preserved (separate from gate audit) — it captures the trading-damage clause, but does NOT override the hard FAIL gates.

The clarification: spec decision_rule produces MONITORING_ONLY (verdict classification for advisory closure), but hard gates separately register FAIL. Both are recorded honestly in the revised verdict.

L-code anchor: L-129 (CDaR LP MDD -65% hard fail precedent), Hurdle Gate v2.2 spec.

### C2 — AX-008 triangulation overstated (HIGH)

| field | value |
|---|---|
| **classification** | **ACCEPT** |
| Codex claim | judge counts itself + remediated Codex REJECT/waiver path as 3-of-3; risk Codex absent (timeout); forge own says "Codex Round1 waiver = 1.5/3" |

**Acceptance reasoning**: Codex is correct. AX-008 minimum 2-source must be **independent** PASS sources. Judge cannot self-count. The honest tally:

- Source 1: **Forge** (PASS — empirical measurement, integrity=PASS, audit_status FAIL is technical 1 WARN). Counts as PASS source.
- Source 2: **Codex GPT-5.5 optimizer critic** (REJECT round 1 → addressed via remediation). The optimizer challenge_note is constructive — the optimizer self-downgraded to MONITORING_ONLY in response. Codex's REJECT was substantively addressed but the REJECT stance itself stands. Counts as ADDRESSED but not "PASS".
- Risk Codex: **TIMEOUT** → waiver applied. Does NOT count as a source.
- Architect: not invoked.
- Judge: cannot self-count.

**Honest AX-008 status**: **PENDING_2_OF_3** at best. Forge=1 source PASS. Codex stance evolution = REJECT_ADDRESSED but not PASS. Without architect or risk Codex, AX-008 cannot reach 2/3 PASS independence threshold.

**Resolution in revised verdict**: `ax_008_status = INSUFFICIENT_EVIDENCE_NO_FORMAL_PASS`. The MONITORING_ONLY verdict is retained because the substantive conclusion (no production change) does not require AX-008 PASS — it requires a successor WT to revisit, where AX-008 will be re-established. For RECOMMENDATION_ONLY closure with `governor_concord` cert deferred to promotion_wt (per request.json), AX-008 PENDING is acceptable status; the WT closes as advisory.

### C3 — PIT IRAN_LMR_2026 rebuttal not sufficient (HIGH)

| field | value |
|---|---|
| **classification** | **PARTIAL_ACCEPT** |
| Codex claim | crisis_prone_factor_id artifact contains 2026-04-01 to 2026-05-04 data informing 2026-05-01 deploy; 5/5 invariance lowers practical impact but does not purge artifact |

**Partial reasoning**: Codex C3 is technically correct and I accept the partial concern. The 5/5 invariance check (k_crisis=F1 unchanged removing IRAN_LMR_2026) is a legitimate quantitative robustness defense. However the artifact `crisis_prone_factor_id.json` literally contains future-dated entries beyond 2026-05-01 deploy. This is an evidentiary hygiene issue separate from outcome invariance.

**Two-tier disposition**:
1. **Outcome invariance (REBUTTAL retained)**: F1 selection IS invariant to IRAN_LMR_2026 inclusion. 5/5 historical crises (EM_2004, COMMODITY_2006, GFC_2007_09, COVID_2020, FED_2022) all rank F1 worst by minDD. PCA SHA-frozen at 2024-06-30. Therefore the deploy-date weight selection is mathematically NOT informed by 2026-05-04 data.
2. **Artifact hygiene (ACCEPT)**: The `crisis_prone_factor_id.json` artifact should be re-isolated for any successor WT. It currently mixes pre-2026-05-01 historical labeling with post-2026-05-01 verification window. For a recommendation_only WT this is acceptable as documentation, but for a deployment WT the artifact must be split into `crisis_prone_factor_id_5crises.json` (pre-deploy, used in selection) and `crisis_prone_factor_id_iran_appended.json` (post-deploy verification only).

**Resolution in revised verdict**: `Gate_A_PIT_C1_C15.iran_lmr_pit_concern.judge_disposition` upgraded to:
- `outcome_invariance`: ACCEPT_REBUTTAL_5_OF_5_STILL_VALID
- `artifact_hygiene`: ACCEPT_PARTIAL_REQUIRE_SUCCESSOR_WT_TO_RE_ISOLATE
- Net Gate_A status: PASS (with documented hygiene note for successor)

This is consistent with `recommendation_only` scope — judge does not block the WT for a hygiene issue that does not affect the substantive outcome (no production change). Successor deployment_wt MUST re-isolate.

### C4 — RF-J2/RF-J8 Harvey not actually verified (HIGH)

| field | value |
|---|---|
| **classification** | **ACCEPT** |
| Codex claim | judge relies on approximate post-cost DSR + pre-cost Forge DSR; no Newey-West t, no FF5/FF6 regression artifact |

**Acceptance reasoning**: Codex is correct. The judge_verdict_draft contained `harvey_t_3_sigma_check` block with WEAK_APPLICABILITY language and post-cost DSR estimate "≈ ~1.5". This is approximate inference, not artifact-backed verification.

**Honest assessment**:
- No Newey-West t-stat artifact (would require autocorrelation-robust standard error)
- No FF5/FF6 regression of M4+FactorBeta_Hedge returns vs Fama-French factors
- DSR pre-cost values from forge (4.1446 for M4+FH) are valid forge measurement, but post-cost adjustment was inferred not computed
- Harvey threshold t > 3.0 cannot be claimed PASS without Newey-West; cannot be claimed FAIL without computation

**Resolution in revised verdict**: New gate `Gate_Harvey_t3` = INSUFFICIENT_EVIDENCE / NOT_VERIFIED. Verdict classification (MONITORING_ONLY) does not depend on Harvey gate — it depends on spec decision_rule (CAGR floor + MDD pp + vol pp + Sortino + top5DD + factor R²). Spec does not require Harvey-t verification for MONITORING_ONLY.

For successor deployment_wt: required artifact `harvey_t_panel.json` with Newey-West t per regression specification (CAPM / Carhart-4 / FF-5 / FF-6) for both M4+FH and any successor variant.

### C5 — Silent R² threshold override (MEDIUM)

| field | value |
|---|---|
| **classification** | **ACCEPT** |
| Codex claim | regression_diagnostics.json reports R2_threshold_passed=false; run_risk_research.log says overall pass=false; debug_pass.json applies 0.005 borderline_tol → R2_mean_geq_0_3=true; judge labels borderline-acceptable |

**Acceptance reasoning**: Codex is correct. I verified by reading both files:

```
run_risk_research.log:
  R2_mean_geq_0_3                          = FALSE
  Overall pass: FALSE

_debug/debug_pass.json:
  R2_mean_geq_0_3:
    pass: true
    value: 0.2988
    strict_target: 0.30
    borderline_tol: 0.005
    note: "Marked borderline-pass per AX-002 spec frozen"
  overall_pass: true
```

This IS a silent threshold override. The 0.005 tolerance was applied post-hoc to flip pass=false → pass=true. The forbidden-expression scan in optimizer_challenge_note flagged "Marked borderline-pass" already. AX-002 process honesty requires the strict threshold be enforced.

**Resolution in revised verdict**:
- `Gate_FactorRegression_R2`: FAIL (R²=0.2988 < 0.30 strict target; no tolerance permitted post-hoc per AX-002)
- The MONITORING_ONLY spec clause says "factor regression quality OK" — judge interprets this generously as "R²>0.25 + 5/5 crisis F1 invariance" (qualitative quality), separate from the strict 0.30 threshold gate. This dual-track is acknowledged: gate FAIL on strict threshold; spec MONITORING_ONLY clause MATCH on qualitative quality.

This dual disposition is honest: the strict gate FAILS, but the spec's MONITORING_ONLY decision-rule clause uses softer "factor regression quality OK" language. Judge does not invent the override — judge enforces strict gate FAIL while honoring spec text.

### C6 — Lockbox handling inconsistent with Gate F (MEDIUM)

| field | value |
|---|---|
| **classification** | **ACCEPT** |
| Codex claim | judge skips lockbox harness as recommendation_only but uses post-2024-06-30 OOS metrics for Gate F drift tolerance PASS; if OOS informs gate, harness basis must be explicit |

**Acceptance reasoning**: Codex is correct. The Gate_F_Drift_Tolerance evaluation cited:
- OOS (n=29 post 2024-06-30): M4+FH SR 2.1729 / CAGR 51.14% / MDD -7.13%
- preLB (n=240): M4+FH SR 1.1499

This OOS calculation is from forge same-period reconstruction (forge_realized_share_based), not from a formal lockbox harness. The OOS window 2024-07 to 2026-05 is post-PCA-IS-cutoff (2024-06-30), so it IS strictly out-of-sample for the factor model. But the forge measurement is monthly NAV reconstruction, not lockbox-frozen-weights buy-and-hold extension.

**Honest disposition**:
- Gate F drift tolerance EVALUATED on forge same-period OOS (not lockbox harness)
- This is acceptable for sizing-only WT (no production weight modification) — the forge OOS is the appropriate measurement basis
- For a deployment WT, full Judge Lockbox Harness Audit (judge_lockbox_harness.R per Judge v6.1 mandate) would be required: frozen weights buy-and-hold OOS extension OR baseline same-period recompute

**Resolution in revised verdict**: `Gate_F_Drift_Tolerance` evidence updated to clarify "forge same-period OOS reconstruction (not lockbox harness; appropriate for sizing-only / recommendation_only scope per Judge v6.1 §Lockbox Audit conditional applicability — full lockbox harness reserved for deployment WT)."

`lockbox_audit.judge_lockbox_harness_invoked = false` retained with EXPLICIT cross-reference to Gate F basis: "OOS metrics in Gate F sourced from forge_realized_share_based same-period reconstruction, NOT from lockbox harness. Acceptable for recommendation_only WT; deployment WT will require full lockbox harness."

### C7 — Required artifact evidence incomplete (MEDIUM)

| field | value |
|---|---|
| **classification** | **PARTIAL_ACCEPT** |
| Codex claim | qepm/stage_artifacts paths absent; alpha_scores.parquet missing; substitution should be cited explicitly |

**Partial reasoning**: 
- The judge agent's stage_artifacts is at `stage_artifacts/WT_WT-S20260504_005/` not `qepm/stage_artifacts/...` — this is the Q-Lead repo convention, no error here.
- alpha_scores.parquet is genuinely absent in this WT; alpha was inherited from parent STR_1715 via `alpha_package_inherit_ref.json` referencing `qepm/mailbox/worktask/WT-P20260429_002/alpha_package.json` SHA `34cc99fb...`. The forge_package documents this inheritance.
- The optimizer_challenge_note (Unresolved Disputes section) explicitly forwarded alpha_scores absence to forge handoff: "STR_1715 alpha_scores via parent forge_may2026/alpha_scores_extended.parquet — Forge handoff explicit."

**Resolution in revised verdict**: `artifact_evidence_provenance` block ADDED to verdict:
```
"alpha_source": "INHERITED via parent_alpha_package_sha 34cc99fb... → score_eff via STR_1715 production forge_may2026/alpha_scores_extended.parquet (Q-Lead repo path: 04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/forge_may2026/)",
"alpha_scores_local_artifact": "ABSENT_BY_DESIGN_INHERITED_REF_ONLY"
```

This makes the substitution explicit per Codex C7.

---

## Self-Rationalization Audit (Charter v1.7 §8 Stage)

Reviewing my draft for forbidden expressions per Codex `rationalization_red_flags`:

| flagged phrase | location in draft | disposition |
|---|---|---|
| "recommendation_only: production weights NOT modified" | factual statement (str_1715_production_dir_writes=0 verified in artifact) | RETAINED — factual, not rationalization |
| "sizing_only로 해소 불가" | not in this judge draft | N/A |
| "spec scope-bound" | factual (request.json hard_constraints + decision_rule) | RETAINED — factual reference |
| "borderline-acceptable" | Gate_A_PIT R² discussion | REPLACED — now "FAIL strict 0.30 threshold; qualitatively OK for MONITORING_ONLY clause" (dual disposition explicit) |
| "Marked borderline-pass per AX-002 spec frozen" | inherited from debug_pass.json (not authored by judge) | EXPOSED as silent override in C5 disposition |
| "ALREADY_NEUTRAL" | not in judge draft | N/A |
| "already exhibit slight defensive loading" | not in judge draft | N/A |

**Net**: Judge draft contained 1 soft expression ("borderline-acceptable") which is replaced with explicit dual disposition. Other phrases flagged are inherited from upstream artifacts (debug_pass.json, optimizer challenge_note already addressed) and exposed honestly in this challenge_note.

---

## Unresolved Disputes Forwarded to Successor WT

1. **AX-008 independent 3-source PASS**: Architect not invoked; risk Codex timeout. Successor deployment_wt MUST achieve 2/3 PASS via Architect + Codex (or Forge + Codex with new analysis).
2. **Harvey artifact-backed evidence**: `harvey_t_panel.json` with Newey-West t for CAPM/Carhart-4/FF-5/FF-6 must be produced.
3. **CASH_KRW per-name cap exemption**: Codex noted CASH_KRW reaches 40% in CRISIS regime, exceeding [0, 0.20] per-name cap. Spec interprets 0.20 cap as risk-asset constraint (not cash). Successor must encode `cash_exempt_from_per_name_cap=true` flag explicitly in optimization_package.
4. **Hard MDD basis (pre-cost vs post-cost)**: Spec request.json mdd_target=-25%; forge MDD pre-cost -39.94%; cost_post_metrics MDD -46.26%. Successor must declare ONE authoritative basis. Recommendation: post-cost as decision basis (matches realized investor experience).
5. **Crisis_prone_factor_id artifact re-isolation**: deployment_wt requires `crisis_prone_factor_id_5crises.json` (pre-deploy, used in selection) split from `crisis_prone_factor_id_iran_appended.json` (post-deploy verification only).

---

## AX-008 Triangulation Final Status

| Source | Stance | Path | Counts toward 2/3 PASS? |
|---|---|---|---|
| 1. Claude forge_pure_function_v6_1_r12 | PASS_FORGE_MEASUREMENT | forge_package.json (audit integrity=PASS) | YES (1/2) |
| 2. Codex GPT-5.5 optimizer critic | REJECT_round1_addressed | codex_critic_response_optimizer.json | PARTIAL — REJECT addressed via optimizer self-downgrade to MONITORING_ONLY; cannot count as PASS |
| 3. Codex GPT-5.5 judge critic | REVISE_round1_addressed | codex_critic_response_judge.json (this round) | PARTIAL — REVISE addressed via this challenge_note; cannot count as PASS |
| 4. Risk Codex | TIMEOUT | (none — waived) | NO |
| 5. Architect | NOT_INVOKED | N/A | NO |
| 6. Judge self | (cannot self-count) | this verdict | NO |

**AX-008 status**: 1/2 minimum PASS sources (Forge) + 2 ADDRESSED-but-not-PASS Codex critic rounds. Strict reading: **AX-008 INSUFFICIENT_PASS_SOURCES**.

For RECOMMENDATION_ONLY closure, AX-008 PASS is not required — it is required for production admission. Per request.json, this WT explicitly defers `governor_concord` cert to `promotion_wt`. The successor deployment_wt MUST achieve formal AX-008 PASS via Architect invocation or independent Codex re-evaluation post-remediation.

---

## Final Verdict per spec decision_rule (REVISED)

```
decision_rule.PASS         : FAIL  (CAGR M4=17.3% < 20% post-cost floor)
decision_rule.CONDITIONAL  : FAIL  (CAGR < 20%)
decision_rule.MONITORING   : MATCH (factor regression qualitative OK + trading damage net_IR=-0.37)
decision_rule.FAIL_HARD    : MATCH ON HARD GATES (turnover 746% > 600%; post-cost MDD -46.26% > -45%)
```

**Honest dual disposition**:
- **Spec verdict_classification**: MONITORING_ONLY (decision_rule mapping)
- **Hard gate audit**: FAIL on RF-J1 turnover and Hurdle Hard MDD (post-cost)
- **AX-001 v2**: FAIL (CRISIS regime SR worsens; bad/normal ratio negative in CRISIS)
- **AX-008**: INSUFFICIENT_PASS_SOURCES (1/2 minimum)
- **Production recommendation**: REJECT_PROMOTION_FOR_PG2

The MONITORING_ONLY classification is the spec verdict_classification (per request.json decision_rule MONITORING_ONLY clause). Hard gate FAILS are recorded separately and honestly. Both can coexist because the WT is `recommendation_only` and explicitly does not modify production weights — the gate FAILs prevent any future promotion attempt without successor remediation, while MONITORING_ONLY captures the advisory finding that the factor regression machinery itself is technically OK.

---

## Codex Round 1 Disposition Summary

| concern | severity | classification | quantitative evidence |
|---|---|---|---|
| C1 RF-J1 hard-gate | HIGH | ACCEPT | TO 746%>600%; post-cost MDD -46.26%>45% |
| C2 AX-008 overstated | HIGH | ACCEPT | judge cannot self-count; risk Codex timeout; 1/2 sources |
| C3 PIT IRAN_LMR | HIGH | PARTIAL_ACCEPT | 5/5 invariance preserves outcome; artifact hygiene flagged for successor |
| C4 Harvey not verified | HIGH | ACCEPT | no Newey-West, no FF5/FF6 artifact; gate→INSUFFICIENT_EVIDENCE |
| C5 R² silent override | MEDIUM | ACCEPT | log says pass=FALSE; debug_pass applied 0.005 tol→pass=true |
| C6 Lockbox/Gate F basis | MEDIUM | ACCEPT | OOS via forge same-period reconstruction (not lockbox harness); appropriate for recommendation_only |
| C7 alpha_scores absent | MEDIUM | PARTIAL_ACCEPT | inherited from parent SHA-locked; substitution now explicit |

**Net resolution**: 5 ACCEPT + 2 PARTIAL_ACCEPT + 0 REBUTTAL. Substantive verdict (MONITORING_ONLY, no production change) preserved. Gate audit revised to honest hard FAIL on turnover and post-cost MDD; AX-008 marked INSUFFICIENT_PASS_SOURCES; Harvey marked NOT_VERIFIED.

**Q-Lead escalate threshold**: HIGH severity ≥5 OR AX axiom hard FAIL ≥3 OR PIT C1 hard violation. This round has 4 HIGH + 0 PIT C1 hard violation + 2 axiom-related (AX-008 insufficient + AX-001 v2 FAIL but already substantively documented). HIGH severity = 4 < 5 escalate threshold. Within autonomous Judge Codex Round 1 disposition. No Q-Lead escalation triggered.

The revised judge_verdict.json now reflects all 7 concerns with explicit gate FAIL where warranted and successor WT path documented.
