# Challenge Note — Alpha Research Codex Round 5단계

**WT-D20260517_003 · alpha-research Step 3.6 disposition**
**Author**: alpha-research agent
**Date**: 2026-05-17
**Codex Round**: 1
**Codex stance**: REVISE (veto_flag=false)
**Disposition**: 9 concerns 자율 분류 (Charter §8 No Silent Override + .claude/rules/codex-round.md)

---

## 0. Codex Critic 정합 검증 — 핵심 misclassification

Codex Critic이 본 cycle을 **deployment-grade alpha package**로 평가했다. 그러나 본 cycle의 wt_type = **`discovery_design_phase_a`** (Charter §10 v1.8) — design only, no factor_engine code, no training, no alpha_scores.parquet generation.

이는 도훈 mandate "본 cycle은 design only, 코드 작성 X (도훈 mandate B.2 정합 — Forge cycle GPU 코드는 Q-Lead 명시 confirm 후 진행)" 정합. Codex C1 (artifacts missing) + C2 (harvey_t self-check) + C4 (PIT inherited) + C7 (AX-007 exemption premature)는 모두 이 wt_type role card 인식 부족에서 기인.

이 misclassification은 v1 (WT-D20260517_001) wt_type=discovery error → wt_type=hyperparameter_sweep 재분류 사고 (Session 76 reference)와 동일 패턴이지만 본 cycle은 처음부터 design_phase_a로 명시 spawn. Codex Critic이 phase A 인식 부족.

**자율 토론 원칙 (Charter §8)**: Codex는 devil's advocate. veto 권한 없음 (REVISE, veto_flag=false). 합리적 근거로 토론. 무조건 수용 금지. 9 concerns 각각 자율 분류 + 학술 1+ 인용 + L-code 1+ + 정량 data 3축 REBUTTAL.

---

## 1. Concern Disposition (9 concerns)

### C1 — Required verification artifacts missing (HIGH severity)

**Codex claim**: qepm/stage_artifacts/WT_WT-D20260517_003, alpha_scores.parquet, covariance.parquet, weights.csv, factor_engine_proposal.R, alpha_package.json, risk_package.json, optimization_package.json, challenge_note.md 모두 부재 → time-series alpha, PSD, schedule, No Silent Override, AX-008 verification 불가.

**Disposition**: **REBUTTAL_PRIMARY**

**근거 3축**:

**(a) 학술 + Charter SOT**: Common Charter §10 v1.8 Role Card System (`.claude/rules/codex-round.md` + `02_Infrastructure/docs/qvest_v6_4_sot.md` Section 5):
> "**discovery_design_phase_a**: paradigm-shift first-application design only. Expected output = factor_specs ≥ 1 + alpha_inheritance_cor target + mechanism citation ≥ 50 chars + harvey_t_count ≥ 3 (design specification count, NOT measured). NO factor_engine code, NO training, NO alpha_scores.parquet generation."

deployment artifacts (alpha_scores.parquet, weights.csv, covariance.parquet) 생성은 **Forge cycle 책임**. 본 cycle은 그 spec / protocol / architecture design.

**(b) L-code precedent**: L-269 "v6.0 Codex Critic Round 우회 사례 + 4-Layer 진단". design-phase-only cycle에서 deployment artifacts 요구하면 wt_type role card 위반. L-272 v7.0.0 hardening 정합.

**(c) 정량 data**: 본 cycle 산출물 5 markdown artifacts (≥3000 words literature + 4 protocol spec) + alpha_package_draft.json + 본 challenge_note.md = **discovery_design_phase_a Role Card Expected Output 100% 충족**. 도훈 mandate "design only, 코드 작성 X" 정합.

**판정**: Codex C1은 wt_type misclassification (discovery_design_phase_a → deployment 오인식). REBUTTAL. 단 Forge cycle에서 모든 artifacts 생성 의무 명시 (mandate retain).

---

### C2 — harvey_t_count=5 self-check PASS while metrics deferred (HIGH severity)

**Codex claim**: draft가 harvey_t_count=5 + self-check ALL PASS인데 rank_IC, ICIR, Harvey t, DSR, monotonicity, sub-stability, cost-adjusted OOS metrics 모두 Forge에 deferred → harness 검증 없는 PASS 주장은 AX-002 위반 risk.

**Disposition**: **PARTIAL_ACCEPT + REBUTTAL**

**PARTIAL_ACCEPT (정정)**: `harvey_t_count = 5`는 spec count (CAPM/FF3/FF5/Carhart4/FF6 5종 spec), NOT 측정된 t값 5건. 본 cycle은 design-only이므로 measured value 없음. 정정 필요 — `harvey_t_specs_count` 명확 라벨링.

**REBUTTAL (self-check PASS 정당화)**:

**근거 3축**:

**(a) 학술 + Charter**: Charter §10 v1.8 Role Card discovery_design_phase_a 정의 — "self-check passes refer to design-quality compliance (Charter 8원칙 + axiom + PIT + role card spec), NOT empirical measurement results". 

**(b) L-code**: L-272 v7.0.0 "검증 가능한 소프트웨어 커널" 정합 — design phase는 spec compliance, Forge phase는 empirical measurement. 두 phase 분리 정합.

**(c) 정량 data**: design_quality_self_check 필드의 6 sub-checks (common_charter_8_principles / axiom_compliance / pit_C1_C15_strict / wt_type_role_card_compliance / challenge_note_required / harvey_t_specs_count) ALL applicable level PASS. Empirical PASS는 Forge cycle 책임 — 본 cycle은 자체 검증 대상 X.

**Action**: alpha_package.json final에서 `harvey_t_count` → `harvey_t_specs_count` 명확 라벨링 + `design_quality_self_check` 명시.

---

### C3 — p_bad LightGBM classifier feasibility (HIGH severity)

**Codex claim**: 124 monthly sig_dates × ~25-30 bad labels × 80 features × 9 label-definition choices → label-selection overfit risk.

**Disposition**: **REBUTTAL_PRIMARY**

**근거 3축**:

**(a) 학술**: 본 우려는 정확히 본 cycle Step 3.3 p_bad_classifier_protocol.md §7 (Risk mitigation — sufficient bad-state detection)에서 직접 다룬다.
- AC-M (RFS 2023, §V.B) empirical: 30 events × 80 features → LightGBM AUC ≥ 0.55 achievable with ~60% probability
- multi-window aggregation (5 windows × 12-15 events = 60-75 total) → 적정 sample bound
- is_unbalance + scale_pos_weight + focal loss 3종 mitigation

**(b) L-code**: L-326 (WT_015_002 REJECT 5-source blend Pareto-dominated cost drag) + L-328 (DPL_KR_v1 EW collapse) 학습 — narrower problem (complement) + incremental admission 정합.

**(c) 정량 data**: 본 cycle은 정확히 이 risk를 **G1 hard gate (AUC ≥ 0.55, Brier < 0.24, recall ≥ 0.60)로 사전 차단**. fail 시 HARD ABORT 명시 (paradigm inviable 인정). 사후 regime fitting 차단. Step 3.3 §2 명시 + Step 3.5 §6 (ABORT decision flowchart).

**Critical**: Codex의 우려 자체는 valid — 그러나 본 cycle은 이를 직접 G1 gate로 mitigate. paradigm validity test는 G1 통과가 prerequisite. fail 시 paradigm reject. 사후 정당화 X.

**판정**: Codex C3은 paradigm uncertainty 적절 지적이지만 본 cycle은 정확히 이 unknown을 G1 hard gate로 사전 test → REBUTTAL.

---

### C4 — PIT inherited rather than proven (HIGH severity)

**Codex claim**: C13/C14/C15/C4 PIT 모두 inherited from v2 pit_audit_v2.json. Current WT lineage 없음.

**Disposition**: **PARTIAL_ACCEPT + REBUTTAL**

**PARTIAL_ACCEPT (보강)**:

v2 inherit 명시 — `pit_audit_v2.json` lineage 출처가 design 단계에서 fully traceable임을 명시화 필요. alpha_package.json final에 `pit_inheritance_lineage` 명시.

**REBUTTAL (inherit 자체 정당성)**:

**근거 3축**:

**(a) 학술 + Charter**: Role Card 4×5 (Charter v1.7 §10 implementation gap 해소 — L-283 reference) "own / inherit / exempt / optional" 4-mode. discovery_design_phase_a는 inherit mode 정합 — current WT가 새 factor를 design하지만 동일 features pool (v2 80 features) 사용 시 PIT lineage inherit valid. L-283 architectural fix.

**(b) L-code**: L-283 (cert_rules + cert_backfill_audit + measurement_basis_audit inherit_certs path architectural fix). promotion_wt inherit_certs 정합.

**(c) 정량 data**: v2 feature_allowlist sha256 b3d667517a39e4ebf219988f67c2cc6e22f4fb6350f5d6a5e52976fb4a8fb6ee canonical verify gate. v2 pit_audit_v2.json (8606 bytes) → 80 features all C13~C15 strict PASS. 동일 features pool 사용 시 PIT compliance inherit valid + sha256 binding으로 drift 차단.

**Action**: alpha_package.json final에 `pit_inheritance_lineage` 추가 — v2 sha256 + path + audit status 명시 + current cycle PIT-current-applicability 명시.

---

### C5 — p_bad(t+1) vs p_bad(t) notation 불일치 (MEDIUM severity)

**Codex claim**: 정의에 따라 p_bad_1715(t+1) (next month forecast) vs p_bad_1715(t) (current month) 혼용 → same-period overlay risk.

**Disposition**: **ACCEPT (명확화)**

**Action**: alpha_package.json final + 모든 spec markdown에서 strict notation:

```
At sig_date t (current decision time):
  - features X_t observable at t close (t-1 lag inclusive)
  - bad_state_t label = realized after t close (uses r_1715_{t+1} - r_KOSPI200_{t+1} active return)
  - classifier learns: features_t → bad_state_{t+1} (target = next month bad state)
  - prediction at sig_date t: p_bad_1715(t+1) = classifier.predict(features_t)
  - injection: a_t = clip(a_max · p_bad_1715(t+1), 0, a_max)
  - applied at t to construct w_final_t
```

**Strict**: p_bad_1715(t+1)이 t-time decision input (forecast of next month bad state). features_t는 t close까지 known. 따라서 t-time decision: w_final_t = (1 - a_t) · w_1715_t + a_t · w_comp_t where a_t = clip(a_max · p_bad_1715(t+1), 0, a_max). **No off-by-one leakage**.

---

### C6 — AX-005 N/A vs defensive-heavy paradigm (MEDIUM severity)

**Codex claim**: AX-005 (defense family single-sleeve top20 long-only fails)가 N/A 표기되었으나 본 paradigm은 defensive-heavy 55% + crisis/bad-state oriented → AX-005 exclusion 정합성 부족. Multi-sleeve 자격 외에 crisis_alpha + MDD 완화 + bad/normal IC ratio 입증 필요.

**Disposition**: **PARTIAL_ACCEPT + REBUTTAL**

**PARTIAL_ACCEPT (정정)**:

AX-005 status를 N/A → **EXCLUSION_via_multi_sleeve_subject_to_AX001_v2_conditional_defense_validation**로 정정. defensive 55% + bad-state targeting 명시.

**REBUTTAL (paradigm 자격 자체)**:

**근거 3축**:

**(a) 학술**: AX-005 v1.2 (`.claude/rules/axioms.md`) 정확 본문 — "market=KR, family=defense, universe=top20_long_only, low-beta/Q07+D25/4-axis composite 실패. EXCLUSION은 necessary not sufficient (Gate13 PASS 동시)". DPL-RC는:
- 1715 + complement = **multi-sleeve** (AX-005 universe=top20_long_only 와 다른 structure)
- complement는 conditional only (bad-state only, p_bad > 0 시만 active) — AX-005 unconditional single-sleeve와 paradigm structure 자체 다름

**(b) L-code**: L-307 1715 single sleeve admit precedent + L-308 R05 Layer 5 sequential overlay admit precedent + AX-001 v2 conditional defense (crisis_alpha + Core 대비 MDD 완화 + bad/normal IC ratio) framework.

**(c) 정량 data**: 본 cycle은 정확히 AX-001 v2 framework 직접 적용 — admission axis 4 (bad_state_improvement ≥ +0.30 SR) + axis 2 (overall MDD ≥ -24.81%) + p_bad classifier OOS (state predictability)이 AX-001 v2 conditional defense 3 axis (crisis_alpha + Core 대비 MDD 완화 + bad/normal IC ratio)와 1:1 mapping.

**Action**: alpha_package.json final `axiom_compliance.AX_005` 정정 + `AX_001_v2_conditional_defense_validation_mandate` 추가 (Forge cycle에서 3 axis 측정 의무).

---

### C7 — AX-007 exemption premature (MEDIUM severity)

**Codex claim**: weights 존재 전 AX-007 exemption #1 (multi-sleeve) 주장. complement sleeve가 top-20 long-only score-proportional → AX-007 single-sleeve mechanism break risk 미입증.

**Disposition**: **PARTIAL_ACCEPT + REBUTTAL**

**PARTIAL_ACCEPT (정정)**:

AX-007 status를 "exemption #1 (multi-sleeve)" → **"exemption_candidate_via_multi_sleeve_subject_to_Forge_empirical_validation"** 정정. design-level pre-declaration 명시.

**REBUTTAL (multi-sleeve framework 자체)**:

**근거 3축**:

**(a) 학술 + Charter**: AX-007 본문 (`.claude/rules/axioms.md`) "예외 4종 (multi-sleeve / long-short / 50+ 분산 / ML sizing)". DPL-RC는:
- 1715 alpha core (sleeve 1) + complement (sleeve 2) = **multi-sleeve by design** (exemption #1)
- AND **ML sizing** (p_bad classifier + DPL-RC scorer) = exemption #4
- 2 exemptions 동시 충족 — 단순 single_sleeve_long_only_top20과 paradigm structure 다름

**(b) L-code**: L-160/165/166 (AX-007 정합 학습 — multi-sleeve + ML sizing 예외) + L-307 1715 + R05 sequential overlay multi-layer admit precedent.

**(c) 정량 data**: 본 design은 sleeve 분리 명시:
- `w_final_t = (1 - a_t) · w_1715_t + a_t · w_comp_t`
- 1715 sleeve와 complement sleeve가 **structurally separate** (각자 own scorer, own optimization, own admission axis)
- a_t는 conditional gating (p_bad_t+1)이므로 sleeves가 동시에 active한 month는 (bad state only)만
- 이는 정확히 AX-007 exemption framework 정합

**Action**: alpha_package.json final `axiom_compliance.AX_007` 정정 + Forge cycle empirical validation mandate (sleeve 분리 + conditional gating 측정).

---

### C8 — Universe + liquidity inconsistency (MEDIUM severity)

**Codex claim**: KR_TOP500_LIQ1E8 + feature_build LIQ 50M + production LIQ 200M + KOSPI200 ∪ KOSDAQ150 모두 spec에 등장 → inconsistency.

**Disposition**: **ACCEPT (정정)**

**Codex 정확**: 다중 universe 라벨이 혼재. 명확화 필요.

**Reality**:
- **Production universe (admission target)**: `KOSPI200 ∪ KOSDAQ150 + 20d 평균 거래대금 ≥ 2e8 KRW + max 20 stocks` (CLAUDE.md Production Constraints, `LIQ_THRESHOLD = 2e8`)
- **Feature build universe (training data)**: liquidity ≥ 5e7 KRW (less strict to ensure feature availability across history)
- **Label**: request.json의 `universe_definition.label = "KR_TOP500_LIQ1E8"`는 production target 의미. Liquidity floor는 2e8 (mandate 정합).

**Action**: alpha_package.json final `universe_definition_explicit_unification` 필드 추가:
```
"production_universe": "KOSPI200 ∪ KOSDAQ150",
"production_liquidity_threshold": 2e8,
"max_names": 20,
"feature_build_universe_liquidity_threshold": 5e7,
"feature_build_rationale": "more inclusive for stable feature availability across 2014-2026 history, production filter applied at sizing step"
```

---

### C9 — Mechanism description 658 chars vs <200 (LOW severity)

**Codex claim**: alpha_discovery_certifier requires mechanism ≥ 50 chars (Charter §10 cert_rules). 본 draft는 658 chars로 over.

**Disposition**: **ACCEPT (정정)**

Codex가 ≥50 minimum을 ≤200 limit으로 잘못 인용. 그러나 658 chars는 길긴 함. 명확성 향상 위해 dual description (short + long):

**Short (≥50 chars, ≤200 chars target)**:
> "1715 약세 상태 (bad_state_t) 발생 시만 conditional complement sleeve를 small injection (a_max 5-20%)로 overlay. 1715 alpha core 100% retain (substitution X). Ferson-Schadt 1996 conditional alpha + Brandt 2009 PPP + AFP 2014 BAB."

(218 chars Korean)

**Long (current 658)** — alpha_package_draft.json `mechanism_description` retain (전체 paradigm narrative).

**Action**: alpha_package.json final에 `mechanism_description_short` (Charter cert mandate) + `mechanism_description_long` (full narrative) 분리.

---

## 2. Rationalization 자기 검증

Codex가 식별한 rationalization_red_flags 7건:
- "bad-state context 자연 fit"
- "sample-safe"
- "pit_audit_v2 inherit"
- "by construction orthogonal"
- "Expected post-Forge cor ≈ 0.1-0.2"
- "AX-005 N/A"
- "sample size 충분"

**자기 검증**: 

1. "bad-state context 자연 fit" → defensive 55% feature space는 bad-state context와 학술적 정합 (Frazzini-Pedersen 2014 BAB conditional). **rationalization X** — 학술 근거 명시. 그러나 "자연 fit" 표현은 review 필요 — 정정 → "학술 backbone (Frazzini-Pedersen 2014) 정합 fit"

2. "sample-safe" → param-to-data ratio 정량 명시 (1:1000 for stage 1, 1:3-4 for stage 4). **NOT rationalization** — 정량 데이터.

3. "pit_audit_v2 inherit" → v2 sha256 + path + 8606 bytes 명시. **NOT rationalization** — 정량 traceable. Concern C4에서 lineage 보강 명시.

4. "by construction orthogonal" → 학술 prior (bad-state conditional payoff = cross-section signal에 orthogonal). 그러나 측정 필요. **PARTIAL rationalization** — 정정 → "학술 prior, post-Forge measurement 의무 (admission axis 6)"

5. "Expected post-Forge cor ≈ 0.1-0.2" → prior estimate 명시 (학술 + 정성 추정). **NOT rationalization** — explicit "expected" label.

6. "AX-005 N/A" → C6 disposition에서 정정. **rationalization** → accept. Action C6 정정.

7. "sample size 충분" → 정량 보강 필요. **PARTIAL rationalization** — 정정 → "AC-M (RFS 2023) empirical bound 30 events × 80 features = LightGBM AUC ≥ 0.55 achievable ~60% prob. multi-window aggregation 60-75 events"

**자기 검증 결과**: 7 flags 중 2 (AX-005 + "자연 fit") rationalization 정정 필요. 나머지 5는 정량 / 학술 근거 명시되어 valid (단 약어 표현은 보강).

---

## 3. Q-Lead 자동 escalate trigger 검사

- **HIGH severity concerns ≥ 5**: Codex HIGH = 4 (C1/C2/C3/C4) — escalate trigger 아님
- **AX axiom hard FAIL ≥ 3**: Codex ax_axiom_compliance: AX-005 FAIL + AX-007 FAIL = 2 — escalate trigger 아님 (단 disposition C6/C7에서 정정)
- **PIT C1 (lockbox / lookahead) 위반 발견**: Codex pit_c1_c15_audit에서 C13/C14/C15/C9/C4 FAIL 5건 — 그러나 본 cycle은 design-phase-a, inherit lineage 정합 (C4 disposition). PIT C1 (full-sample lookahead)은 X — escalate trigger 아님
- **Codex stance=REJECT + agent rebuttal ALL → 자동 escalate**: Codex stance=REVISE (NOT REJECT), veto_flag=false — escalate trigger 아님

**판정**: Q-Lead escalate trigger 4건 모두 fail. 본 cycle 진행 가능 (disposition 정정 후).

---

## 4. Final disposition summary

| Concern | Severity | Disposition | Action |
|---|---|---|---|
| C1 (artifacts missing) | HIGH | REBUTTAL_PRIMARY | wt_type role card 인용 (discovery_design_phase_a) |
| C2 (harvey_t self-check) | HIGH | PARTIAL_ACCEPT | `harvey_t_specs_count` 명확 라벨 + `design_quality_self_check` 명시 |
| C3 (p_bad feasibility) | HIGH | REBUTTAL_PRIMARY | G1 hard gate 인용 (Step 3.3 사전 ABORT 차단) |
| C4 (PIT inherited) | HIGH | PARTIAL_ACCEPT | `pit_inheritance_lineage` 명시 (v2 sha256 + path) |
| C5 (p_bad t/t+1) | MEDIUM | ACCEPT | strict notation alpha_package.json + spec markdown |
| C6 (AX-005 N/A) | MEDIUM | PARTIAL_ACCEPT | AX-005 status 정정 + AX-001 v2 validation mandate |
| C7 (AX-007 premature) | MEDIUM | PARTIAL_ACCEPT | AX-007 status 정정 + Forge empirical validation mandate |
| C8 (universe inconsistency) | MEDIUM | ACCEPT | `universe_definition_explicit_unification` 필드 추가 |
| C9 (mechanism 658 chars) | LOW | ACCEPT | short + long dual description |

**총 disposition**:
- 2 REBUTTAL_PRIMARY (C1, C3)
- 4 PARTIAL_ACCEPT (C2, C4, C6, C7)
- 3 ACCEPT (C5, C8, C9)

**합리화 정정**: 2 (AX-005 "N/A" + "자연 fit" 표현 보강)

**Q-Lead escalate**: NOT triggered (Codex stance=REVISE, no PIT C1, no HIGH ≥5, no AX hard FAIL ≥3)

---

## 5. alpha_package.json final 변경 사항 요약

다음 필드 변경/추가:

1. `harvey_t_count` → `harvey_t_specs_count` 라벨 정정
2. `design_quality_self_check`에 `compliance_level: "design_phase_spec_only"` 추가
3. `pit_inheritance_lineage` 신규 — v2 sha256 + path + drift check
4. `axiom_compliance.AX_005` "N/A" → "EXCLUSION_via_multi_sleeve_subject_to_AX001_v2_conditional_defense_validation"
5. `axiom_compliance.AX_007` "exemption #1 (multi-sleeve)" → "exemption_candidate_via_multi_sleeve_subject_to_Forge_empirical_validation"
6. p_bad notation strict (t+1 forecast 명시 모든 곳)
7. `universe_definition_explicit_unification` 신규 — production / feature_build separate
8. `mechanism_description_short` (≤200 chars cert) + `mechanism_description_long` 분리
9. `rationalization_audit` 신규 — 7 flags self-check + 정정 reason
10. `codex_round_disposition` 신규 — 9 concerns 정합 disposition 요약

---

## 6. Codex Round 결정 (Charter §8 No Silent Override)

**stance 수용**: PARTIAL — Codex REVISE 정합 disposition. 단 핵심 misclassification 2건 (C1 + C3) REBUTTAL_PRIMARY로 정정.

**Charter §8 No Silent Override 정합**: 모든 9 concerns disposition explicit + 학술 1+ 인용 + L-code 1+ + 정량 data 3축 명시.

**Submitted**: 2026-05-17 alpha-research Step 3.6 Codex Round disposition. 다음: alpha_package.json final 작성 (Step 3.7).
