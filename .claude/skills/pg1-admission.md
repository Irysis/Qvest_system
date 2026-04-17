---
name: pg1-admission
description: "PG1 후보 입성 심사 시 적용 — Antipattern, LOO, Role Honesty, ADMIT/REJECT"
---
## PG1 Candidate Admission

### 호출
```r
admit <- pg1_admission("V7_ALLWEATHER_001", candidate_id, validated_role, gap)
```

### 3중 검증
1. **Antipattern 13종** (`antipattern_detector.R`): 과적합, OOS 열화, MDD 증폭, TO 극단, IC 퇴화 등
2. **LOO 4종** (`loo_validator.R`): GFC(2008-09), COVID(2020 H1), RATE(2022) 제외 검증 + regime/subperiod/sleeve
3. **Role Honesty Audit** (`role_honesty_audit.R`): 역할 위장 탐지

### 판정
| 결과 | 조건 | 경로 |
|------|------|------|
| **ADMIT** | 3중 통과 | → PG2 |
| **DEFER** | LOO 실패 | → S5 재순환 |
| **REJECT** | Critical antipattern 또는 role dishonesty | → ARCHIVE |

### Family 집중도
한 family max 35%. 초과 시 DEFER.
