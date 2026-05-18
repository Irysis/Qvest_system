# Admission Protocol — Step 2.5

**WT-D20260519_002 Bear Prediction Engine v1.0**

**5-subgate strict + G5 integration test + G6 AX-008 + DPL_KR_v3 binding** 명시.

---

## 1. Decision gates (request.json spec retain + max-history mandate adjust)

| Gate | Spec | Pass criterion | Failure → |
|---|---|---|---|
| **G0_PIT** | Usable_Date ≤ sig_date strict + all macro/yield/ETF t-1 lag | `lookahead_detector.R` PASS + `pit_enforcement.R` PASS for each of 32 features | HARD ABORT |
| **G1_classifier_5_subgate** | 5 sub-gate strict | (1) AUC ≥ 0.60 (2) Brier < 0.20 (3) Recall ≥ 0.60 (4) Precision ≥ 0.40 (5) sub-window 4/5 stability ALL pass | HARD ABORT v5 paradigm-inviable confirmed |
| **G2_economic_significance** | OOS active return prediction skill | Diebold-Mariano test p < 0.05 (bear-month prediction better than random/persistence baseline) | DEFER |
| **G3_feature_stability** | Importance Gini + sub-period overlap | Gini < 0.5 AND top-10 Jaccard overlap ≥ 0.6 across 5 sub-windows | WARN + Codex review |
| **G4_DSR** | Deflated Sharpe Ratio (downstream NAV) | Bailey-LdP Z ≥ 1.5 (if standalone alpha sleeve emit, else N/A for regime sensor) | DEFER |
| **G5_dpl_integration_or_standalone** | (a) DPL_KR_v3 p_bad inject AUC uplift ≥ 0.05 OR (b) standalone regime sensor admit | EITHER admit | DEFER |
| **G6_AX008** | Forge + Codex + Architect ≥ 2/3 PASS | AX-008 quorum | DEFER |

---

## 2. G1 5-subgate detailed pass criteria

### Subgate 1: AUC ≥ 0.60

- Computed per sub-window on test data
- ROC AUC of p_bad_monthly vs bad_month label
- Threshold-independent metric

### Subgate 2: Brier < 0.20

- Computed per sub-window
- Brier(y, p̂) = mean((y - p̂)²)
- Calibration measure

### Subgate 3: Recall ≥ 0.60

- Computed per sub-window at **threshold = 0.5** (default) OR optimal-F1 threshold (pre-declared)
- Recall = TP / (TP + FN) = bad month detection rate
- **v5 fail target: 0.089 → 0.60+ (7× improvement)**

### Subgate 4: Precision ≥ 0.40

- Computed per sub-window at same threshold
- Precision = TP / (TP + FP)
- False alarm control
- **v5 fail target: 0.08~0.15 → 0.40+ (3× improvement)**

### Subgate 5: Sub-window 4/5 stability

- Across 5 sub-windows (W1~W5)
- **At least 4 sub-windows pass ALL of subgate 1~4 simultaneously**
- v5 fail: 0/4 → 4/5 stability target

### Pass condition

```
G1_PASS = (4/5 sub-windows have:
            AUC ≥ 0.60 AND
            Brier < 0.20 AND
            Recall ≥ 0.60 AND
            Precision ≥ 0.40
          )
```

---

## 3. Threshold selection (pre-declared)

**Threshold selection 의무 fixed pre-declared** (post-hoc tuning prohibited):

```
default_threshold = 0.5
optimal_threshold = arg max_τ F1(τ) on validation set
```

Forge cycle reports both. Default for G1 = optimal_threshold computed on val.

---

## 4. Output integration paths (G5 binding)

### Path A: DPL_KR_v3 p_bad injection

```
WT-D20260519_001 DPL_KR_v3 cycle inherits p_bad_monthly_t feature:
  - feature_count: 80 (base) + 1 (p_bad_v1) = 81 features (per-stock or market-level injection)
  - Forge cycle integration test: re-train DPL_KR_v3 with new feature
  - Metric: ΔAUC ≥ 0.05 (Codex G6 STRENGTHENED) OR ΔSharpe ≥ 0.1 (alternate metric)
```

### Path B: Standalone regime sensor

```
Output: p_bad_monthly_t time-series (1 value per month)
Use case: STR_1715 PG2 add Layer 6 (in addition to M4 BOCPD + R05 Tail Risk)
  - Sequential overlay: w_final = w_str1715 × m4 × β_AR × β_R05 × β_bear_v1
  - β_bear_v1(p_bad_t): {p_bad < 0.3 → 1.0, 0.3~0.5 → 0.7, 0.5~0.7 → 0.5, > 0.7 → 0.3}
  - Defensive cash scaling on high-confidence bear prediction
```

### Path A vs B (Forge cycle decision)

- **Path A admit**: if DPL_KR_v3 cycle is also admit AND ΔAUC ≥ 0.05
- **Path B admit**: if standalone OOS test demonstrates clear regime sensitivity (Recall ≥ 0.6 + crisis-conditional defensive outperform)

**Both can be admit**: not mutually exclusive.

---

## 5. AX-008 Verification Triangulation (G6 binding)

본 cycle은 **multi-source verification** 정합:

| Source | Role | Output |
|---|---|---|
| **Forge** | empirical execution | 5-model ensemble fit + G1 5-subgate measurement |
| **Codex (4-cycle rounds)** | external evaluator (alpha + risk + optimizer + forge + judge + governor) | 5-stage Codex Round per agent |
| **Architect** | 3rd-source independent verification | concurrent spawn mandate (도훈 mandate v5 학습 strict) |

**Quorum requirement**: ≥ 2/3 PASS for admit.

**Architect concurrent spawn** (도훈 mandate v5 학습 strict, request.json axis_5_external_verification_strict):
- Forge cycle 중 architect agent spawn parallel
- Architect 산출물: `architect_audit.json` independent re-execution of ML fit
- Comparison: Architect's metrics vs Forge's metrics (delta < 1% threshold for AX-008 PASS)

---

## 6. Failure cutoffs (request.json mandate)

### HARD ABORT triggers

1. **G1 5-subgate all 5 models fail**: v5 paradigm-inviable confirm even with dedicated features + multi-source data + max-history → close cycle, archive lessons in L-code
2. **Synthetic detection by Codex**: any feature value identified as synthetic (no real source binding) — v4 학습 strict
3. **Feature pool invalid PIT**: lookahead_detector flags any feature → HARD ABORT
4. **Codex REJECT veto=true**: any Codex round REJECT with veto=true → DEFER

### DEFER triggers

- G1 partial pass (some subgates fail but not all)
- G2 economic significance fail
- G3 stability fail
- G4 DSR fail
- G5 integration fail (neither Path A nor Path B)
- G6 AX-008 quorum fail (only 0/3 or 1/3 PASS)

**DEFER → mutation cycle**: Forge cycle empirical FAIL ≠ paradigm fail (Charter §10 v1.8 정합). Design spec invalidated by Forge → next cycle re-design.

---

## 7. Production promotion eligibility

```
ELIGIBLE_FOR_PROMOTION = 
  G1 5-subgate ALL PASS AND
  G6 AX-008 ≥ 2/3 AND
  (G5 Path A: DPL_KR_v3 integration AUC uplift ≥ 0.05 OR G5 Path B: standalone regime sensor admit with m4/R05 layer 추가 정합)
```

If eligible: book_state mutation (add bear_v1 layer or replace M4 with hybrid M4+bear_v1).
If not eligible: STR_1715 PG2 retain unchanged (Session 80 admit lineage).

---

## 8. Codex Round mandate (5-stage flow per agent)

본 cycle 모든 agent (alpha-research + risk + optimizer + forge + judge + governor) Codex Round 의무 (Level 0 rule).

### Alpha-research cycle (this cycle)

```
Stage 1: alpha_package_draft.json write (this skill output)
Stage 2: PostToolUse codex_round_auto_trigger.sh background spawn (~9-15min)
Stage 3: codex_critic_response_alpha-research.json review
Stage 4: challenge_note_alpha-research.md write (각 concern ACCEPT/PARTIAL/REBUTTAL)
Stage 5: alpha_package.json final emit (after Codex disposition)
```

### Subsequent cycle Codex Rounds

- Risk-research: post-alpha_package
- Optimizer-research: post-risk_package
- Forge: post-optimizer (or post-risk for design-only)
- Judge: post-forge
- Governor: post-judge

Each spawn 5-stage flow mandatory. **우회 시 PreToolUse Hook BLOCK** (codex_round_pre_enforcer.sh).

---

## 9. Self-rationalization detection (Charter §8 No Silent Override)

본 cycle challenge_note write 시 다음 표현 자동 grep 검사:

```
"미미", "관행적", "보수적이면", "대부분 결과 동일", "실무적", "이미 반영", "백테스트 충분히 길어서 상쇄"
```

**Hit 시 RE-VIEW 의무**: REBUTTAL은 학술 1+ 인용 + L-code 1+ + 정량 data 3축 강화.

**HIGH severity ≥ 5 / AX hard FAIL ≥ 3 / PIT C1 위반 → Q-Lead escalate** 자동.

---

## 10. wt_type role card compliance (discovery_design_phase_a)

본 cycle wt_type = **discovery** (request.json line 5).

**Charter §10 v1.8 discovery_design_phase_a 정합** (WT-D20260518_001 SEFRS Phase A 첫 시연 + WT-D20260517_001 DPL_KR_v1 + WT-D20260519_001 DPL_KR_v3 inherit):

본 alpha-research cycle scope = **design phase only**:
- Own deliverables: 5 stage_artifacts md + alpha_package_draft + challenge_note + alpha_package
- Exempt deliverables: 
  - actual alpha_vector / confidence_vector (Forge cycle output)
  - alpha_scores.parquet (Forge cycle output)
  - harvey_t_count realized (Forge Stage 3 output)
- Inherited: SEFRS Phase A (S08) + STR_1715 lineage (M4/R05) + DPL_KR_v3 (WT_019_001 parallel)
- Deferred to Forge cycle: real PIT data collection + 32 feature computation + 5-model ensemble train + G1 5-subgate measurement + Architect concurrent

**Forge cycle empirical demonstration → admit OR design-invalidate decision**.

---

## 11. Alpha_discovery_certificate eligibility

**Role Card discovery_design_phase_a → alpha_discovery_certificate**:
- factor_specs ≥ 1: ✅ (1 unified bear_prediction_v1 family)
- alpha_inheritance_cor < 0.95: N/A (no parent alpha; new family)
- mechanism citation ≥ 50 chars: ✅ (8 학술 backbone, ~5000 chars dedicated_features md)
- harvey_t_specs_pass_count ≥ 3: **Pending Forge cycle Stage 3** (5 spec NW-adjusted t-stat target)

**design phase certificate**: SEFRS precedent inherit — Phase A design spec PASS = certificate eligibility 후 Forge cycle Stage 3 t-stat realized 시 issue.

---

## 12. Audit conclusion

도훈 mandate **"5-subgate strict + AX-008 + DPL_KR_v3 binding"** 정합 PASS:

1. ✅ 7 decision gates pre-declared (G0~G6)
2. ✅ G1 5-subgate strict (AUC + Brier + Recall + Precision + sub-window 4/5)
3. ✅ Threshold pre-declared (default + optimal-F1)
4. ✅ G5 dual path (DPL_KR_v3 integration OR standalone regime sensor)
5. ✅ G6 AX-008 quorum 2/3 (Forge + Codex + Architect)
6. ✅ Failure cutoffs HARD ABORT 4종 + DEFER 6종
7. ✅ Codex Round mandate 5-stage per agent
8. ✅ Self-rationalization detection grep
9. ✅ wt_type discovery_design_phase_a Charter §10 v1.8 정합

---

## 참조

- 도훈 mandate 2026-05-19 추가 (max-history + 8 crisis)
- request.json `decision_gates_5_axis_v5_learning`
- Charter §10 v1.8 discovery_design_phase_a Role Card
- `.claude/rules/codex-round.md` (5-stage Positive Hook 패러다임)
- `.claude/rules/axioms.md` AX-008 verification triangulation
- L-326 / L-328 / L-330 / WT-D20260518_001 SEFRS Phase A inherit
- L-247 answer-principles (Charter v1.4 §13)
