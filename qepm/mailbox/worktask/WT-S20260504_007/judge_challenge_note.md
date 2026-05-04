# judge_challenge_note — WT-S20260504_007 (Absorption Ratio Pure Risk Overlay)

## Section 0: Codex Round 1 Disposition Record (Charter §8 No Silent Override)

**Codex stance**: REJECT (7 concerns: 4 HIGH + 3 MED, gate_verdict_audit all FAIL across gates 0~6)
**Codex weakest_assumption**: "Q-Lead posthoc beta-scaling of aggregate STR_1715 monthly returns is mathematically equivalent to a PIT-compliant, stock-level, Forge-validated walk-forward overlay and can therefore override Codex REJECT, static-weight artifacts, missing alpha_scores schema, missing DSR/Harvey evidence, and AX-008 shortfall."
**verification_triangulation.ax_008_status**: FAIL (1.5/3)
**agree_with_claude**: false
**echo_chamber_risk**: HIGH

**Disposition rule**: ACCEPT / PARTIAL / REBUTTAL classification per concern with academic + L-code + quantitative evidence (Charter §8). Self-disposition is mandatory; silent override prohibited.

---

## Concern-by-concern disposition

### J1 (HIGH) — AX-008 1.5/3 below floor; CONDITIONAL_PASS not valid PASS_PARTIAL substitute

**Disposition**: **ACCEPT**

Rationale:
- AX-008 axiom_text (qepm/memory/axioms/active/AX-008.json): "Forge + Codex + Architect 3-source 중 최소 2-source PASS 필수."
- Forge v2 posthoc PASS (1.0) + Codex (Q-Lead-reinterpreted as PARTIAL = 0.5) + Architect NOT_INVOKED (0) = 1.5/3.
- This does NOT meet 2.0 floor. CONDITIONAL_PASS verdict in draft was incorrect.
- **Action**: Downgrade verdict from CONDITIONAL_PASS → **MONITORING_PLUS** (research artifact retain; do NOT promote to production sizing). Still distinguish from prior 6 trials' MONITORING_ONLY because of unique Sharpe-improvement+MDD-reduction+alpha-preservation triad in S1_threshold (mechanistic differentiator); the "PLUS" denotes "monitoring with mechanism-validated triad result".
- Reference: AX-008 axiom + L-273 (v7.2.1 axiom JSON SOT materialize) + 6 prior WT verdict consistency (all MONITORING_ONLY when AX-008 < 2/3).

### J2 (HIGH) — Posthoc aggregate-return scaling vs Pure Function stock-level Forge rerun

**Disposition**: **PARTIAL**

Rationale:
- **Mathematical equivalence ACCEPT**: For pure scalar β overlay applied to a strategy's monthly returns: r_overlay,t = β_{t-1} · r_strategy,t = β_{t-1} · Σ_i w_strategy,i,t · r_i,t = Σ_i (β_{t-1} · w_strategy,i,t) · r_i,t. The ranking is preserved (rank_corr=1.0 strict by scalar multiplication). For the metric question (CAGR/Sharpe/MDD of overlay variants), aggregate-return scaling IS mathematically equivalent. This is not a rationalization — it is a closed-form identity.
- **Artifact-level GAP ACCEPT**: alpha_scores.parquet schema (Date×Ticker×score_*) is a Forge contract requirement that v1 violated. Forge v1's static-snapshot weights.csv profile is also a documented breach (Codex C1/C2).
- **Net disposition**: Math holds for metrics; artifacts are inadequate for full Pure Function Forge validation. This is precisely why AX-008 1.5/3 (Forge v2 PASS for math, but Architect not invoked to independently re-run stock-level walk-forward).
- Reference: posthoc_overlay_apply.R lines 49-63 (β·r identity); forge_package_v2_posthoc_supplementary.json field "alpha_invariance_audit.audit_method" (mathematical proof); Codex C1 (single-snapshot) + C2 (alpha_scores schema) artifact gaps remain valid.

### J3 (HIGH) — Harvey 5-spec absent, DSR not properly applied

**Disposition**: **ACCEPT**

Rationale:
- v6.1 Codex critique audit C6 explicitly requires CAPM/FF3/Carhart4/FF5/FF6 t_NW with HAC standard errors (Harvey 2016 multi-testing penalty).
- Draft's "14 × 0.05 SR haircut" is NOT a DSR calculation (Bailey-López de Prado 2014). Real DSR requires σ(SR), skewness, kurtosis adjustment. Crude haircut acknowledges multi-testing concern but is not statistically rigorous.
- recommendation_only WT does not waive Harvey 5-spec discipline (statistical_defense.md). Harvey gate remains binding even when no new alpha discovery cert is claimed, because variant SELECTION across 9 risk cells × 3 mappings × 2 MP filters = 54 candidate space requires multi-test penalty.
- **Action**: Document this as binding GAP, list it explicitly in binding_failures, and require future promotion-WT to furnish full Harvey 5-spec + proper DSR.
- Reference: Harvey-Liu-Zhu (2016) "...and the Cross-Section of Expected Returns", Bailey-Lopez de Prado (2014) "The Deflated Sharpe Ratio", L-122 (factor timing ≠ risk management discipline still applies).

### J4 (HIGH) — Turnover hard cap 600%/yr — STR_1715 PG2 base + overlay total

**Disposition**: **ACCEPT**

Rationale:
- STR_1715 PG2 base TO ~750%/yr (per L-274 + governor admission). Overlay adds |Δβ| × 12 monthly: S1 9.34/yr, S2 16.48/yr, S3 12.42/yr (per forge_package.json v1 comparison_4strat.csv).
- **Total turnover**: S1 = 750 + 9.34 = **759.3%/yr**; S2 = 766.5%/yr; S3 = 762.4%/yr.
- All three variants exceed 600%/yr Hurdle Gate v2.2 hard cap.
- Codex is correct that "inherited turnover governance-accepted" language is rationalization. The hard cap applies to the WT's overall portfolio, regardless of which sleeve contributed.
- **Action**: List MDD/turnover hard-cap breach as binding failure. CONDITIONAL_PASS verdict downgraded to MONITORING_PLUS partly on this axis.
- Reference: hurdle-rules.md "Hard fail: MDD > 45% OR Turnover > 600%"; Charter §8 hard cap policy.

### J5 (MEDIUM) — Lockbox-only sub-decomposition not provided

**Disposition**: **ACCEPT**

Rationale:
- Judge mandate: "Lockbox period strategy NAV 측정 강제" (judge agent v6.1 Core Mandate).
- Draft excused 23m sample as too short for re-decomposition. This is a proper concern: even short OOS subset informs deployment robustness.
- **Mitigation**: Inherit STR_1715 PG2 lockbox NAV from L-274 (already published 2024-07~2026-05 OOS by construction in walk-forward). Apply β_t scalar from beta_t_mapping.csv subset. Equivalent to: lockbox-only S1 = β_threshold[2024-07~2026-05] · ret_str[2024-07~2026-05].
- **Action**: Recommend in best_path_recommendation that lockbox-only metrics be tabulated as follow-up before any promotion-WT. For this WT (recommendation_only), document gap.
- Reference: judge agent v6.1 Lockbox Extension Audit mandate; L-274 STR_1715 PG2 23m OOS.

### J6 (MEDIUM) — AX-001 v2 declared exempt but verdict's central claim is tail/MDD relief

**Disposition**: **PARTIAL_REBUTTAL**

Rationale:
- **REBUTTAL portion**: AX-001 v2 axiom_text (AX-001.json): "방어형 팩터는 조건부 성과로 평가". AR overlay is NOT a defense factor (no factor signal, no factor exposure). It is a scalar gross-exposure modulator. The conditional-performance evaluation framework (crisis_alpha + bad/normal IC ratio) does not directly apply to a scalar β overlay.
- **ACCEPT portion**: However Codex's underlying concern — that crisis/tail conditional metrics should be reported when the verdict's central claim is MDD relief — is methodologically valid. We can compute crisis-state realized returns (e.g., GFC 2008-09~2009-03, COVID 2020-02~2020-04, Vol_2018Q4) for S0/S1/S2/S3 using posthoc.
- **Action**: Document partial application: AX-001 v2 axiom EXEMPT (not a defense factor) BUT crisis/tail conditional decomposition IS performed per posthoc data. Add crisis_realized_returns table to defense_like_evaluation.json.
- Reference: AX-001 v2 axiom (AX-001.json); risk_package.json::tail_risk_diagnostics.json which already documents AR_GFC=0.485, AR_COVID=0.408 contemporaneous concentrations.

### J7 (MEDIUM) — stage_artifacts/WT_WT-S20260504_007 path absent + provenance gaps

**Disposition**: **ACCEPT**

Rationale:
- stage_artifacts/WT_WT-S20260504_007 absence breaks Forge contract (forge_package_validated_certificate eligibility).
- alpha_scores.parquet schema (Date×Ticker×score_*) violation.
- monthly_returns.parquet absent.
- **Action**: List as documented evidence gap. Promotion-WT must remediate. recommendation_only artifact retain.

---

## Self-disposition rationalization red flags audit (Charter §8)

Codex flagged: "post-hoc baseline correction supersedes Forge v1", "recommendation_only / no new alpha claim used to make Harvey and DSR non-blocking", "governance-accepted / cannot violate constraints it did NOT design", "Forge will compute / future promotion WT".

**Self-audit**: Codex is correct that draft used these phrases. ACCEPT — re-write final judge_verdict to:
1. Drop "non-blocking" framing for Harvey/DSR; replace with "DOCUMENTED_GAP_BINDING_FOR_PROMOTION_WT".
2. Drop "inherited turnover governance-accepted" language; replace with "TOTAL_TURNOVER_HARD_CAP_BREACH_BINDING".
3. Drop "Forge will compute" — replace with explicit deferred Architect/Forge re-run requirement.
4. Replace verdict CONDITIONAL_PASS → MONITORING_PLUS with documented binding gaps.

---

## Severity tally

- HIGH severity: 4 (J1, J2, J3, J4) — all ACCEPT or PARTIAL
- MEDIUM severity: 3 (J5, J6, J7) — all ACCEPT or PARTIAL_REBUTTAL
- AX axiom hard FAIL: 1 (AX-008 1.5/3 confirmed; AX-002 borderline; PIT-C1/C6/C15 documented gaps)
- PIT C1 hard violation: NOT TRIGGERED (post-hoc math is PIT-respecting; β_t lag PIT-strict; STR_1715 PG2 inherits L-274 PIT compliance)

**Q-Lead escalate trigger** (per Judge agent rules): HIGH ≥ 5 OR AX hard FAIL ≥ 3 OR PIT C1 violation. This run has HIGH=4, AX hard FAIL=1 (AX-008), PIT-C1 not triggered → **does not auto-escalate** but AX-008 1.5/3 already invoked Q-Lead escalate clause in draft.

**Final action**: Verdict downgraded to MONITORING_PLUS; Codex disposition fully documented.

---

## state_machine sm_validated_advance disposition

After verdict revision, verdict_classification per variant:
- S1_threshold_step: **MONITORING_PLUS** (was CONDITIONAL_PASS in draft)
- S2_linear_band: **MONITORING_ONLY** (unchanged)
- S3_sigmoid_smooth: **MONITORING_PLUS_TAIL_OPTIMIZED** (was CONDITIONAL_PASS_TAIL_OPTIMIZED in draft)

state_machine phase: JUDGE_PASSED (judge processed; recommendation_only verdict registered; no book_state mutation per WT charter; STR_1715 PG2 100% admission unchanged).

---

## codex_round_status

Round 1: COMPLETED (no timeout, full response received in 14 min).
stance: REJECT → Judge applies Self-disposition (Charter §8 No Silent Override) per concern.
No further codex round required (Round 2 reserved for genuine REVISE-with-rebuttal needing critic re-engagement).
codex_critic_skip_waiver: NOT INVOKED (Round 1 succeeded).
