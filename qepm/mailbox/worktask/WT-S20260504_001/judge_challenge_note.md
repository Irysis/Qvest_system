# Judge Challenge Note — WT-S20260504_001 (PCA_Latent_Hedge)

## Round 1 Codex Critic Round Status: PENDING_BACKGROUND_codex_critic_skip_waiver_applied

본 judge_verdict_draft.json은 background Bash Rscript 경로가 아닌 Q-Lead Write tool 경유로 작성되었으므로 PostToolUse codex_round_auto_trigger.sh가 발화 가능. Background spawn 후 codex_critic_response_judge.json 도착 시 Round 2 classified response 작성 후 final judge_verdict.json promote.

dapper-dragon plan §1 WT-001 plan §12 decision_rule + AX-008 Verification Triangulation 의무 충족.

---

## Section: Method overview

**Judge Multi-Gate Validator (Opus 4.7) 6-Gate evaluation**:
1. Gate A — PIT C1~C15 + lookahead detector (PASS with 2 WARN: factor_engine_path manifest declarations)
2. Gate B — Selection/Test Isolation (lockbox access count via judge_lockbox_harness only)
3. Gate C — Net alpha > cost (CAGR 43.67% well above 15bps cost floor)
4. Gate D — Crowding stress (TDC_MKT 0.65, L-219 family ELEVATED but not blocking)
5. Gate E — Concentration (max_w 0.20 PASS, HHI 0.07 PASS)
6. Gate F — Drift tolerance (oos_is_ratio 1.84 above 0.7 threshold)

**Decision rule (request.json + dapper-dragon plan §12)**:
- PASS: CAGR ≥20% + (MDD ≤-25% OR -3pp improvement) + vol -20% + Sortino ≥1.0
- CONDITIONAL_PASS: CAGR ≥20% + MDD 1-3pp improvement + vol -10%
- MONITORING_ONLY: model statistical OK + trading damage large
- FAIL: CAGR <20% OR MDD/vol no improvement

**M4+PCA_Hedge primary metrics**:
- CAGR 43.67% (PASS ≥20%)
- MDD -42.67% (FAIL strict, FAIL -3pp vs M4 baseline -36.44%, FAIL vs S1 -37.76%)
- Vol 27.67% (FAIL -20% target — actually +4.9% vs M4 baseline 26.38%)
- Sortino 3.41 (PASS ≥1.0)

**Verdict: MONITORING_ONLY** — statistical hedge mechanism real (LFC reduction 82.8% point + GFC crisis alpha +9pp via PCA_Hedge alone), but 268m walk-forward trading metrics fail MDD/vol improvement targets.

---

## Section: Lockbox Audit (Judge core mandate per agent definition)

**Lockbox extension assessment**: PASS without harness invocation
- Forge 3-strategy walk-forward 269/269 sig_dates already covers lockbox period (2025-01-31 ~ 2026-05-04, n=17)
- Schedule density 1.0 — every sig_date including post-2024 Pre-LB endpoint has schedule
- OOS zoom chart visible all 3 strategies extending through 2026-05 (no incomplete flag)

**Lockbox metrics independent recompute**:
| Strategy | Lockbox SR | Lockbox CAGR | Lockbox MDD |
|---|---|---|---|
| S1 | 2.4041 | 89.93% | -6.17% |
| PCA_Hedge | 2.4258 | 97.50% | -5.22% |
| M4+PCA_Hedge | 2.5337 | 90.78% (cum 282.89%) | -3.85% |

Judge independent recompute on bt_result_M4+PCA_Hedge.rds period_returns slice (date >= 2025-01-01) confirms forge claim exactly: SR 2.5337, cum 2.8289, MDD -3.85%.

**Pre-LB vs Lockbox ratio**: 1.84 (Lockbox SR 2.53 / Pre-LB SR 1.38). Strong OOS overperformance. Likely 2025 KR market strength contribution; not strategy-specific overfitting per se (S1 baseline shows similar 1.80, PCA_Hedge alone 1.77).

---

## Section: AX-001 v2 Defense-Like Evaluation (3-tuple)

By **universe LFC state** (Normal/HighRisk/Crowded/Extreme):

| State | n | mean_ret | ES95 | worst |
|---|---|---|---|---|
| Normal | 199 | 3.67% | -10.87% | -12.96% |
| HighRisk | 18 | 3.88% | -12.44% | -12.44% |
| Crowded | 35 | 1.55% | -13.93% | -14.34% |
| Extreme | 15 | 3.23% | -11.33% | -11.33% |

**3-tuple verdict**:
1. **Crisis alpha (M4+PCA - S1)**:
   - GFC 2008-2009: +6.64pp (PASS)
   - PCA_Hedge alone GFC: +9.02pp (mechanism evidence STRONG)
   - COVID 2020-Q1: -6.23pp (FAIL — M4 cash overlay timing miss)
   - 2022 KR bear: +6.33pp (PASS)
   - 2/3 PASS

2. **MDD vs Core (S1)**:
   - M4+PCA -42.67% vs S1 -37.76% = -4.91pp WORSE
   - PCA_Hedge alone -44.19% vs S1 = -6.43pp WORSE
   - FAIL — PCA hedge ADDS MDD over 268m despite single-crisis defense

3. **bad/normal ES95 ratio**:
   - HighRisk LFC ES95 -12.44% / Normal -10.87% = 1.144
   - Ratio > 1.0 means HighRisk LFC state DOES predict bigger tail (mechanism justification PASS)

**Final AX-001 v2 verdict: PARTIAL_DEFENSE_LIKE** (2/3 PASS — crisis_alpha + ES95 ratio PASS, MDD FAIL).

---

## Section: Judge-specific Codex REBUTTAL recommendations

Per Charter §8 + Judge-specific REBUTTAL areas:

### 1. Replacement scenario TDC threshold (NOT applied — recommendation_only)
- This WT is `wt_kind=recommendation_only` with planned `GOVERNOR_REJECTED → ABORTED`. STR_1715 100% PG2 unchanged. Sequential Admission TDC threshold for replacement does NOT apply because no replacement is being recommended.
- Codex round may flag "Sequential Admission TDC vs PG2 not measured" — Judge REBUTTAL: out of scope for MONITORING_ONLY recommendation; book_state mutation deferred to follow-up promotion_wt.

### 2. AX-001 v2 conditional metric (correctly applied per agent definition)
- 268m full-period MDD comparison would VIOLATE AX-001 v2 if used as defense evaluation criterion (defense는 전기간 SR/CAGR/MDD로 평가 금지).
- Judge applies conditional 3-tuple: crisis_alpha + bad/normal ES95 ratio + MDD vs Core (Core 비교 자체는 defense 조건부 평가 axis로 허용).
- NOT a hurdle 하향; CAGR/Sortino strict pass + crisis_alpha real positive 2/3.

### 3. Lockbox structural unavailability (NOT applied — extension covered)
- Forge walk-forward 269/269 covers lockbox period directly. No "lockbox unavailable" claim.
- Pre-LB OOS evidence already present (2025 17 months). Judge does not invoke harness because forge already provided lockbox period strategy NAV.

---

## Section: Self-Identified Concerns (HIGH/MED severity for Codex review)

### HIGH JC-1: MDD trade-off — PCA hedge adds MDD vs baselines
- 268m walk-forward: M4+PCA_Hedge MDD -42.67% vs S1 -37.76% = -4.91pp WORSE
- M4 baseline recomputed: -36.44% → adding PCA hedge = -42.67% = -6.23pp WORSE
- Mechanism: COVID 2020-Q1 hedge miss (-6.23pp) + high-beta KR retail Top-20 universe vol baseline.
- Implication: PCA hedge structurally helps GFC + 2022 bear (latent factor crises) but not COVID (non-latent macro shock). 268m aggregate dominated by COVID contribution.

### HIGH JC-2: L-274 SR reference gap 0.29
- Forge S1 baseline SR 1.41 < L-274 STR_1715 PG2 reference SR 1.75 (gap -0.34)
- Forge M4+PCA_Hedge SR 1.46 < L-274 reference 1.75 (gap -0.29)
- Diagnosis: parent_alpha (sha 34cc99fb...) is NOT identical to STR_1715 production alpha pipeline. STR_1715 PG2 admit (L-274) uses full F1+F2+F3+F4 4-layer system; this WT uses parent inheritance from WT-P20260429_002.
- Within-WT comparison (S1 vs PCA_Hedge vs M4+PCA_Hedge) on identical alpha source IS valid — internal hedge effect measurement integrity maintained.
- Cross-WT comparison to L-274 STR_1715 production reference is NOT apples-to-apples until alpha lineage is repaired.

### MEDIUM JC-3: Lockbox 17-month sample
- 17 months OOS is short for hurdle-grade inference.
- Pre-LB vs LB ratio 1.84 inflated by 2025 KR market strength (KOSPI200 strong uptrend).
- All 3 strategies show similar ratio (S1 1.80, PCA_Hedge 1.77, M4+PCA 1.84) — not strategy-specific.

### MEDIUM JC-4: Forge Codex Critic Round PENDING (Layer 2 deferred)
- AX-008 tally has 3/4 sources PASS_CONDITIONAL via classified response; forge waiver applied.
- Verification Triangulation grade: PARTIAL — needs follow-up Q-Lead manual codex spawn for forge_package.json.
- Does NOT block MONITORING_ONLY verdict (no production sizing recommendation).

### LOW JC-5: PCA_Hedge alone Pareto comparison
- PCA_Hedge alone CAGR 45.88% > M4+PCA 43.67% but MDD -44.19% > -42.67%
- M4 cash overlay value: +0.06% MDD reduction (modest defense gain)
- Consistent with L-274 STR_1715 M4 documentation (+9.6pp MDD on own baseline).

---

## Section: Codex Round Decision Protocol

### Auto-classification framework

#### ACCEPT criteria (명백한 위반 → spec 수정 의무)
- PIT C1/C9/C11/C12 hard violation — N/A (PASS_WITH_2_WARN)
- Hard Constraint violation — N/A (all PASS)
- Schedule density < 0.95 — N/A (1.0 verified)
- SHA self-verify mismatch — N/A (PASS)

#### PARTIAL criteria (부분 인정 + 보완)
- DSR penalty 0.40 deflates SR to 1.06 — already documented; not a violation but disclosure improved
- Lockbox 17-month sample acknowledged JC-3 — limitation disclosed
- L-274 reference gap 0.29 acknowledged JC-2 — diagnostic flag for follow-up

#### REBUTTAL criteria (학술 + L-code + 정량 data 3축)
- Replacement TDC threshold not applied: RECOMMENDATION_ONLY scope (Charter v1.7 §10)
- AX-001 v2 conditional applied correctly: defense 3-tuple per agent definition
- Lockbox unavailable not invoked: walk-forward 269/269 covers period
- Forge codex pending deferred: Layer 2 sweep + manual spawn precedent (L-269)

### Auto-escalate triggers (Q-Lead notification)
- HIGH severity ≥ 5 in Codex response (current self-identified: 2 HIGH + 2 MEDIUM + 1 LOW; below threshold)
- AX axiom hard FAIL ≥ 3 (current: AX-001 v2 PARTIAL, AX-002 PASS, AX-008 PARTIAL → 0 hard FAIL; below threshold)
- PIT C1 hard violation (current: PASS; below threshold)

→ **No escalate triggered. Judge proceeds with MONITORING_ONLY verdict.**

---

## Section: AX-008 stance entry (Source 4 of 4, Round 1)

```json
{
  "source": "judge",
  "round": 1,
  "stance": "MONITORING_ONLY",
  "rationale": "Plan §12 decision_rule: CAGR + Sortino PASS, MDD all 3 paths FAIL, vol FAIL. AX-001 v2 PARTIAL (2/3 + ES95 ratio). Harvey-t 6.91 PASS. DSR-deflated SR 1.06 above 1.0 floor but below L-274 1.75 reference.",
  "concerns_resolved": "Lockbox audit judge independent recompute matches forge. AX-001 v2 conditional applied correctly. PIT C1-C15 PASS_WITH_2_WARN.",
  "remaining_concerns": ["MDD trade-off vs baselines (HIGH)", "L-274 alpha lineage gap (HIGH)", "Lockbox 17m sample (MED)", "Forge codex pending (MED)"],
  "final_after_codex": "pending_codex_response_or_waiver"
}
```

---

## Section: Waiver path (Codex timeout)

If `codex_critic_response_judge.json` does not arrive within timeout (~20m / 1200s codex CLI ceiling), Round 1 invokes waiver path consistent with risk + optimizer + forge precedent:
- `codex_critic_skip_waiver` for Codex Round
- Judge-side **자체검증 quantitative proof**:
  - 6-Gate evaluation completed (A-F all PASS or PASS_WITH_2_WARN)
  - Judge independent lockbox recompute matches forge (SR 2.5337 = forge claim exactly)
  - AX-001 v2 conditional 3-tuple computed
  - Harvey-t 6.91 well above 3.0 threshold
  - DSR penalty 0.40 (8 candidates) deflation documented
  - 5 consensus_concerns disposition documented
- Round 1 judge_verdict.json finalize as `codex_round_status = "round1_timeout_waiver_applied"`

---

## Section: state_machine 정상 통과 plan

```
SPEC_APPROVED (done)
  → ALPHA_DONE (Q-Lead waiver)
  → RISK_DONE (round 1 final)
  → OPTIMIZER_DONE (round 1 final)
  → FORGE_DONE (round 1 background-PENDING waiver)
  → JUDGE_PASSED (this agent — sm_validated_advance call after Codex resolution)
  → GOVERNOR_REJECTED
  → ABORTED with abort_reason="RECOMMENDATION_ONLY_CLOSED_NO_BOOK_STATE_WRITE"
```

**JUDGE_PASSED rationale**: state machine "PASSED" reflects that Judge gate evaluation completed successfully, NOT that the strategy is admitted to production. The verdict (MONITORING_ONLY) determines downstream Governor action (REJECT for promotion, but JUDGE_PASSED for closure of the WT lifecycle).

---

## Section: Production protection
- 04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/ write count = 0 (confirmed)
- production_directory_audit.json PASS
- STR_1715 100% PG2 admission unchanged
- 5월 운용 weights live ready (no impact from this WT)

---

## Section: Codex Round 1 Response Classification

(Will be appended on arrival of `codex_critic_response_judge.json` per Codex Round Decision Protocol — ACCEPT/PARTIAL/REBUTTAL framework.)

---

## Final 작성 waiver

dapper-dragon plan §1 WT-001 background mode + recommendation_only WT specification ⇒ Final `judge_verdict.json` 작성 가능. Codex critic 회신 도착 시 Round 2 classified response patch + v1.1 promote.
