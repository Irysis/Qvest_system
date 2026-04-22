# Admission Rule v3.8.1 — Gate 17 ACTIVE 승격 + Gate ID 정합 Patch

**발효 일자 (PATCH DRAFT)**: 2026-04-23 (Session 69)
**이전 버전**: v3.8 draft (`admission_rule_v38_draft.md`, 2026-04-19 Session 68 Day 2)
**변경 성격**: **Patch (minor) — Gate 17 ACTIVE 승격 + R 코드 gate_id 상수 정정 사양서**
**작성자**: Judge (Session 69 Task, Q-Lead Option 1 승인)
**Governor review 요청**: SendMessage 후 기록 예정

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

**정정 사양서**:

| 파일 | 현재 `gate_id` 상수 | v3.8.1 정정 값 |
|------|-----|---------------|
| `02_Infrastructure/validation/signal_portfolio_translation_audit.R:192` | `"Gate 13 (Signal-Portfolio Translation Failure)"` | `"Gate 16 (Signal-Portfolio Translation Failure)"` |
| `02_Infrastructure/validation/poison_pill_ic_return_audit.R:234` | `"Gate 12 (Poison Pill IC-Return)"` | `"Gate 17 (Poison Pill IC-Return Decoupling)"` |
| `02_Infrastructure/validation/ax_cand_3rd_member_screening.R:161` | `"Gate 14 (AX_CAND 2/3 → 3rd Member Screening)"` | `"Gate 18 (AX_CAND 2/3 → 3rd Member Screening)"` |

**정정 방법** (Judge 권고, Forge/Architect 실행):
1. 단순 문자열 치환. Sub-gate 내부 명명("12a/12b/12c")은 hash key로 사용되는 경우 v3.8.1 내부 naming policy에 따라 유지 또는 `17a/17b/17c` 재명명 결정 필요 (`poison_pill_ic_return_audit.R:239~243` `sub_gates` list key 4곳).
2. artifact JSON의 `sub_gates` 하위 key가 downstream에서 hash lookup되는 경우 변경 전후 호환성 체크 필요. Judge 권고 **Option X** (보수): 상위 `gate_id`만 변경, sub-gate key는 "12a/12b/12c" 유지하되 docstring에 "historical, v3.4 내부 명명" 주석 추가.
3. 변경 후 `artifact_validator.sh`의 Gate ID regex 검증 (v3.8 draft §7 hook integration)이 "Gate 16" / "Gate 17" / "Gate 18" 명명을 기대하므로 호환 확인.

**영향**:
- v3.8 draft §7 "hook integration" 조항 (Gate 13/14 거부 로직)과 정합
- Gate ID 충돌(v3.7 Gate 14 vs R 코드 Gate 14) 해소
- 기존 테스트 fixture가 `gate_id = "Gate 12"`를 기대한다면 fixture 갱신 필요

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

## 3. 실행 순서 (Q-Lead 최종 sign-off 후)

1. **Governor review** — 본 patch 수신 후 portfolio_gap_vector v1.0.7 명명 동기 확인. 불일치 시 Judge-Governor 협의.
2. **Forge/Architect 코드 수정** — §1.2 사양서 기준 3 파일 `gate_id` 상수 정정. sub-gate hash key 정책 결정 (Option X 보수 권고).
3. **Hook validator 갱신** — `artifact_validator.sh`의 Gate 16/17/18 regex 활성화.
4. **기존 artifact 재생성 또는 annotation** — 기존 `poison_pill_ic_return_audit.json`에 `schema_version: "v1.0-pre-v3.8.1"` annotation 추가 (Option A) 또는 재실행으로 갱신 (Option B).
5. **v3.8 draft 본문 직접 업데이트** vs **v3.8.1 독립 유지** — Q-Lead 결정. 추천: v3.8 final 승격 시 본 patch 내용을 본문에 병합하여 v3.8 final로 정규화 (v3.8.1 patch는 히스토리로 archive).

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
- **Approved by**: team-lead (Q-Lead) — "v3.8.1 patch Option 1 승인"
- **Pending**: Governor review + Forge/Architect R 코드 정정 + Q-Lead 최종 sign-off
- **Next**: Governor SendMessage review 요청 (본 patch + R 코드 명명 정정 사양서 전달) + Retroactive Audit 설계서 초안

---

## 부록 A — R 코드 정정 diff 미리보기

### signal_portfolio_translation_audit.R:192
```diff
-    gate_id                   = "Gate 13 (Signal-Portfolio Translation Failure)",
+    gate_id                   = "Gate 16 (Signal-Portfolio Translation Failure)",
```

### poison_pill_ic_return_audit.R:234
```diff
-    gate_id         = "Gate 12 (Poison Pill IC-Return)",
+    gate_id         = "Gate 17 (Poison Pill IC-Return Decoupling)",
```

### ax_cand_3rd_member_screening.R:161
```diff
-    gate_id              = "Gate 14 (AX_CAND 2/3 → 3rd Member Screening)",
+    gate_id              = "Gate 18 (AX_CAND 2/3 → 3rd Member Screening)",
```

### poison_pill_ic_return_audit.R sub_gates (line 239~243, Option X 보수 권고)
```r
# Option X (보수, 권고): 유지하되 주석 추가
sub_gates = list(
  `12a_per_factor_pill_check`     = a,   # historical naming, v3.4 Gate 12 기준
  `12b_composite_pill_count`      = b,
  `12c_regime_amplification_flag` = c_
)

# Option Y (적극): 재명명
sub_gates = list(
  `17a_per_factor_pill_check`     = a,
  `17b_composite_pill_count`      = b,
  `17c_regime_amplification_flag` = c_
)
```
Judge 권고: **Option X** (downstream hash lookup 호환 우선, v3.8.1 단계에서는 외부 API 변경 최소화).
