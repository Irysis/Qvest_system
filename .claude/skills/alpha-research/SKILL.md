---
name: alpha-research
description: QEPM Alpha Research Agent 자율 리서치. theme만 주어도 가설 자동 발굴(Step 0) + Factor DB 종속성 없음 — 기존 팩터 재사용 + 신규 팩터 직접 설계 모두 허용. Scout의 S0~S5 통합 역할 대체. 공분산/weight 결정 절대 금지 (Hook 강제). 방법론 자율 선택 (classical / ML / RL).
---

# /alpha-research {WT_id}

Alpha Research Agent를 Work Task에 spawn하여 alpha_package.json을 자율 생성.

## Usage

```
/alpha-research WT20260423_001
```

## 동작

1. `qepm/mailbox/worktask/{WT_id}/request.json` 존재 확인
2. `hypothesis_title`이 NULL이면 **Step 0 Hypothesis Discovery 자동 활성화**
3. Agent tool로 `subagent_type=alpha-research` spawn
4. Agent init prompt: `02_Infrastructure/prompts/alpha_research_init.md`
5. **8-step 자율 파이프라인** 실행:
   - **Step 0 (신규, 조건부)**: Hypothesis Discovery — PG0 gap + L-code + 문헌 survey로 가설 자동 발굴
   - Step 1: Hypothesis intake
   - Step 2: **Factor Sourcing** — DB 재사용 / DB 변형 / **신규 팩터 직접 설계** / alt data 자율
   - Step 3: Signal engineering (기존 DB 팩터 + 신규 자체 계산 팩터 혼용)
   - Step 4: Diagnostics (IC / ICIR / Harvey t / DSR)
   - Step 5: Alpha forecast
   - Step 6: Confidence scoring
   - Step 7: Alpha package emission
6. 산출: `qepm/mailbox/worktask/{WT_id}/alpha_package.json`
7. status.json → `ALPHA_DONE` 전이
8. Q-Lead에 완료 알림 (SendMessage)

## 가설 발굴 모드 (Step 0)

**Trigger**: request.json의 `hypothesis_title == null` + `theme != null`

**자율 프로세스**:
- `.cache/portfolio_gap_vector.json` 분석
- `methodology_active.md` L-code 실패 패턴 survey (kr-inverse-pattern-miner)
- `mcp__jina / mcp__paper-search` 문헌 조사
- Factor DB gap (`daily_factor_db_state.md` 활용률 낮은 family) 식별
- 복수 가설 후보 3~5건 생성 → 1 선택 + 대안 기록
- `request.json.hypothesis_title` 자동 주입 + `hypothesis_source = alpha_agent_discovered` 기록

## Factor Sourcing 자율성 (Factor DB 비종속)

Alpha Agent는 다음 4가지 source 중 **자율 선택**:

| Source | 방식 | 예시 |
|---|---|---|
| A. `db_existing` | `load_month_factors()` Factor DB 288개 | Q07 / B/P / ROE |
| B. `db_derived` | DB 팩터 변형 | residualization / ratio |
| C. `new_designed` | 자체 설계 (DART/flow/FRED) | Cash_Flow_Growth_Stability |
| D. `alt_data` | Alternative (승인 시) | (현재 승인 없음) |

각 팩터 `factor_specs`에 `source` 필드 필수.

## 제약

- **Common Charter 8원칙** 강제 (`worktask/common_charter.md`)
- **역할 경계** Hook 강제 (`agent_role_guard.sh`)
- **Work Task 순서** Hook 강제 (`worktask_sequence_enforcer.sh`)
- **Red Flag 자동 감지** (`red_flag_detector.sh`)
- **PIT C1~C15** 전체 준수

## 완료 후

Q-Lead가 Risk Agent spawn을 트리거:
```
/risk-research WT20260423_001
```

## 실패 시

Rule 1 STOP 조건:
- Look-ahead 의심
- Signal monotonicity 붕괴
- Subperiod instability
- Cost 대비 alpha 미미

→ `status.json` phase=ABORTED + challenge_flags 기록 + Q-Lead 알림
