# Admission Rule v3.8.1 — Gate 17 ACTIVE 승격 + Gate ID 정합 Patch

**발효 일자 (FINAL)**: 2026-04-23 (Session 69)
**이전 버전**: v3.8 draft (`admission_rule_v38_draft.md`, 2026-04-19 Session 68 Day 2)
**변경 성격**: **Patch (minor) — Gate 17 ACTIVE 승격 + R 코드 gate_id 상수 정정 사양서**
**작성자**: Judge (Session 69 Task, Q-Lead Option 1 승인)
**Governor review**: APPROVE_WITH_CONDITIONS (2026-04-23) — 수정사항 2건 반영 완료 (§1.2 `ax_cand_3rd_member_screening.R` 추가 정정 3줄 + `poison_pill_ic_return_audit.R` sub_gates key 주석 정책)
**Governor sign-off 추가**: STR_1631 Gate 17 Non-applicable APPROVE / STR_1656 Gate 17 Non-applicable APPROVE_CONDITIONAL (retroactive audit 사유 명시 요구) / AX_CAND JSON gate_ref 업데이트 NOT REQUIRED (하드코딩 없음) / gap_vector v1.0.9+ 갱신 예약 (현 v1.0.8 blocker 없음)

---

## 0. 배경

v3.8 draft §2 "Gate 17 (Poison Pill IC-Return Decoupling)" 항목은 "PENDING threshold — Scout 합의 후 v3.8.1 patch"로 기술되어 있다. 그러나 Session 69 Judge 재검토 결과:

- **실제 R 코드 `02_Infrastructure/validation/poison_pill_ic_return_audit.R`** (Apr 19 16:28, 13554 bytes)에서 threshold 4종 전부 확정됨
  - `.PP_PRODUCT_HARD_FAIL = -0.05` (L-163 Option α, Scout 2026-04-18 채택)
  - `.PP_PRODUCT_WARN = -0.03`
  - `.PP_REGIME_AMPL_FACTOR = 1.5`
  - `.PP_WEIGHT_CAP_AFTER_VIOLATION = 0.10`
- **Sub-gate 12a/12b/12c 전부 구현**, aggregate verdict + audit_from_handoff_kit() 헬퍼까지 구비
- **L-163 상태**: `02_Infrastructure/validation/poison_pill_ic_return_audit.R:9,29,228,245`에서 "L-163 ACTIVE" 명시

→ 즉 Gate 17은 **이미 ACTIVE이나 v3.8 draft 문서가 최신 상태를 반영 못 함**. 본 patch가 공식 승격.

추가로 **R 코드의 `gate_id` 상수가 v3.4 기준(Gate 12/13/14)으로 남아 있어 v3.8 (Gate 16/17/18) 명명과 불일치**. 이 Gate ID 충돌은 v3.7 Gate 14(Algebraic Identity, L-160)와 R 코드 `ax_cand_3rd_member_screening.R`의 `gate_id = "Gate 14"`가 **같은 번호를 중복 점유**하는 구조적 모순을 야기.

---

## 1. 변경 사항 (v3.8.1 = v3.8 + 본 patch)

### 1.1 Gate 17 PENDING → ACTIVE 승격

**이전 (v3.8 draft §2, line 65~71)**:
> **R 코드 (PENDING)**: `02_Infrastructure/validation/poison_pill_ic_return_audit.R` — Scout 담당 (Task #14, L-163 측정식 합의 후)
>
> ### 2.1 측정 지표 (PENDING — Scout 합의 필요)
> - `ic_return_decoupling_ratio` (잠정): IC > 0인 월에서 portfolio 수익률 negative 비율
> - threshold: PASS < 0.40 / CONDITIONAL 0.40~0.60 / HARD_FAIL > 0.60 (잠정)
>
> > **PENDING NOTE**: Gate 17 정식 임계는 Scout poison_pill_ic_return_audit.R 구축 시 확정. v3.8 도입 시점에는 framework만 제공, 임계는 Scout 합의 후 v3.8.1 patch.

**변경 후 (v3.8.1)**:

> **R 코드**: `02_Infrastructure/validation/poison_pill_ic_return_audit.R` (Session 68 Day 2 구축 완료)
>
> **채택 기준**: L-163 Option α (Scout 2026-04-18 채택, Judge 승격 2026-04-23)
>
> ### 2.1 측정 지표 (ACTIVE)
>
> **주 측정식**: 각 factor f에 대해 `stress_icir(f) × weight(f)` (Defense composite 한정)
>
> **Thresholds (R 상수)**:
> | 상수 | 값 | 의미 |
> |------|----|----|
> | `.PP_PRODUCT_HARD_FAIL` | `-0.05` | HARD_FAIL 경계 (L-163 main rule) |
> | `.PP_PRODUCT_WARN` | `-0.03` | CONDITIONAL (WARN) 경계 |
> | `.PP_REGIME_AMPL_FACTOR` | `1.5` | crisis stress_icir이 bull 기준 1.5× 악화 시 amplification flag |
> | `.PP_WEIGHT_CAP_AFTER_VIOLATION` | `0.10` | HARD_FAIL 시 auto action 상한 |
>
> **Sub-gates (3종, 모두 구현)**:
> - **12a per_factor_pill_check**: 각 factor f에 `stress_icir(f) × weight(f) ≥ -0.05` (L-163 main rule). 위반 시 HARD_FAIL.
> - **12b composite_pill_count**: HARD_FAIL factor 수 ≤ 0 (Defense composite admission 강제).
> - **12c regime_conditional_amplification**: bull/crisis stress_icir 증폭 비교. CONDITIONAL (S6 monitor, hard fail 아님).
>
> **Aggregate**:
> - PASS — 모든 sub-gate PASS
> - CONDITIONAL — 12a PASS이나 12c amplification flag
> - HARD_FAIL — 12a 또는 12b HARD_FAIL → `variant_comparison` 강제 (drop or weight-cap 10%)
>
> **Evidence case (L-144 → L-163)**:
> - Q24_Altman_Z: stress_icir = -0.695, weight = 0.25 → product = -0.174 (threshold 대비 3.48× 초과) → HARD_FAIL
>
> **R 함수 시그니처** (v3.8.1 정식):
> ```r
> audit_poison_pill_ic_return(strategy_id, factor_weights, stress_icir_map,
>                             regime_icir_map = NULL, output_dir = NULL)
> audit_from_handoff_kit(handoff_kit_path, families_path, output_dir)
> ```

### 1.2 R 코드 `gate_id` 상수 정정 사양서 (코드 수정은 Forge/Architect 담당)

**배경**: v3.7 Gate 14(Algebraic Identity)/Gate 15(Linear Composite)과 v3.8 신설 Gate 16/17/18이 R 코드에서 Gate 12/13/14로 명명되어 **번호 중복**. 특히 "Gate 14 Algebraic Identity"(v3.7) vs "Gate 14 AX_CAND 3rd Member Screening"(R 코드)가 충돌.

**정정 사양서 (Governor 2026-04-23 review 반영 — §1.2 확장: 3 → 6 항목)**:

| # | 파일 | 위치 | 현재 값 | v3.8.1 정정 값 | 유형 |
|---|------|------|---------|--------------|------|
| 1 | `signal_portfolio_translation_audit.R` | `:192` | `gate_id = "Gate 13 (Signal-Portfolio Translation Failure)"` | `"Gate 16 (Signal-Portfolio Translation Failure)"` | gate_id 상수 |
| 2 | `poison_pill_ic_return_audit.R` | `:234` | `gate_id = "Gate 12 (Poison Pill IC-Return)"` | `"Gate 17 (Poison Pill IC-Return Decoupling)"` | gate_id 상수 |
| 3 | `ax_cand_3rd_member_screening.R` | `:161` | `gate_id = "Gate 14 (AX_CAND 2/3 → 3rd Member Screening)"` | `"Gate 18 (AX_CAND 2/3 → 3rd Member Screening)"` | gate_id 상수 |
| 4 **(Governor 추가)** | `ax_cand_3rd_member_screening.R` | `:89` | `# Direct verdict signal (Gate 13 hard_fail = strong evidence for translation family)` | `# Direct verdict signal (Gate 16 hard_fail = strong evidence for translation family)` | 주석 |
| 5 **(Governor 추가)** | `ax_cand_3rd_member_screening.R` | `:93` | `hits <- c(hits, "Gate 13 HARD_FAIL aligns with translation failure family")` | `hits <- c(hits, "Gate 16 HARD_FAIL aligns with translation failure family")` | hits 문자열 |
| 6 **(Governor 추가)** | `ax_cand_3rd_member_screening.R` | `:191` | `cat("=== Gate 14 — AX_CAND 3rd Member Screening ===\n")` | `cat("=== Gate 18 — AX_CAND 3rd Member Screening ===\n")` | print_summary() 출력 |

**정정 방법** (Judge 권고, Forge/Architect 실행):
1. 6곳 모두 단순 문자열 치환. 항목 #4/#5는 `gate_13_verdict` 함수 인자명을 `gate_16_verdict`로 rename 시 function signature 변경 범위 점검 필요 (호출자 영향). Judge 권고: 인자명 `gate_13_verdict`는 그대로 두고 **주석/문자열만** 변경하여 downstream API 호환성 유지.
2. Sub-gate 내부 명명("12a/12b/12c") — **Option X (보수 유지)** Governor 동의. 상위 `gate_id`만 변경, sub-gate key는 "12a/12b/12c" 유지.
3. **Governor 요구 주석 (필수)** — `poison_pill_ic_return_audit.R:239~243` 인근에 다음 주석 블록 추가:
   ```r
   # sub_gates key naming: historical (v3.4 Gate 12 era). Gate ID = Gate 17 as of v3.8.1.
   # downstream callers: do NOT match on sub_gate key prefix "12" for Gate ID routing.
   sub_gates = list(
     `12a_per_factor_pill_check`     = a,
     `12b_composite_pill_count`      = b,
     `12c_regime_amplification_flag` = c_
   ),
   ```
   이유: `artifact_validator.sh`가 sub_gate key를 Gate ID로 오인할 경우 오탐 가능성 차단 (Governor APPROVE_WITH_CONDITIONS 필수 조건 2).
4. 변경 후 `artifact_validator.sh`의 Gate ID regex 검증 (v3.8 draft §7 hook integration)이 "Gate 16" / "Gate 17" / "Gate 18" 명명을 기대하므로 호환 확인.

**영향**:
- v3.8 draft §7 "hook integration" 조항 (Gate 13/14 거부 로직)과 정합
- Gate ID 충돌(v3.7 Gate 14 vs R 코드 Gate 14) 해소
- 기존 테스트 fixture가 `gate_id = "Gate 12"` 또는 `cat("=== Gate 14 ...")` 출력을 기대한다면 fixture 갱신 필요
- `ax_cand_3rd_member_screening.R` 단독 실행 시 console 출력이 "Gate 18"로 표시됨 (CI/테스트 log 파싱 regex 갱신 필요할 수 있음)

### 1.3 v3.8 draft §9 참조 섹션 업데이트

**이전 (v3.8 draft line 191)**:
> - Gate 17 R: `02_Infrastructure/validation/poison_pill_ic_return_audit.R` (Scout PENDING)

**변경 후 (v3.8.1)**:
> - Gate 17 R: `02_Infrastructure/validation/poison_pill_ic_return_audit.R` (ACTIVE, L-163 Option α — Session 68 Day 2 구축, Session 69 Judge 승격)

### 1.4 Total Gate Count (v3.8.1 확정)

| Gate | 명칭 | Source | Action on Breach | Status (v3.8.1) |
|------|------|--------|-----------------|------------------|
| 1~15 | (v3.7 동일, 보존) | v2.0~v3.7 | 각 Action | ACTIVE |
| 16 | Signal-Portfolio Translation Failure | v3.8 NEW (L-160/L-165) | REJECT | ACTIVE (코드 명명 정정 대기) |
| 17 | Poison Pill IC-Return Decoupling | v3.8 NEW (L-163) | REJECT | **ACTIVE** (L-163 Option α, v3.8.1 승격) |
| 18 | AX_CAND 2/3 → 3rd Member Screening | v3.8 NEW | PROMOTE_TRIGGER | ACTIVE (코드 명명 정정 대기) |

**총 18 gate** (v3.8 == v3.8.1).

---

## 2. Backward Compatibility

- **v3.8 Gate 1~18 ID/의미 100% 보존**. v3.8.1은 Gate 17 상태만 PENDING → ACTIVE 승격 + R 코드 `gate_id` 상수 명명 정정 사양.
- **기존 artifact JSON** (`poison_pill_ic_return_audit.json`): R 코드 정정 전에 생성된 artifact의 `gate_id = "Gate 12"`는 v3.7 기준으로 해석 (v3.8.1 승격 이후 새 artifact는 "Gate 17").
- **Hook integration**: `artifact_validator.sh`의 Gate 명명 regex는 R 코드 정정과 동시 배포 필요 (v3.8 draft §7).

---

## 3. 실행 순서 (Q-Lead 2026-04-23 확정)

**Status**: Governor APPROVE_WITH_CONDITIONS + Q-Lead 최종 sign-off APPROVED. Patch chain 독립 유지 결정.

1. **Governor review** — ✅ **완료** (2026-04-23 APPROVE_WITH_CONDITIONS). 수정사항 2건 반영 완료.
2. **Q-Lead sign-off** — ✅ **완료** (2026-04-23 APPROVED).
3. **Forge/Architect R 코드 정정** — 🔄 **DISPATCHED** (Q-Lead 2026-04-23). §1.2 사양서 6 항목 + 주석 블록 (Governor 수정 반영). sub-gate hash key = Option X 보수 유지.
4. **Hook validator 갱신** — 🔜 Forge 담당. `artifact_validator.sh`의 Gate 16/17/18 regex 활성화. R 코드 정정과 동시 배포.
5. **기존 artifact annotation 또는 재생성** — Judge 권고: schema_version annotation 추가 (Option A, 최소 변경). 재실행(Option B)은 Retroactive monthly_returns_gross.csv 재계산과 동시 진행.
6. **Retroactive measurement** — 🔜 Forge STR_1686/STR_1689 S1 완료 후. monthly_returns_gross.csv 재계산 + audit_from_strategy_dir() (STR_1631 + STR_1656).
7. **Judge final verdict** — 🔜 `retroactive_audit_final_v3_8_1.json` 발행 (ESTIMATED → PRECISE).
8. **Governor portfolio_gap_vector v1.0.9 갱신** — 🔜 `admission_rule_version: "v3.8.1 (18 gates)"` 명시.
9. **본문 병합** — ⏸ **보류** (Q-Lead 2026-04-23 결정). major version bump (v3.9 또는 v4.0) 시점에 일괄 처리. Patch chain 독립 유지 (Governor revX pattern과 동일).

---

## 4. Retroactive Audit 영향 (v3.8 §6, Task #15)

v3.8 §6 Retroactive Audit 대상(STR_1631_SYN_05, STR_1656_MLRA_M05)은 Gate 16 + Gate 17 모두 받아야 함.

- Gate 17은 Defense composite에만 적용 → Core 전략인 STR_1631은 **Non-applicable** (audit_poison_pill_ic_return() 호출 생략 가능)
- STR_1656_MLRA_M05 (ML regime-adaptive, trail=ml_empirical_first) → **Gate 17 적용 여부 미정**. Judge 권고: ML 전략은 stress_icir 분해가 factor 레벨이 아닌 feature 레벨이므로 **Non-applicable**로 분류하되, v3.8.1 retroactive audit 시 Scout/Forge와 합의 필요.

자세한 설계서는 Retroactive Audit 설계서 초안 (별도 작성 예정)에 기재.

---

## 5. 참조

- v3.8 draft: `00_Lawbook/admission_rule_v38_draft.md`
- Gate 17 R (ACTIVE): `02_Infrastructure/validation/poison_pill_ic_return_audit.R`
- L-163: `methodology_memory.md` Session 67 Day 1 poison_pill_quantified_threshold
- L-144: Q24_Altman_Z single-factor evidence
- AX_CAND: `qepm/memory/axioms/candidates/CAND_20260419_signal_portfolio_translation_failure_L-160_L-165_PENDING_2of3.json`

---

## 6. Sign-off

- **Drafted by**: Judge (Session 69, 2026-04-23)
- **Approved by (Option 1)**: team-lead (Q-Lead) — "v3.8.1 patch Option 1 승인"
- **Governor review**: APPROVE_WITH_CONDITIONS (2026-04-23) — 수정사항 2건 전부 반영 완료
- **Q-Lead 최종 sign-off**: **APPROVED** (2026-04-23) — "8/8 조건 충족 + 3 artifact 검증 완료"
- **Versioning policy** (Q-Lead 2026-04-23 결정): **Patch chain 독립 유지** (본문 병합 보류)
  - v3.8 lawbook 본문은 건드리지 않음. v3.8.1/v3.8.2/... patch chain으로 순차 적용.
  - Hook validator + R 코드는 항상 latest patch까지 적용. `artifact_validator.sh` 갱신 시 "v3.8 + patches through v3.8.1" 기준.
  - 본문 통합은 major version bump (v3.9 또는 v4.0) 시점에 일괄 처리.
  - Governor revX pattern과 동일 (rev6/rev7/rev8 독립 유지).
- **Execution order confirmed** (Q-Lead 2026-04-23):
  1. Forge R 코드 정정 dispatch — **DISPATCHED** (Q-Lead)
  2. Hook validator Gate 16/17/18 regex 갱신 — Forge
  3. STR_1686/STR_1689 S1 완료 후 Retroactive monthly_returns_gross.csv 재계산 — Forge
  4. Judge `retroactive_audit_final_v3_8_1.json` 발행 (ESTIMATED → PRECISE)
  5. Governor `portfolio_gap_vector v1.0.9` 갱신 (`admission_rule_version: v3.8.1 (18 gates)`)
  6. 본문 병합은 v3.9/v4.0 major bump 시점 (현재 보류)
- **Next**: Forge R 코드 정정 결과 수신 시 Judge가 `artifact_validator.sh` regex와 정합 검증 + S6 cascade 진입 (Forge STR_1686/STR_1689 DONE → TODO_S6)

---

## 부록 A — R 코드 정정 diff 미리보기 (Governor 2026-04-23 review 반영, 6 항목)

### A.1 `signal_portfolio_translation_audit.R:192` — gate_id 상수
```diff
-    gate_id                   = "Gate 13 (Signal-Portfolio Translation Failure)",
+    gate_id                   = "Gate 16 (Signal-Portfolio Translation Failure)",
```

### A.2 `poison_pill_ic_return_audit.R:234` — gate_id 상수
```diff
-    gate_id         = "Gate 12 (Poison Pill IC-Return)",
+    gate_id         = "Gate 17 (Poison Pill IC-Return Decoupling)",
```

### A.3 `ax_cand_3rd_member_screening.R:161` — gate_id 상수
```diff
-    gate_id              = "Gate 14 (AX_CAND 2/3 → 3rd Member Screening)",
+    gate_id              = "Gate 18 (AX_CAND 2/3 → 3rd Member Screening)",
```

### A.4 `ax_cand_3rd_member_screening.R:89` — 주석 (Governor 추가)
```diff
-  # Direct verdict signal (Gate 13 hard_fail = strong evidence for translation family)
+  # Direct verdict signal (Gate 16 hard_fail = strong evidence for translation family)
```

### A.5 `ax_cand_3rd_member_screening.R:93` — hits 문자열 (Governor 추가)
```diff
-    hits <- c(hits, "Gate 13 HARD_FAIL aligns with translation failure family")
+    hits <- c(hits, "Gate 16 HARD_FAIL aligns with translation failure family")
```

### A.6 `ax_cand_3rd_member_screening.R:191` — print_ax_cand_screening() 헤더 (Governor 추가)
```diff
-  cat("=== Gate 14 — AX_CAND 3rd Member Screening ===\n")
+  cat("=== Gate 18 — AX_CAND 3rd Member Screening ===\n")
```

### A.7 `poison_pill_ic_return_audit.R:239~243` — sub_gates Option X + 주석 (Governor 필수 요구)
```r
# 정정 후 (v3.8.1 final):
# sub_gates key naming: historical (v3.4 Gate 12 era). Gate ID = Gate 17 as of v3.8.1.
# downstream callers: do NOT match on sub_gate key prefix "12" for Gate ID routing.
sub_gates = list(
  `12a_per_factor_pill_check`     = a,
  `12b_composite_pill_count`      = b,
  `12c_regime_amplification_flag` = c_
),
```
Judge 권고 + Governor 동의: **Option X** (downstream hash lookup 호환 우선, v3.8.1 단계에서는 외부 API 변경 최소화 + artifact_validator.sh 오탐 차단 주석 필수).

### A.8 (Reference only, 미변경) — `ax_cand_3rd_member_screening.R` function 인자 `gate_13_verdict`
```r
# v3.8.1 미변경 (호환성 유지)
# 함수 인자명 gate_13_verdict는 historical naming으로 유지.
# 호출자 API 변경 최소화를 위함. 향후 v3.9에서 `gate_16_verdict`로 rename 검토 가능.
```
영향: 호출자 4곳(추정 `pipeline_trigger.sh` / `governor.R` / `ax_promotion_script.R` / test fixture) API 변경 없음.
