# 감사 레인 K — 사후 지식 축적 · 재귀적 개선 고리 (2026-11-10)

## 1. 지식의 흐름 지도 (코드로 추적 — 쓰는 쪽 / 설계 시점에 실제로 읽는 쪽)

| 결과가 생기는 곳 | 기록(저장소 · writer) | 설계 시점 reader | 판정 |
|---|---|---|---|
| 충실구현 1편 | L-code `stage_artifacts/l_code/paper_replication/*`(run_paper_replication.R:1020 emit — **모든 측정마다** · 전기간 SR · 등급 포함 · epoch 없음) · module_catalog(B+) · 레인 저널 `.cache/reinforce_auto_log.jsonl` · 행동 카드 · 재료 큐 | hypothesis_index(수동 lookup · 세션 · 어드바이저) · 상설 판 스캔 → 기저 풀(`rc_p4_base_pool`) | 기저 풀 경로는 닫힘. 논문 **선택 순서**(`rf_next_paper_pick.py` · "재정렬 금지")로는 되먹임 0 |
| 프로그램 라운드 | 결과 원장 `06_Registry/round_outcomes.jsonl`(register.R:168 `rc_close`) + 등록부 | `rc_outcomes_md`(라운드 설계 시 SKILL §0-1 수동 명령) · `rc_p4_design_input` §5 · §6 | 닫힘(단 원장 0줄 — 닫힌 라운드 0) |
| 강화 사슬 걸음 | 걸음 원장 `chain_steps.jsonl`(p4.R `.rcp4_append`) | 같은 사슬 설계 입력 §4 · `rc_p4_generator_review` · `rx_generator_scorecard.R`(E2) | **다른 사슬의 걸음은 생성기에 안 간다**(§4 = 이 사슬만) |
| 강화 사슬 닫기 | 결과 원장(p4.R `rc_p4_close`) · finalize.json(전기간 · 사람 쪽) | 설계 입력 §6(최근 5줄) · 생성기 검토 · `rxg_revise` evidence 검사 | 닫힘 |
| 라운드 P4 단계의 L-code | 측정 칸마다 L-code(p4 · standing · measure_cell 이 `QVEST_RP_NO_LCODE` 안 켬) | hypothesis_index — 선택 보정 전 전기간 등급으로 색인 | **오염 경로**(패치 P5) |
| 2계층 시도 | 원장 L2 `reinforce_ledger_l2.json` | rf_l2_lib.R(2계층 자체) | 1계층 생성기 reader 0 |
| 어드바이저 측정 | run_paper_replication 경유 L-code | hypothesis_index | 위와 같음 |
| BOOK 트래킹 | live_track · book_registry | 1계층 설계 reader 0 | (BOOK 레인 소관) |
| 판단 원장 | `q_judgment_ledger.json`(Superfan) | 등록 · 닫기 영수증 검사(p4.R · register.R) | 영수증 확인용 — 설계 내용 입력 아님 |
| timing_defense_evidence | `06_Registry/timing_defense_evidence.json`(grade_v3 writer) | 등급 CR 노치(grade_v3.R) | 판정 입력 — 설계 입력 아님(정상) |
| 주간 요약 | `weekly_digest_*.md`(증류 레인) | **reader 0**(설계 입력 · 생성기 · 등록 어디에도 안 읽힘) | 쓰기만 하는 저장소 |
| 메모리(Claude) | 세션 기억 · `06_Registry/memory_inbox/` | 세션(Q)만 | 무인 생성기는 못 본다(정상 · τ_D) |
| `portfolio_gap_vector.json` | gap_vector_steering(구 governor) · 11-01 쓰기 | QEPM 동결 경로 · friday_alpha_snapshot · bootstrap WARN | v10.2 설계 reader 0 |
| `.cache/failure_revival_flags.json` | (보관된) failure_revival_monitor | WARN_11 · harvester 변동부 | writer 0(보관) — 읽으려는데 아무도 안 쓰는 저장소 |
| `06_Registry/distilled_knowledge.json`(DIST) | (보관된) cluster_extractor · distilled.R | hypothesis_index (d) — **조회 상위 30행을 독점**(실측) | writer 0 · reader 는 남음 → 수리(정렬) |
| `positive_context.json` | lcode_harvester(변동부) | 주입 훅(v10.2 변동부 미주입) | reader 0 |

**핵심**: (writer 0 · reader 있음) = DIST 카드 · revival flags. (reader 0) = weekly digest · gap vector · positive_context · L2 원장(1계층 쪽). 생성기(P4 처방 에이전트)는 `design_input.md` 하나만 본다(step.md §입력 "그 밖의 파일 · 기억 · 사전학습 지식을 성과 근거로 쓰지 않는다") — 즉 생성기에게 닿는 과거 지식 = 같은 사슬 걸음 + 결과 원장 최근 5줄 + 열린 탐침뿐.

## 2. 재귀적 개선이 실제로 닫히는가

- (a) 닫은 사슬 교훈 → 다음 사슬 설계 입력: **예(코드 경로 실재 · 시험 L1 · L2)**. 단 두 가지 끊김: ① 이어받기 표시 `rc_probe_consume` 호출처 0(열린 탐침이 줄지 않고 쌓임 — L8c) ② 결과 원장 1줄 손상 · 교훈 속 '등급 C' 표기 하나가 **모든** 설계 입력 · 생성기 검토를 영구 정지(L7c · L10 — 쓰기 검사와 읽기 검사 비대칭 · 추가 전용).
- (b) 과거 negative 의 자동 유입: **아니오**. 설계 입력에 hypothesis_index 절이 없고 생성기는 다른 파일을 못 본다. DESIGN_p1.md 템플릿의 lookup 한 줄이 유일(수동 · Q 세션). ★게다가 hypothesis_index 판정 라벨은 **전기간 등급**(τ_D 뒤 포함)이라 그대로 생성기에 넣으면 정보 경계 위반 — 넣을 수 있는 것은 보는 창 원장(결과 원장 · 걸음 원장)뿐. 이번 수리로 그 둘이 조회 원천 (h) 가 됐다.
- (c) 충실구현 결과 → 우선순위: 기저 풀(상설 · 등급 B+)은 닫힘. 다음 논문 선택은 큐 순서 고정(재정렬 금지) — 같은 계열 F 가 이어져도 순서 불변. 레인 C 소관 · 결정 사항(§8).
- (d) 생성기 개정 근거: `rxg_revise` 는 근거 = 결과 원장 round_id ≥ 1 + 철학 영수증을 기계 검사(L9). **언제 개정하는가**는 정의 없음(검토 `p4-generator-review` 는 수동). 이번에 계기 `unreviewed_closed_chains`(현 판 이후 닫혔는데 개정 근거로 안 쓴 사슬 수)를 추가 — 문턱 숫자는 만들지 않았다(근거 없음).
- (e) 같은 실패 반복 방지: 사슬 안 = 설계 입력 §4 기각 사유 + 채택 규칙 기계 판정. 사슬 사이 = 없음(패치 P2). 성적표 `rx_generator_scorecard.R::repeat_fail` 은 같은 사슬 안만 센다.

## 3. 수리(소유 범위)

| 파일 | 결함 · 원인 | 수리 | 검증 |
|---|---|---|---|
| tools/hypothesis_index.R 보충 스캔 | corpus 정체(11-07 이후 수확 0) 동안 새로 철회 표식 단 원본 L-code 를 직접 파싱해 **다시 색인**(invalidated_lcodes 는 corpus 에만) | `.hi_raw_invalid` = 정본 `lcode_validity.py check` 호출(50개씩) · 실패 시 판정 필드 존재 = 제외(보수) · coverage 에 basis | I1 · I2 · I3(돌연변이 — 거르는 줄 삭제 시 재색인) |
| 같은 파일 원천 | v10.2 학습 원장이 조회 원천에 없음 | (h) = 결과 원장(RO_ · ROUND_NOISE/SIGNAL/CLOSED · 서명에 epoch) + 걸음 원장(P4S_ · STEP_ACCEPT/REJECT · 사유 코드만 · 수치 없음) + stale 감시 | I4a~d · I5 |
| 같은 파일 교체 쓰기 | `file.remove` 후 rename → 병렬 lookup 이 '인덱스 없음'으로 멈추는 창 | 덮어쓰기 rename 먼저(Windows 실측 TRUE) · 실패 폴백에서만 삭제 · 읽기 쪽 0.25초×8 대기 | I8 |
| 같은 파일 병렬 재빌드 | 조회 = 공유 등록부 쓰기 · 동시 재빌드 | `<index>.rebuild.lock`(dir.create) · 못 잡으면 기존 인덱스로 응답 · 600초(빌드 실측 57초 ≈ 10배) 넘은 잠금만 회수 · `HI_NO_AUTO_REBUILD=1` · CLI `--no-rebuild` | I6a · I6b · I7 |
| 같은 파일 정렬 | DIST 퇴역 뒤에도 DIST 우선 → momentum · defense · regime overlay · dividend 상위 30행이 전부 옛 DIST(실측) · 기기 이관 mtime 로 4~5월 WT 30건이 IN_PROGRESS | `axiom_engine_status.promotion_enabled=false` 면 날짜 순 · 진행 중 WT 표식은 맨 뒤(상태 파일 없으면 구 동작) | I9 |
| 같은 파일 속도 | stale 검사 `file.info` 1,945 OneDrive 파일 12.7초 · 항목별 이중 루프 | `extra_cols = FALSE`(2.6초) · haystack 벡터화(결과 동치 I10) | lookup 34초 → 6.5초(실측) |
| 같은 파일 CLI | `lookup regime` 부가 출력 파싱 오류 보고(E2: `unexpected input in "LED_NEG %d · PASS %d ·"`) — 4개 로캘 · 2개 셸에서 **재현 안 됨**. 원인 추정 = CLI 블록을 떼어 `Rscript -e` 로 돌릴 때의 비ASCII 인자(저장소 기지 함정) | CLI 블록 코드 줄 ASCII 전용(`·` 등) | I11a · I11b(돌연변이) · I11c(실행 종료 0 · 오류 없음) |
| ops/cleaner_distill_lib.R materials | 퇴역 뒤에도 §2 공리 · §3 DIST 초안을 요구 → 에이전트가 집행 안 될 초안을 매주 작성 · v10.2 학습 고리가 재료에 없음 | §1b 학습 고리(계기 + 열린 탐침) · 퇴역이면 §2/§3 한 줄 | test_scn_knowledge_distill D1~D4 · 기존 test_cleaner_distill 25/25 |
| ops/cleaner_distill_run.sh 프롬프트 | 의무 절 = 공리 사이클 | 의무 절 = 학습 고리 · ② 퇴역이면 건너뜀 | D5 · bash -n |
| memory/knowledge_loop_metrics.R(신규) | '나아지는가' 계기 없음 | 주별 닫힌 라운드 · 사슬 · 새 탐침/이어받음 · 상설 자격 · 사전 감사 1차 통과율 · 충실도 1회 통과 + 스냅샷(열린 탐침 · 연속 잡음 · 개정 대기 사슬) · 허용 열 목록 가드 · 손상 줄 경고. 사슬 걸음 지표는 `rx_generator_scorecard.R` 정본(중복 제거 · 총괄 지시) | K1a~f |
| 문서 3종 | 보관 스크립트를 부르는 절차 문구 | axiom-engine.md 첫 절(처분 · 남은 것 · 보관 · 되살리기) · axioms.md 처분 블록 · cleaner SKILL §② 학습 고리 의무 절 + 공리/DIST 절 사료 표시 | 문서 — 시험 대상 아님 |

운영 실측(계기 첫 출력): 사전 감사 1차 통과율 W43 5/6 · W44 6/6 · W45 12/15 · **충실도 감사 1회 통과 W43 0/8 · W44 0/6 · W45 1/12** · 닫힌 라운드 · 사슬 0 · 상설 판정 0.

## 4. 못 고친 결함 — 패치 제안(round_core = E1 소유 · 읽기 전용)

- **P1 원장 독살(L10)** `v1/outcomes.R:51` `rc_outcome_record` 의 τ_D 검사 옆에 `.rcp4_assert_clean` 과 같은 등급 표기 검사(`(등급|Grade|grade)\s*[ABCF](?![A-Za-z])`)를 추가 — 지금은 쓰기는 통과 · 읽기(`p4.R:64`)는 멈춤 → 추가 전용 원장 한 줄이 설계 입력 · 생성기 검토를 영구 정지.
- **P2 사슬 사이 기억** `v1/p4.R::rc_p4_design_input` §4 뒤에 "§4b 다른 사슬의 같은 블록 유형 걸음(판정 · 사유 코드 · 가설 1줄 · 수치 없음)" — 소스 = `rc_p4_generator_review(root, out=NULL)$table` 또는 `rxg_scorecard(...)$steps` 를 block_type 으로 걸러 최근 N줄(N = 사슬 판 `budget.max_steps` 재사용 — 새 숫자 없음).
- **P3 이어받기 자동화(L8c)** `rc_p4_step_open(..., probe_ref = NULL)` 과 register.R 등록에 `--consumes <ref>` 인자 — 있으면 `rc_probe_consume(ref, chain_id/round_id, rc_outcomes_path(root))`. 생성기 출력 JSON 에 `probe_ref`(선택) 칸.
- **P4 τ_D 날짜 표기(L6c)** `v1/util.R:69 rc_after_tau_leaks` 가 `YYYY-MM[-DD]` 만 잡는다 — `20(2[3-9]|[3-9][0-9])\s*년` · `20\d{2}[/.](0[1-9]|1[0-2])` · `'2[3-9]년` 추가(τ_D 연도 비교). 같은 함수가 설계 입력 검사에도 쓰이므로 한 곳 수리로 양쪽.
- **P5 측정 칸 L-code 오염** `p4.R:574 rc_p4_runner_default` · `standing.R:646` · `measure_cell.R:24` 에 `Sys.setenv(QVEST_RP_NO_LCODE = "1")`(칸 교훈 정본 = 결과 원장 · 걸음 원장) — 지금은 걸음 · 기준 칸마다 선택 보정 전 전기간 등급 L-code 가 hypothesis_index 에 쌓인다.
- **P6 손상 복구(L7c)** 결과 원장 손상 줄 격리 도구(`rc_outcomes_quarantine(path)` — 깨진 줄을 `.quarantine.jsonl` 로 옮기고 원장에 `kind=quarantine` 1줄) — 지금은 멈추기만 하고 되돌릴 절차가 없다.

## 5. 업데이트 누락 감지

| 산출물 | 생산자 | 주기 | 신선도 검사 | 소비자 | 낡았을 때 |
|---|---|---|---|---|---|
| `.cache/lcode_corpus.json` | lcode_harvester.py(주간 스윕 · run_alpha_search · bootstrap=health_full) | 주 1(스윕 — 이 PC 0회 · 11-07 노트북) | hypothesis_index 보충 스캔 · WARN_1 | hypothesis_index · knowledge_index | 보충 스캔이 원본 직접 파싱(이번 수리로 철회 표식도 거름) |
| `06_Registry/hypothesis_index.json` | lookup 인라인 재빌드 · build | 조회 때 | `.hi_stale_check`(원천 mtime · (h) 포함) | 세션 lookup · 어드바이저 · DESIGN_p1 | 자동 재빌드(57초) · 잠금 중이면 기존 판 |
| `round_outcomes.jsonl` | round_core close · p4-close | 라운드마다 | 없음(손상 = 판정 경로 정지 · 계기 경고) | 설계 입력 · 생성기 검토 · rxg_revise | 0줄 = '닫힌 라운드 없음' 문구 |
| `.cache/cleaner_pending.json` | weekly_cleaner_sweep.R | 토 09:00(이 PC 미실행 · 11-07 노트북 실행) | bootstrap 7일 게이트(health_full) · 증류 gate | 증류 레인 | 증류 레인 gate rc 10(할 일 없음) — 아침 면 표시 없음(미확인) |
| weekly digest | 증류 레인 | 주 1 | 없음 | reader 0 | 무영향 |
| 지표(계기) | knowledge_loop_metrics.R | 호출 때 | 손상 줄 경고 | 증류 재료 §1b · (모닝 레인 예정) | 0 행도 표에 남김('안 돌았다'가 보인다) |

## 6. 속도

- 조회 lookup(읽기 전용): 34.3초 → 6.5초(stale 검사 `file.info` 26.1→7.6초 · 매칭 벡터화). 상위 소모: ①stale 검사 file.info(OneDrive 1,945 L-code) ②재빌드 57.3초(alpha_search 657 폴더 · WT 299 폴더 · corpus 4MB) ③구 이중 루프.
- 남은 단축안(판정 불변): (e) WT 원천 제외(QEPM 동결) · 재빌드를 레인 쓰기 직후 1회로 옮기고 조회 기본을 읽기 전용으로(결정 §8-2).
- 시험: knowledge_loop 2.9초 · knowledge_index 5.6초 · knowledge_distill 8.6초.

## 7. P/L 우상향 관점 최대 제약

1. **생성기가 과거를 거의 못 본다** — 설계 입력 = 같은 사슬 + 결과 원장 5줄. 사슬 사이 기각 기억 · 보는 창 negative 지도 없음 → 같은 블록 · 같은 기전 재시도 비용(걸음 = 전체 측정 1회).
2. **고리가 아직 0회 돌았다** — 결과 원장 0줄 · 닫힌 라운드 0 · 상설 판정 0. 충실도 1회 통과 1/12(W45): 재료(기저) 공급 쪽이 병목. 고리의 품질보다 고리에 들어오는 엔진 수가 먼저다.
3. **지식 원장의 정보 경계 혼합** — L-code · hypothesis_index 라벨이 전기간 등급 · epoch 없음(J5). 그대로는 처방 입력으로 못 쓴다 → 보는 창 원장(결과 · 걸음)으로 지식 축을 옮겨야 한다(이번 (h) 가 첫걸음).

## 8. 도훈 결정이 필요한 것

1. 생성기에 사슬 사이 기억(P2)을 넣을지 — 권고: 넣는다(보는 창 판정 · 사유 코드만 · 수치 없음).
2. hypothesis_index 조회 기본값 — (가) 지금처럼 조회가 재빌드(공유 등록부 쓰기) (나) 조회는 읽기 전용 · 재빌드는 레인 쓰기 직후/주간 1회. 권고 (나).
3. 다음 논문 선택에 충실구현 결과 되먹임(같은 계열 연속 F 시 후순위) — 큐 순서 고정 원칙(lean-loop) 변경이라 도훈 권한. 권고: 보류(재료 공급량이 먼저).
4. 예약 작업 MonthlyDistill 해제와 함께 memory/ 죽은 가지 삭제(dead tsv).

## 9. 바꾼 파일 · 시험

- 수정: `02_Infrastructure/tools/hypothesis_index.R` · `02_Infrastructure/ops/cleaner_distill_lib.R` · `02_Infrastructure/ops/cleaner_distill_run.sh` · `.claude/skills/cleaner/SKILL.md` · `02_Infrastructure/docs/rules/axiom-engine.md` · `.claude/rules/axioms.md`
- 신규: `02_Infrastructure/memory/knowledge_loop_metrics.R` · `08_Tests/scenarios/test_scn_knowledge_loop.R`(23/23 · GAP 8) · `08_Tests/scenarios/test_scn_knowledge_index.R`(21/21) · `08_Tests/scenarios/test_scn_knowledge_distill.sh`(8/8)
- 회귀: test_hypothesis_index_paper_lane 17/17 · test_qepm_advisor_contract 140/140 · test_lcode_cell_relabel 23/23 · test_cleaner_distill 25/25
- 손대지 않음: weekly_cleaner_sweep.R(죽은 후보 순회 블록은 등록 시험 2종과 묶여 있어 dead tsv 로 일괄 삭제 제안) · round_core · run_all_hooks.sh
- 미확인: E2 파싱 오류의 정확한 재현 조건 · 노트북의 예약 작업 실행 이력 · 증류 레인이 다음 토요일 실제 산출에 §1b 를 옮기는지(LLM 실행 안 함)
