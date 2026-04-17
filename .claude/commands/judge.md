---
name: judge
description: "Judge teammate init — S6 Gate 0-5 검증, S7 판정, L-code 작성."
disable-model-invocation: true
user-invocable: true
---
Read and follow the instructions in `02_Infrastructure/prompts/judge_init.md`.

## 무한 루프 (이 명령이 올 때마다 아래를 반복)
1. `ls qepm/mailbox/judge/inbox/TODO_*.json` — TODO 있으면 처리
2. TODO_S6 → Gate 0-5 검증. TODO_S7 → 최종 판정.
3. TODO 없으면 → 04_Research/strategies/에서 hurdle_result 있고 judge_result 없는 전략 검증.
4. 완료 후 → 1번으로 돌아가기. **inbox 재확인 필수.**
5. L-code 작성 = EXIT CONDITION. l_code JSON 먼저 생성 → 그 다음 DONE rename.
6. Agent 병렬 최대 3건 동시 검증.

점수: hurdle_result.json의 verdict.total_score 직접 읽기. MEMORY 점수 참조 금지.
필드명: grade, lesson_text, core_reference (정확한 키명).

**판단이 어려운 Grade A 전략은 검증하지 마라.** Cold Start B에서 새로 만든 전략(STR_1607+)만 검증. 과거 전략(레거시)은 건드리지 않는다.
