# 낡은 문서 사실 정정안 (H2 감사 2단계 · 2026-11-10 · 직접 고치지 않음 — 줄 단위 수정안)

형식: **지금 문구 → 제안 문구 → 근거**. 줄 번호는 2026-11-10 14:30 작업 트리 기준입니다.

## 1. `.claude/rules/lean-loop.md:44` (자동 로드)
- 지금: `… 타이밍 방어만 — 등급 v3.2 에서 정한 규칙 · 현행 판 v3.3 · 헌장 빈칸 9 A′ · …`
- 제안: `… 타이밍 방어만 — 등급 v3.2 에서 정한 규칙 · 현행 판 v3.4(CR 노치 규칙은 v3.2 그대로) · 헌장 빈칸 9 A′ · …`
- 근거: `06_Registry/grade_v3.json::rules_version = "v3.4"`(rules_version_v34_source: "종합점수 S · 하한 · CR 노치 · 팩터 알파 노치 · OOS 관문은 v3.3 그대로") · 같은 파일 :45 와 CLAUDE.md §등급이 이미 v3.4 다.

## 2. `.claude/rules/pit.md:57–62` '## S0/S1 오버레이 금지' (자동 로드)
- 지금(6줄): S0(가설)/S1(구현) 오버레이 금지 · 'S1 은 EW 20종목 + 15bps + 유동성만' · '오버레이는 S5 Mutation 또는 v6.4 Optimizer/Forge 에서만'.
- 제안(3줄로 교체):
  ```
  ## 오버레이 적용 위치 (v10.01 · 1계층)
  - 충실구현(논문 그대로) 측정에는 논문에 없는 DD/VT/Regime 오버레이를 붙이지 않는다(논문이 국면을 알파 원천으로 쓰면 그 국면만 허용).
  - 오버레이는 처방 · 강화 사슬(P2 방어 엔진 · P4 걸음)에서만, 위 '오버레이 신호 타이밍'(C5) 의무와 함께.
  ```
- 근거: S0~S5 · v6.4 Optimizer/Forge 는 QEPM WT 단계명이다(QEPM-R0-FREEZE 2026-09-25 · CLAUDE.md '구 1계층 고정 격자 강화 = 퇴역 · QEPM WT = 동결'). '종목 20' 은 현 고정 축(≤25종 · CLAUDE.md §축)과도 다르다. 현 루프에 맞춘 같은 금지 취지(측정 단계에 오버레이 섞지 않기)는 남긴다.

## 3. `.claude/rules/pit.md:75–80` '## V6 Gap-Directed 가설' (자동 로드)
- 지금: 'S0 가설에 `expected_role` + `why_now` 필수' · '`.cache/portfolio_gap_vector.json` → 현재 SR/CAGR/MDD gap 확인' · '조건부 IC … as-of 판만(cond_ic_asof_guard.R)'.
- 제안: 첫 두 줄 삭제, 셋째 줄만 '## 조건부 IC 소비(C1/C14)' 절 이름으로 존치:
  ```
  ## 조건부 IC 소비 (C1/C14 · D-E-V6 2026-09-25)
  - 조건부 IC 는 `Usable_Date <= 결정 시점` 판만 쓴다. as-of 판 미제공 시 사용 안 함(현행 `.cache/conditional_ic_matrix.csv` = 전기간 스냅샷 → C1/C14 대상 · 엔진 소비 함수 4종은 `02_Infrastructure/validation/cond_ic_asof_guard.R` 호출부 가드가 가린다).
  ```
- 근거: `.cache/portfolio_gap_vector.json` 을 쓰는 살아 있는 코드 없음(언급 = 미등록 훅 `arm_gen_read_guard.sh` 정규식 · `role_taxonomy_admission_gate.sh` · `unified_agent_guard.sh` 뿐 — H2 감사 §4). 'S0 가설' 은 QEPM 단계. PIT 규칙(조건부 IC as-of)은 살아 있으므로 남긴다.

## 4. `.claude/rules/measurement-graduation.md:33 · :46–47` (경로 트리거 · contracts/** 편집 때마다 적재)
- 지금 :46: `**Graduation tier (불변 — essence Grade A 의 HARD 3종)**: 위 HARD 3종(PORT_t 2.95·oos_retention 0.7·calmar 0.64) — …`
- 제안 :46: `**구 Graduation tier (QEPM 졸업 훅 전용 · 등급 v3.4 의 A 하한이 아님)**: 위 HARD 3종(PORT_t 2.95·oos_retention 0.7·calmar 0.64)은 discovery_graduation_gate.sh 가 QEPM Deployment WT(WT-P*/request.json) 에만 적용한다. 권위 A 하한 = CLAUDE.md §등급(S ≥ 1 · PORT_t ≥ 2.0 · Calmar ≥ 같은 창 KOSPI200 · CAGR ≥ 16% · Sharpe ≥ 0.8 · 시험 창 OOS 관문 · 스윕이면 선택 현실 점검). — …`(뒤 문장 그대로)
- 지금 :33 머리: `- **HARD (block)**: \`portfolio_alpha_t_nw\` ≥ 2.95 … + **\`oos_retention\` ≥ 0.7** … + **\`calmar\` ≥ 0.64** …`
- 제안 :33 머리에 한 구절 덧붙임: `- **HARD (block · 구 졸업 관문 — 등급 v3.4 에서 2.95 는 S 의 정규화 상수 · oos_retention 은 A 관문 아님)**: …`(나머지 그대로 · 창-도달가능성 병기 의무는 살아 있는 보고 규율이라 유지)
- 지금 :47: `**훅 배선 완료 (2026-07-03 …)**: discovery_graduation_gate.sh 가 HARD 3종 … fail-closed 실차단 + sweep-DSR 미산출 block.`
- 제안 :47 끝에 덧붙임: `★대상은 QEPM WT-P 요청뿐(마지막 쓰기 2026-07-06 · QEPM-R0-FREEZE). 1계층 · 2계층 권위 등급은 이 훅을 지나지 않는다.`
- 근거: CLAUDE.md §등급(등급 v3.4 · A 하한 PORT_t ≥ 2.0 · OOS = GRADE-V33-OOS-TEST-WINDOW-CALMAR · 선택 현실 점검 = DSR-GATE-FORM-20261110) · `06_Registry/grade_v3.json` · `constraint_defaults.json::tier_graduation`(0.64 · 2.95 · 2.0 · 16% · 0.8 — 2.95 는 S 식의 분모). 훅 코드: `02_Infrastructure/hooks/discovery_graduation_gate.sh:85–86`(`*/WT-P*/request.json` 만).

## 5. 아직 없는 원장을 가리키는 곳 (문구는 맞다 — 사실 주석만)
H2 감사 1단계 보고의 '확장자 `.json`' 지적은 **철회**합니다(정규식 절단 오탐 — 세 문서 모두 `.jsonl` 로 바르게 적혀 있습니다). 남는 사실은 '파일이 아직 없다' 하나입니다.
- `.claude/skills/research-program/SKILL.md:80` · `.claude/agents/superfan.md:56` · `.claude/agents/superfan-philosophy.md:47` — `06_Registry/round_outcomes.jsonl`
  - 제안(각 줄 끝에): `(2026-11-10 현재 미생성 — 첫 `round.sh close` 가 만든다 · writer = `_lib/round_core/v1/outcomes.R`)`
  - superfan 두 문서는 총괄 통합 중 경로라 손대지 않는 것을 권고 — 대신 SKILL 한 곳만.
- `.claude/skills/research-program/SKILL.md:203` — `06_Registry/mechanism_atlas.jsonl`
  - 제안: `(미생성 — writer = programs/mechanism_atlas.R --ingest · 첫 수록 전엔 파일 없음)`
- 근거: `ls 06_Registry/round_outcomes.jsonl` · `mechanism_atlas.jsonl` = 없음(11-10) · writer 코드 `04_Research/programs/_lib/round_core/v1/outcomes.R:5,16` · `02_Infrastructure/programs/mechanism_atlas.R:30`.

## 6. `CLAUDE.md:7` — 'boot_currency_check.sh C0 파생' (사실 정리만 · 어느 쪽을 고칠지는 총괄)
- 사실: `boot_currency_check.sh` 의 C0(`:95–97`)은 CLAUDE.md Active Version 줄에서 버전 · 모델 · 구조를 파생해 다른 문서와 대조한다 — **그 검사는 존재하고 동작한다.**
- 그러나 `/qvest` 부팅(`.claude/commands/qvest.md:12` → `02_Infrastructure/ops/boot_lean.sh`)은 그 스크립트를 부르지 않는다. 호출자 = `ops/bootstrap.sh` · `ops/health_full.sh`(주간/수동 · 세션 자동 호출 금지) · `hooks/boot_stamp_check.sh`(주석으로만 언급) · 시험 `08_Tests/hooks/test_boot_currency.sh`.
- 그래서 '버전 표기 드리프트가 다음 부팅에서 바로 잡힌다'(boot_currency_check.sh 머리말의 설계 의도)는 현재 거짓이고, 주간/수동 전수 점검에서만 참이다.
- 선택지: (a) CLAUDE.md:7 을 '(`boot_currency_check.sh` C0 파생 · 주간/수동 health_full 에서 검사)' 로 고친다 (b) boot_lean.sh 에 C0 만 가볍게 넣는다(파이썬 블록에서 CLAUDE.md 줄 1회 정규식 · 부팅 줄 1개 · 실측 비용 ≈ 0) — (b) 는 부팅 출력이 바뀐다.

## 7. (참고) 그 밖의 1단계 지적 — 정정 대상 아님
- `CLAUDE.md:105` 'settings.json 13 distinct .sh' — 사실(command 값 기준 13). 부팅 `hooks 14/13 ✗` 는 부팅 계수기의 오탐이었고 이번에 고쳤다(boot_lean.sh · 시험 08_Tests/ops/test_boot_lean_memo.sh H 축).
