---
name: scout
description: "Scout teammate init — S0 가설(plan mode), S3 직교성, S5 mutation 설계"
disable-model-invocation: true
user-invocable: true
---
Read and follow the instructions in `02_Infrastructure/prompts/scout_init.md`.

## 작업 분기

### A. inbox TODO 처리 (plan mode 불필요)
1. `ls qepm/mailbox/scout/inbox/TODO_*.json` — TODO 있으면 처리
2. TODO_S3 → S3 직교성 분석. TODO_S5_DESIGN → mutation 설계.
3. 완료 후 → inbox 재확인.
4. Rename: TODO_ → DONE_ prefix만 교체.

### B. S0 가설 설계 (plan mode 필수)
TODO_S0_GAP 또는 가설 설계가 필요한 경우:
1. **plan mode 진입** — 코드 실행/파일 수정 금지. read-only 탐색만.
2. 탐색:
   - `.cache/portfolio_gap_vector.json` → sleeve_needs, gap 확인
   - `.cache/conditional_ic_matrix.csv` → 고 ICIR + C19 저상관 팩터
   - `methodology_memory.md` → L-code 교훈, 실패 팩터 회피
   - `CLAUDE.md ## Axioms` → 공리 범위 내 가설 금지
3. plan 파일에 가설 설계 작성:
   - factor_id, hypothesis, economic_rationale
   - expected_role (sleeve_needs 일치 필수)
   - why_now (gap 수치 근거)
   - core_reference (학술 논문)
   - lesson_check (관련 L-code)
   - factors (2~3 팩터 블렌드 권장, 단독 팩터 지양)
   - overlay_plan (DD/VT/Regime 등)
4. **ExitPlanMode** → Q-Lead가 PG0 기준으로 승인/거부
5. 승인 시: allocate_str + sg_init + s0_record 작성 + Forge inbox TODO_S1
6. 거부 시: 피드백 읽고 재설계 → plan 재제출

### C. inbox 비면 대기.
