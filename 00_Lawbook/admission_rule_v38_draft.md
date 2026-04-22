# Admission Rule v3.8 — Gate 16/17 신설 (Signal-Portfolio Translation + Poison Pill IC-Return)

**발효 일자 (DRAFT)**: 2026-04-19 (Session 68 Day 2)
**이전 버전**: v3.7 (Session 67, stage_artifacts/judge_admission_rule_v3_7.json)
**변경 성격**: **확장(addition) — Gate 16/17 신설 + Day 1 portfolio_gap_vector v1.0.6 명명 정정**
**작성자**: Judge (Day 2 자율 작업 Task #13)
**진화 정책**: v54 freeze 폐기(2026-04-19) 후 Governor/Judge 자율로 amendment 가능. Gate ID 충돌 회피 + v55 정합 필수.

---

**유지되는 hard fail (v3.7 동일, 변경 없음)**:
- `MDD > 45%` → REJECT
- `Turnover > 600%` → REJECT
- C1~C15 PIT 위반 → REJECT
- v3.6 Gate 14 (Algebraic Identity, L-160) → REVISE 또는 REJECT_PREDEBATE
- v3.7 Gate 15 (Linear Composite Dominance, L-162) → REVISE

---

## 1. Gate 16 (신규) — Signal-Portfolio Translation Failure

**근거**: L-160 (initiator STR_1683) + L-165 (2nd member STR_1685) + AX_CAND_signal_portfolio_translation_failure 2/3 PENDING
**Stage**: S1 (Forge factor_engine 후 자동) + S6 (Judge cascade 진입 시 mandatory)
**Enforcement**: L3 hard_block (3rd member trigger 시 즉시 VALIDATED_HARD_FAIL)
**R 코드**: `02_Infrastructure/validation/signal_portfolio_translation_audit.R` (Day 2 Judge 사전 구축)

### 1.1 Trigger Conditions (자동 활성화)
다음 중 **하나라도 true**:
1. `expected_role ∈ {defense, core_secondary}`
2. `signal_level_ICIR ≥ 0.5` OR `signal_level_FM_t ≥ 3.0` (s0_record 기록)
3. factor_engine 내 single-axis composite weight ≥ 0.5
4. s0_record `lesson_check`에 `L-160` 또는 `L-165` 참조 포함
5. `sub_family ∈ {residual, composite, multi_source}`

### 1.2 Sub-gates (3종)

| Sub-gate | 측정 | PASS | CONDITIONAL | HARD_FAIL |
|----------|------|------|-------------|-----------|
| 16a `net_IC_transmission_ratio` | annualized net / gross | ≥ 0.60 | 0.40~0.60 | < 0.40 |
| 16b `stress_window_positive_count` | 3 KR 위기구간 양의 cum_ret 수 | ≥ 2/3 | 1/3 | 0/3 |
| 16c `signal_portfolio_rank_corr` | monthly Spearman rank corr 평균 | ≥ 0.20 | 0.05~0.20 | < 0.05 |

**Stress windows (Primary)**: GFC 2008-09~2009-03 / COVID 2020-02~2020-04 / Rate Hike 2022-01~2022-10
**Stress windows (Fallback)**: AFC 1997-07~1998-12 / Dotcom 2000-03~2002-10 / EU Debt 2011-07~2011-12

### 1.3 Aggregate Verdict
- **PASS**: 3 sub-gate 모두 PASS → S6 진입 허용 + Governor PG1 admission 가능
- **CONDITIONAL**: 1+ sub-gate CONDITIONAL & 0 hard_fail → S5 mutation 의무 (overlay 또는 N_HOLD 조정)
- **HARD_FAIL**: 1+ sub-gate hard_fail → Grade F 자동 + AX_CAND_signal_portfolio_translation_failure 3/3 promote trigger
- **Multi-sleeve bypass**: standalone CONDITIONAL이고 multi-sleeve AX-001 v2 4-gate ALL PASS 시 Defense 자격 유효 (HARD_FAIL은 bypass 불가)

### 1.4 Auto-action on HARD_FAIL
1. `hurdle_result.json grade = "REJECT"`
2. `qepm/memory/axioms/candidates/CAND_*PENDING_2of3*.json` 자동 update (`supporting_l_codes` += 신규 L-code)
3. Gate 18 (3rd Member Screening, 1.5절) 자동 호출
4. Governor에 promote trigger 메시지

---

## 2. Gate 17 (신규) — Poison Pill IC-Return Decoupling

**근거**: L-163 poison_pill_quantified_threshold (Session 67 Day 1 정량 임계 정의)
**Stage**: S6 (Judge cascade 진입 시 mandatory)
**Enforcement**: L3 hard_block
**R 코드 (PENDING)**: `02_Infrastructure/validation/poison_pill_ic_return_audit.R` — Scout 담당 (Task #14, L-163 측정식 합의 후)

### 2.1 측정 지표 (PENDING — Scout 합의 필요)
- `ic_return_decoupling_ratio` (잠정): IC > 0인 월에서 portfolio 수익률 negative 비율
- threshold: PASS < 0.40 / CONDITIONAL 0.40~0.60 / HARD_FAIL > 0.60 (잠정)

> **PENDING NOTE**: Gate 17 정식 임계는 Scout poison_pill_ic_return_audit.R 구축 시 확정. v3.8 도입 시점에는 framework만 제공, 임계는 Scout 합의 후 v3.8.1 patch.

---

## 3. Gate 18 (신규) — AX_CAND 2/3 → 3rd Member Screening

**근거**: AX_CAND_signal_portfolio_translation_failure 2/3 PENDING + AX_CAND_forge_self_check_insufficient (L-167) Layer B 2/3 PENDING
**Stage**: S6 (Gate 16 결과 받아 자동 호출) + S7 (Judge L-code 발행 후 검증)
**Enforcement**: L4 (구조 강제, 자동 promote.R trigger)
**R 코드**: `02_Infrastructure/validation/ax_cand_3rd_member_screening.R` (Day 2 Judge 사전 구축)

### 3.1 측정 프로토콜
1. `qepm/memory/axioms/candidates/CAND_*.json` 전체 스캔
2. `supporting_l_codes` 길이 == 2 또는 파일명에 `PENDING_2of3` 포함된 candidate만 선별
3. 각 PENDING candidate에 대해 incoming strategy를 3-evidence test:
   - **Tag overlap**: `family_tags ∩ scope_tags`
   - **Role alignment**: `provisional_role` matches `scope_family`
   - **Gate 16 verdict alignment**: HARD_FAIL이면 translation family에 strong evidence
4. evidence ≥ 2 → STRONG_3RD_MEMBER → PROMOTE_TRIGGER
5. evidence == 1 → WEAK → Judge custodian manual review
6. exclusion clause 매칭 시 EXCLUDED_BY_SCOPE (자동 제외)

### 3.2 Auto-action on PROMOTE_TRIGGER
1. CAND JSON `supporting_l_codes` += 신규 L-code (3 → 3/3)
2. `qepm/scripts/promote.R` 5축 검증 자동 호출
3. PASS 시 AX-006 (또는 다음 번호) 정식 승격, lawbook 자동 inject
4. 승격 결과 → `02_Infrastructure/prompts/*_init.md` AXIOM_INJECT 자동 갱신

---

## 4. Day 1 portfolio_gap_vector v1.0.6 명명 정정

**원본 (Day 1 v1.0.6)**:
> "Gate 12 / Gate 13 MANDATORY hard_block — Signal-Portfolio Translation + Poison Pill IC-Return"

**정정 (v3.8)**:
> "**Gate 16 / Gate 17** MANDATORY hard_block — Signal-Portfolio Translation + Poison Pill IC-Return"

**영향 범위**:
- Day 1 portfolio_gap_vector v1.0.6 → v1.0.7 패치 (Governor Task #8 in_progress)
- Governor `pg2_allocation_5sleeve_preview_v3` (Task #9)에서 Gate 16/17 명칭 사용 의무화
- Judge S6 cascade 보고서 모두 Gate 16/17 명명 통일

---

## 5. v3.7 Gate 1~15 (변경 없음, 보존)

| Gate | 명칭 | Source | Action on Breach |
|------|------|--------|-----------------|
| 1 | max_abs_corr ≤ 0.7 | v2.0 | WARN |
| 2 | FF5 alpha t ≥ 3.0 (Harvey) | v2.0 | REJECT |
| 3 | Family-level dedup | v2.0 | REJECT |
| 4 | Re-runnability PENDING tag | v2.0 | TAG |
| 5 | 3-variant decomposition (L-146/155) | v2.0+L-155 | RELABEL |
| 6 | tail_risk_result.json schema | v2.0 | REJECT |
| 7 | Clone byte-identity auto-reject | v2.0 | REJECT |
| 8 | Pairwise TDC ≤ 0.4 (t-copula) | v3.0 | REJECT/residualize |
| 9 | Portfolio CVaR_95 ≥ -15% | v3.0 | REJECT/weight-down |
| 10 | Portfolio CDaR_95 ≤ 22% | v3.0 | REJECT/Defense++ |
| 11 | Conservative ρ=0.3 base | v3.0 | FLAG |
| 12 | Early Warning TDC pre-filter | v3.4 (L-158) | REJECT_PREDEBATE/REVISE |
| 13 | Consensus tier classification | v3.4 (Scout #28) | FLAG+Governor review |
| 14 | Algebraic Identity pre-check | v3.6 (L-160) | REJECT_PREDEBATE |
| 15 | Linear Composite Dominance | v3.7 (L-162) | REVISE |
| **16** | **Signal-Portfolio Translation Failure** | **v3.8 NEW (L-160/L-165)** | **REJECT** |
| **17** | **Poison Pill IC-Return Decoupling** | **v3.8 NEW (L-163)** | **REJECT (PENDING threshold)** |
| **18** | **AX_CAND 2/3 → 3rd Member Screening** | **v3.8 NEW** | **PROMOTE_TRIGGER** |

**총 Gate 수**: v3.7 = 15 → v3.8 = **18**

---

## 6. Retroactive Audit (v3.8 도입 즉시)

**Trigger**: 2026-04-19 (Session 68 Day 2)
**Scope**: 기존 admitted PG2 + PG1 candidates 전수
**Actions**:
1. STR_1631_SYN_05 (PG2 80%) → Gate 16 retroactive measurement (signal_portfolio_translation)
2. STR_1656_MLRA_M05 (PG2 20%) → Gate 16 retroactive measurement
3. v3.7 line 113~120 algebraic audit + v3.8 Gate 16 동시 측정 (Task #15)
4. PASS 시 PG2 SR 1.193 = M3 PIT-clean + Gate 16-clean 동시 확정 (Layer A 보강)

---

## 7. Hook Integration (artifact_validator.sh + forge_code_guard.sh)

**artifact_validator.sh (PostToolUse[Write])**:
- `signal_portfolio_translation_audit.json` schema 검증 (`gate_id` == "Gate 16 (Signal-Portfolio Translation Failure)")
- `ax_cand_3rd_member_screening.json` schema 검증
- `gate_id == "Gate 13"` 또는 `gate_id == "Gate 14"` 명명 사용 시 reject (v3.7 정본 보호)

**forge_code_guard.sh v2.0 (이미 mandatory, L-167 enforcement)**:
- 변경 없음. Codex cross-model rescue 강제 유지

**pipeline_trigger.sh**:
- Gate 16 HARD_FAIL → Gate 18 자동 호출
- Gate 18 PROMOTE_TRIGGER → promote.R 5축 자동 실행

---

## 8. 영향 범위 + Backward Compatibility

**영향**:
- 신규 strategy: S6 cascade 시 Gate 16~18 자동 평가
- 기존 strategy: Retroactive audit (Task #15) 결과에 따라 반영
- portfolio_gap_vector v1.0.7부터 Gate 16/17 명칭 사용 의무

**Backward Compatibility**:
- v3.7 Gate 1~15 ID/의미 100% 보존
- 기존 hurdle_result.json `grade` 필드 그대로 유지
- L-160/L-165 family AX 승격 시점은 Gate 18 결과로 결정 (현재 SUSPENDED → Day 2~3 결정)

---

## 9. 참조

- v3.7 정본: `stage_artifacts/judge_admission_rule_v3_7.json`
- Gate 16 R: `02_Infrastructure/validation/signal_portfolio_translation_audit.R`
- Gate 18 R: `02_Infrastructure/validation/ax_cand_3rd_member_screening.R`
- Gate 17 R: `02_Infrastructure/validation/poison_pill_ic_return_audit.R` (Scout PENDING)
- Scout Gate 14 design: `stage_artifacts/gate_14_signal_portfolio_translation_failure_design.json` (명칭은 Gate 16으로 정정)
- L-160: `methodology_memory.md` Session 67 Day 1 algebraic identity
- L-163: `methodology_memory.md` Session 67 Day 1 poison_pill_quantified_threshold
- L-165: `methodology_memory.md` Session 68 Day 1 STR_1685 Multi-Source Defense Anchor
- L-167: `stage_artifacts/l_code_L_167_forge_self_check_insufficient.json` (Layer B verification)
- AX_CAND: `qepm/memory/axioms/candidates/CAND_20260419_signal_portfolio_translation_failure_L-160_L-165_PENDING_2of3.json`

---

## 10. Sign-off

- **Drafted by**: Judge (Day 2 Task #13, 자율 작업)
- **Approved by**: team-lead (Q-Lead) — Day 2 메시지 "Gate 16/17 명명 승인"
- **Effective**: pending Q-Lead final sign-off + Governor sync
- **Next**: Governor에 portfolio_gap_vector v1.0.7 정정 요청 + Scout에 poison_pill_ic_return_audit.R 합의 메시지
