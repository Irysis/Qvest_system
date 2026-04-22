---
name: kr-inverse-pattern-miner
description: "VALIDATED_HARD_FAIL L-code를 입력받아 반대 방향 가설을 자동 제안. KR 실증 실패 패턴의 역전 메커니즘 탐색."
---

## KR Inverse Pattern Miner (v54)

VALIDATED_HARD_FAIL로 확정된 L-code의 **실패 메커니즘을 역전**하여 새로운 가설 후보를 자동 생성한다.
AX-000 "한계란 없다" 원칙에 따라, 실패 패턴은 반대 방향에서 alpha source가 될 수 있다.

### 호출 방법

- Q-Lead 또는 Scout이 `/kr-inverse` 호출
- 인수: L-code ID (예: `L-161`) 또는 family명 (예: `momentum`)
- 인수 없이 호출 시: 전체 VALIDATED_HARD_FAIL L-code를 스캔하여 미탐색 역전 가설 목록 제시

### 실행 절차

#### Step 1: 실패 패턴 로드

```
1. methodology_memory.md에서 대상 L-code 읽기
2. 필수 추출 필드:
   - family: 실패한 factor family
   - direction: 원래 가설이 기대한 방향 (long/short)
   - mechanism: 왜 실패했는가 (KR 시장 구조적 원인)
   - tags: VALIDATED_HARD_FAIL 관련 태그
   - AX-code: 연결된 Axiom (있으면)
3. .cache/conditional_ic_matrix.csv에서 해당 family factor의 실제 IC sign 확인
```

#### Step 2: 역전 가설 생성

각 실패 패턴에 대해 다음 3가지 역전 유형을 검토:

| 역전 유형 | 설명 | 예시 |
|-----------|------|------|
| **Direction Flip** | 동일 factor, 반대 방향 | L-161 momentum → short-horizon reversal |
| **Conditional Gate** | 동일 factor, 특정 regime에서만 적용 | L-160 defense → defense conditional exposure (CRISIS-only) |
| **Synthesis Pivot** | 실패 factor를 다른 family와 결합 | L-154 low-beta → low-beta + quality (Q07+C19) |

#### Step 3: 가설 템플릿 작성

```json
{
  "source_l_code": "L-161",
  "source_failure": "KR momentum inverse — 12M momentum이 한국에서 음의 IC",
  "inverse_type": "direction_flip",
  "proposed_hypothesis": {
    "name": "KR short-horizon reversal",
    "expected_role": "core_alpha",
    "family": "momentum",
    "sub_family": "reversal",
    "factors": ["MOM_1M_REV", "MOM_3M_REV"],
    "mechanism": "12M momentum 실패의 역전: 한국 개인투자자 과잉반응 → 1-3M reversal premium",
    "core_reference": "Jegadeesh (1990) short-term reversal + Da et al. (2014) overnight returns",
    "lesson_check": "L-161 momentum inverse 실패 확인 → reversal 방향 탐색",
    "why_now": "L-161 VALIDATED_HARD_FAIL로 momentum long 가설 공간 폐쇄, reversal이 유일한 남은 경로",
    "expected_icir": "conditional_ic_matrix에서 MOM_1M_REV IC sign 확인 후 기입"
  },
  "risk_factors": [
    "Reversal도 KR에서 작동하지 않을 수 있음 (L-code 미존재 = 미검증, 아님)",
    "Turnover 과다 (1M reversal → 월 100% TO 가능)"
  ],
  "explore_budget_tag": "Explore_KR_Empirical_10pct"
}
```

#### Step 4: 출력 및 핸드오프

- 파일: `stage_artifacts/kr_inverse_candidate_H_XXXX.json`
- H_XXXX 번호: 기존 H-code 시퀀스에서 자동 할당 (config.R allocate_hyp())
- Scout에게 핸드오프: 생성된 후보를 Scout inbox에 `TODO_S0_INVERSE_H_XXXX.json` 작성
- Scout이 정식 S0 Debate 진입 여부 결정 (자율)

### 역전 매핑 레퍼런스 (v54 기준)

| L-code | 실패 패턴 | 역전 유형 | 제안 가설 |
|--------|----------|-----------|----------|
| L-161 | KR momentum inverse (12M MOM 음의 IC) | Direction Flip | KR short-horizon reversal (1-3M) |
| L-160 | Defense IC-Return decoupling (IC 양수인데 수익 음수) | Conditional Gate | Defense regime-gated exposure (CRISIS-only 노출, 정상 시 현금) |
| L-154 | Low-beta BAB standalone fail | Synthesis Pivot | Low-beta + quality synthesis (beta + Q07 + C19 composite) |
| L-132/135 | Value EP standalone fail | Direction Flip + Conditional | Value-Growth barbell (호황 growth + 불황 value) |
| L-133/134/139 | Quality profitability standalone fail | Synthesis Pivot | Quality as overlay in multifactor (QMJ + momentum + value) |
| L-136/140 | Defense Q07+D25 combo fail | Conditional Gate | Defense conditional + vol-managed (Barroso-Santa Clara 2015) |

### Explore Budget 규칙

- KR-Inverse 가설은 **Explore 버킷 10% 전용 예약**으로 배치
- families.json에 `explore_kr_inverse` 태그 자동 부여
- 논문 근거가 약해도 AX-000 근거로 S0 Debate 진입 허용 (단, kr_empirical_check는 정상 채점)
- 동일 L-code에서 역전 가설 **최대 2건**까지만 (조합 폭발 방지)

### 사용 제한

- Scout과 Q-Lead만 호출 가능 (Forge/Judge/Governor는 호출 불가)
- 생성된 가설이 AX-003/004/005 scope 내이면 경고 표시 (EXCLUSION 조건 확인 필수)

### 참조 파일

- `methodology_memory.md` — L-code 정본 (VALIDATED_HARD_FAIL 검색)
- `.cache/conditional_ic_matrix.csv` — KR IC sign 확인
- `.cache/portfolio_gap_vector.json` — 현재 gap 확인 (역전 가설의 expected_role 결정)
- `02_Infrastructure/config.R` — allocate_hyp()
- `CLAUDE.md ## Axioms` — AX-000/003/004/005 scope 확인
