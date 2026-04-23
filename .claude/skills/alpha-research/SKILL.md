---
name: alpha-research
description: QEPM Alpha Research Agent 자율 리서치 루프 실행. 주어진 Work Task에서 종목별 기대초과수익 α̂ 생성. Scout의 S0~S5 통합 역할 대체. 공분산/weight 결정 절대 금지 (Hook 강제). 방법론 자율 선택 (classical / ML / RL).
---

# /alpha-research {WT_id}

Alpha Research Agent를 Work Task에 spawn하여 alpha_package.json을 자율 생성.

## Usage

```
/alpha-research WT20260423_001
```

## 동작

1. `qepm/mailbox/worktask/{WT_id}/request.json` 존재 확인
2. Agent tool로 `subagent_type=alpha-research` spawn
3. Agent init prompt: `02_Infrastructure/prompts/alpha_research_init.md`
4. 7-step 자율 파이프라인 실행:
   - Hypothesis intake
   - Candidate factor library
   - Signal engineering
   - Diagnostics
   - Alpha forecast
   - Confidence scoring
   - Alpha package emission
5. 산출: `qepm/mailbox/worktask/{WT_id}/alpha_package.json`
6. status.json → `ALPHA_DONE` 전이
7. Q-Lead에 완료 알림 (SendMessage)

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
