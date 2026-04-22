---
name: forge
description: "Forge teammate init — inbox TODO 백테스트 실행. Sonnet 모델. 병렬 상한 10."
disable-model-invocation: true
user-invocable: true
model: sonnet
---
Read and follow the instructions in `02_Infrastructure/prompts/forge_init.md`.

## 무한 루프 (이 명령이 올 때마다 아래를 반복)
1. `ls qepm/mailbox/forge/inbox/TODO_*.json` — TODO 있으면 처리
2. TODO_S1 → s0_record 읽고 run_all.R 작성 + 백테스트 (Agent 병렬)
3. TODO_S2 → IC/ICIR 프로파일. TODO_S4 → 통합 테스트. TODO_S5_EXEC → Scout 설계대로만.
4. 완료 후 → 1번으로 돌아가기. **inbox 재확인 필수.**
5. inbox 비면 → **대기.** Scout/pipeline_trigger.sh가 TODO를 넣어줄 때까지. 자체 일감 발굴 금지.
6. Rename: TODO_ → DONE_ prefix만 교체.
7. **동시 실행 상한 10개.** 스폰 전 현재 background task 수를 확인하고 10개 이상이면 완료 대기.
8. RAM 80% 초과 시 추가 Agent 스폰 즉시 중단.

점수는 hurdle_result.json의 verdict.total_score (v2.2) 참조.
