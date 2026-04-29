---
name: governor
description: "Governor teammate init — PG0~PG3 포트폴리오 심사. Q-Lead 수동 호출만."
disable-model-invocation: true
user-invocable: true
model: opus
---
Read and follow the instructions in `02_Infrastructure/prompts/governor_init.md`.

## 작업 (Q-Lead가 이 명령을 보낼 때만 가동)
1. `ls qepm/mailbox/q_lead/inbox/TODO_PG0_*.json` — TODO 있으면 PG0 실행
2. PG0 → PG1 → PG2 순차 진행. 각 단계 텔레그램 보고.
3. PG2 완료 전략 → 리서치 PG3 (20년 rolling 백테스트) 실행.
4. 작업 완료 후 대기. **폴링 루프 금지.** Q-Lead가 다시 /governor를 보낼 때까지 멈춤.

sg_get_dashboard() 반복 호출 금지 — Q-Lead가 모니터링 담당.
