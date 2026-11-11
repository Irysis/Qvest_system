# P1S01 사전등록 초안 격리 교차 점검 v2

- 점검자: 격리 교차 점검(서브에이전트 · v1 점검과 같은 정보 경계). 이 판의 설계 · 구현에 참여하지 않았고 측정 결과를 보지 않았다. 기술 점검만 했다(판단 · 철학 정렬은 다른 감독 몫). 점검 시각 2026-11-11 14:16~14:45.
- 점검 종류: 변경분 점검. v1 점검 3절의 'R-3 을 반영해 `pins.files` 를 더하면 사양 md5 가 바뀐다' 경우라 v1 항목 1(무결성) · 7(시험 · 등록 조건) · 8(정기 실행)을 다시 재도출했다.
- 대상(md5 앞 8자리)
  - 판 폴더: `prereg_draft.json`(draft_version 2 · d7720f29) · `prereg_draft.md`(7c4a292c) · `drafts.json`(530ccdef · v2 review = null) · `round_spec.json`(bdb8b98d) · `specs/P1S01_E2_C0.json`(fd9a012f) · `specs/P1S01_E3_RX0.json`(398e153c) · `standing_rules.md`(82d3597f) · `DESIGN.md`(d0116189) · `behavior_card_cfg_at_prereg.json`(6a2a1d21)
  - 대조 기준 v1: `git show 77f8ab831:…/prereg_draft.json`(029bcae4 · 그 안 `spec` = 사양 52d8eecc) · `…/prereg_draft.md`(465aa0ed) · 점검 v1 `prereg_draft_review_v1.md`(b7cdd241)
  - 코어 v1(매니페스트 e70ac0af): `standing.R`(83a57088) · `register.R`(d8629123) · `pins.R`(3c793976) · `p1.R`(004f1026) · `p4.R`(50a749c9) · `RELEASES.json`(44ee4449) · `round.sh`(0736dcc0) — v1 점검 때와 모두 같다
  - 운영: `02_Infrastructure/ops/standing_board_run.sh`(b661b6cb · v1 때와 같다)
  - 시험: `08_Tests/programs/test_round_core_v1_standing.R`(0b5be604) · `test_round_core_v1_flow.R`(12a7cddf)
  - HEAD: 시작 77f8ab831 → 끝 d19e631a6. 그 사이 다른 세션 커밋 2건(d6ea880ed · d19e631a6)은 핀 26 · 판 폴더 · 코어를 건드리지 않았다(파일 목록 대조).
- **판정: ok(등록 가능)** — 초안 v2 는 지금 등록 조건 ②~⑧ 을 모두 만족한다(① = 이 기록).
  - v1 필수 F-1 은 풀렸다. `rc_pins_mismatches` = 0건이다(14:2x · 14:38 두 번 확인). `rc_draft` 식으로 지금 사양에서 초안을 다시 만들면 바이트 그대로 나온다(d7720f29 · md 7c4a292c).
  - v1 → v2 사양 차분을 기계로 대조했다. 정확히 진술한 다섯 묶음(20 경로)뿐이다. 규칙 · 칸 · 선택 · 생성 함수 핀 · 회계 · 보고 · Superfan 은 그대로다.
  - `orientation_admit` 명시는 실효 집합을 바꾸지 않는다. 같은 시각에 v1 설정 · v2 설정으로 만든 입구 표 두 벌이 통째로 같다(51 디렉터리 · 통과 1).
  - 권고 셋: 고정되는 사양 문장 둘의 사실 오류, 핀 범위, 원장 커밋 상태다. 판정 규칙 · PIT 에는 닿지 않는다. 사양 문장을 고치면 사양 md5 가 바뀌어 v3 가 필요하다 — v3 여부는 원 세션이 정한다(3절).
- **건수: 필수 0 · 권고 3 · 선택 4**

## 0. 정보 경계 선언

- 연 것
  - 판 폴더: `prereg_draft.json`(v2) · `prereg_draft.md` · `drafts.json` · `round_spec.json` 전문 · `DESIGN.md` 전문 · `prereg_draft_review_v1.md` 전문.
    - `standing_rules.md` 는 md5 와 재생성 대조만 했다.
    - `specs/` 2개는 키 · factors · weighting · rebalance · base_signal · md5 만 봤다.
    - `behavior_card_cfg_at_prereg.json` 은 md5 만.
    - git: `git show 77f8ab831:` 초안 v1 json · md, `git diff eaa899df9 HEAD -- DESIGN.md`.
  - 코어 v1
    - 전문: `pins.R` · `spec.R` · `load.R`.
    - 일부: `register.R`(1-160) · `standing.R`(1-130 · 233-345 · 378-512 · 590-632 · 672-745 · 895-960) · `util.R`(1-60) · `p1.R`(19-50) · `metrics.R`(15-32) · `cell_eval.R`(45-70) · `p4.R`(140-206 · grep).
    - `round.sh`(1-60 · 100-175) · `RELEASES.json`(앞 80줄 · 값 대조).
  - 운영: `standing_board_run.sh`(1-80).
  - 측정 경로(source 줄 · 그 맥락)
    - `rf_cell_worker.R` · `rf_cell_engine.R`(40-60 · 70-80 · 96-112 · 135-145 · 272-280 · 545-590 · 812-820 · 888-895) · `run_paper_replication.R`(source 줄 · 646-670 · 820-840).
    - `save_bt_result.R`(1-30 · grep) · `audit_bt_result.R`(93-118 · 740-758).
    - `RP_AUTO_2002_06975/engine.R` 은 torch · cuda grep 줄만.
  - 문서(머리글 · 해당 줄만)
    - 헌장: §2 원칙 · §5 빈칸 행의 이름 칸만.
    - `research-program` SKILL §0-1 앞 15줄 · 설계 README(`qvest_v10_2_audit_redesign_20261110`) 머리글 · `factor_db/DIRECTION_POLICY.md` 머리글 · `superfan_protocol.md` 머리글.
  - 등록부 `research_programs.json`: P1R01 · P2R05 round 의 round_id · status · prereg · prereg_md5 만. `grade` · `cr_verdict` · 성과 키는 출력하지 않았다. P1S01 항목은 없다(미등록).
  - 결정 기록부: `P4-BASE-POOL-GRADE-PATH-TAU-20261111` 의 존재 · status · owner · decided_by · opened_at · options 개수와 머리 6자만.
  - 판단 원장 `q_judgment_ledger.json`
    - reviews: id · role · trigger · round · file · at · challenges id 목록.
    - challenges: id · review · role · grade · status · hold_request · responses 개수와 kind.
    - HEAD 와 작업 트리를 id 단위로 대조했다. claim · evidence · alternative · 응답 본문은 출력하지 않았다.
  - P2R05 `prereg.json`: md5 · git 이력 3판의 md5 · cells 의 n_family 값 · operational_pins 경로 목록.
  - `06_Registry/behavior_card.json`: 최상위 키 · `uc_floor` 값 · md5.
  - `nvidia-smi` 이름 · 메모리.
- 안 연 것
  - 모든 라운드의 `results/`. P1S01 `results/` 는 파일 수만 셌다(0).
  - `authoritative_remeasure.json` · `stage_artifacts/replication/**` · 산출물 `behavior_card.json` · `results/standing/*`.
  - Superfan 리뷰 본문 · 판단 원장의 리뷰 · 도전 본문(아래 우연 열람 몇 줄 제외) · 2023 이후 성과 수치.
  - 설계 README 본문(사양 노출 8번째 줄에 따르면 §1 · §8 에 전 기간 등급 집계가 있다) · `DIRECTION_POLICY.md` §6 본문.
  - 하네스가 넣은 MEMORY 문맥은 판정 · 지적에 쓰지 않았다.
- 간접 접근 고지
  - 입구 dry-run(`round.sh … scan --dry-run` 1회 · 같은 함수 R 호출 2벌)은 코드가 레인 산출을 읽는다: `04_holdings.csv` 의 date · weight 두 열, `authoritative_remeasure.json` 의 `replication.source_paper`, `lane_provenance` · `FIDELITY` · `fidelity_audit`, 판 표식 메타. 화면에는 사유 · 방향 층 · 판 표식 · PIT · 롱 레그 계수 · paper_key 만 띄웠다. 입구 표에 성과 열은 없다.
  - 시험 2종은 P0R01 공유 측정 `eval.json` 을 읽는다. 출력은 `[ok]` 줄 수 · `[FAIL]` 줄 수 · 마지막 JSON 줄만 봤다.
- ★우연 열람 고지
  - `orientation_admit` 문자열을 저장소 전체에서 grep 하다가 경계 안쪽 파일 세 곳의 줄이 화면에 떴다.
    - `06_Registry/q_judgment_ledger.json` 도전 claim 2줄(5945 · 6243).
    - Superfan 리뷰 본문 `_supervision/superfan/philosophy/20261111_1351_P1_P1S01.md`(168-170) · `_supervision/superfan/20261111_1355_T1.md`(90).
  - 내용은 노출 4번째 줄 문구와 DESIGN §3-1 의 P2R05 md5 이력이었다. 성과 수치 · 등급 값 · 시험 창 정보는 없었다.
  - 그 뒤 grep 은 그 경로를 뺐다. 이 기록의 지적은 모두 코드 · 파일 · git 재도출에서 나왔고, 그 줄은 근거로 쓰지 않았다.
- 실행한 것
  - Rscript 임시 스크립트 5개(`mktemp -d` 폴더 · 점검 뒤 삭제)
    - 초안 재구성 · 핀 재계산 · 매니페스트 대조
    - 방향 층 허용 집합 · 사양 검사 · 규칙 문서 재생성 · 시드 회계
    - v1 · v2 scan 설정 입구 표 대조
    - ⑥ · ⑦ 재도출
    - 부호 층 간접 탐침 7종
  - `bash round.sh <판> scan --dry-run` 1회(전후 `git status` md5 같음 · `results/` 0 그대로).
  - `standing_board_run.sh --dry-run` 2회.
    - 1회차: `RC_SA_ROOT` = 임시 가짜 사전등록, `RB_SH` = 임시 배리어 대역.
    - 2회차: 실제 뿌리.
    - 잠금 · 로그 생성 없음(scheduler_logs 651 → 651).
  - `Rscript` 시험 2종. 부수 효과: `.cache/round_core/perf/{P1R99_core_selftest,P1S98_standing_selftest2,P1S99_standing_selftest}.jsonl` 에 줄이 더해졌다(시험 설계상 · git 무시 경로).
  - git status · diff · log · show, md5sum, nvidia-smi(읽기).
  - `round.sh` 의 draft · reviewed · register · measure · standing-measure · scan(비드라이런) · standing-check 는 돌리지 않았다. standing-check 는 `standing_rules.md` 를 다시 쓰므로 같은 함수를 메모리에서 불러 대조했다.
- 쓴 것: 이 파일 1개.

## 1. 항목별 결과(재도출 값 · 파일:행)

### 1. 초안 무결성 — 일치

| 대조 | 재도출 | 결과 |
|---|---|---|
| `drafts.json` 마지막 판(v2) md5 = 디스크 초안 | 판 수 2 · v2 md5 d7720f29 = 디스크 · md5_md 7c4a292c = 디스크 · at 14:15:28 · review null | 일치 |
| 초안 `spec_md5` = 지금 `round_spec.json` | bdb8b98d = bdb8b98d · 초안 `spec` = `rc_spec_load` 결과(.path · .md5 제외) identical | 일치 |
| 사양 바이트 재현(참고) | 초안 v2 `spec` → `rc_json_write` = bdb8b98d. 초안 v1 `spec` → `rc_json_write` = 52d8eecc. v1 초안 안의 `spec` 필드가 v1 사양 바이트를 그대로 재현한다 — 2절 차분의 기준이 맞다 | 일치 |
| 초안 `cells[].md5` = 지금 칸 사양 | E2 fd9a012f · E3 398e153c = 디스크 | 일치 |
| `rc_pins_mismatches(초안 pins)` | **0건**(14:2x · 14:38 재확인 · HEAD d19e631a6) | 일치 |
| `rc_pins_compute(사양)` = 초안 pins | files · core · packages · r_version 모두 identical | 일치 |
| 핀 구성 | 기본 18(pins.R:6-13) + `pins.files` 4(round_spec.json:158-165) + 엔진 1(`RP_AUTO_2002_06975/engine.R` · pins.R:27-35) + 칸 사양 2 + 행동 카드 사본 1 = **26**. 겹침 없음 · 합집합 26 = 초안 경로 집합 | 일치 |
| v1 → v2 핀 md5 | v1 22개 중 21개 같음. `run_paper_replication.R` 65580501 → 6fe62365(F-1 해소). 새 4: `rf_base_cache.R` f6fef4f9 · `replication_harness.R` d0b94e14 · `backtest_result_contract.R` d1d6f81d · `validation/lookahead_detector.R` 044f3ff1 | 일치 |
| 코어 매니페스트 | 지금 e70ac0af = `RELEASES.json` v1 `manifest_md5` = 초안 `core` · 파일별 md5 20/20 · 초안 `pins.core.files` = RELEASES `files` | 일치 |
| 패키지 · R 판 | data.table 1.18.6.1 · jsonlite 2.0.0 · arrow 26.0.0 · PerformanceAnalytics 2.0.8 · bbdetection 1.0 · R 4.6.2(2026-10-29 ucrt) — v1 과 같다 | 일치 |
| 초안 전체 재구성(`rc_draft` 식 · register.R:45-63 · 판 번호 2 · 시각 = 초안 값) | md5 d7720f29(바이트 동일) · `rc_prereg_md` = 7c4a292c · `rules_resolved` JSON 직렬화 동일 | 일치 |

### 2. v1 → v2 차분 — 진술과 일치(정확히 다섯 묶음)

- 사양 JSON 경로 차분(초안 v1 `spec` → v2 `spec`) = 20 경로뿐이다.
  - ① `$.standing_cfg.scan.orientation_admit[1]` 추가 `"factor_db_static"`(v1 = `["engine_native"]`).
  - ② `$.exposures[3]` 문구 변경(4번째 줄) · `[6]` · `[7]` 추가 — 새 줄 2. 6줄 → 8줄. `[0..2]` · `[4..5]` 는 같다(가운데 끼워 넣기 없음).
  - ③ `$.conclusion_scope[4..9]` 추가 — 새 6줄. 4줄 → 10줄. 앞 4줄은 같다.
  - ④ `$.changes_after_review[0..3]` · `$.changes_after_superfan[0..4]` — v1 은 둘 다 빈 배열이었다. 4줄 · 5줄.
  - ⑤ `$.pins` 추가(files 4 · basis).
- 불변
  - 최상위: schema · program · round_id · template · core_version · tau_d · purpose · hypothesis · standing · cells · rules · selection · tests · behavior_card_cfg.
  - `standing_cfg`: edition · program · generator · generator_pin(fn_md5 80f8311f · like_md5 080cfea8 · canon) · scan 의 나머지 8 키 · accounting · rejudge_prior_editions · report · superfan.
- 초안 수준
  - 같은 것: `rules_resolved` · `sentences` · `cells` · `behavior_card_cfg`(6a2a1d21) · `core` · `pins.packages` · `pins.r_version`.
  - 다른 것: `draft_version` · `drafted_at` · `spec_md5` · `spec` · `pins.files` 뿐이다.
- `prereg_draft.md` 차분(55 → 63줄): 제목 v1 → v2 · 사양 md5 · 노출 4번째 줄 + 2줄 · 결론 범위 + 6줄 · 핀 '파일 22' → '파일 26'. 사양 차분과 같다.

### 3. `orientation_admit` 명시 — 실효 집합 불변 · 입구 결과가 v1 점검과 같다

- `rc_standing_orient_admitted`(standing.R:446)
  - `c("engine_native")` → `c("engine_native","factor_db_static")`.
  - `c("engine_native","factor_db_static")` → 같은 값(순서까지 identical).
  - 사양이 읽히는 꼴(list)도 같다.
  - 층별: engine_native 참/참 · factor_db_static 참/참 · factor_db_asof 거짓/거짓 · orientation_layer 거짓/거짓. `dynamic_sign` 판정(standing.R:476)이 이 집합을 쓴다.
- `rc_standing_validate(check_pin = TRUE)` 통과(standing.R:96-127 · 허용 어휘 검사 :113). 생성 함수 핀 차분 0건.
- 규칙 문서
  - `rc_standing_rules_md(v2 사양)` = 디스크 `standing_rules.md` 82d3597f(바이트 동일 · HEAD 블롭과도 같다).
  - v1 사양으로 만들면 2e01cddd(= v1 점검 값)다. 다른 줄은 23번째 하나뿐이다: '허용 방향 층 = engine_native' → 'engine_native · factor_db_static'(standing.R:884).
- `bash round.sh … scan --dry-run`(14:21 · standing.R:925-929)
  - `[scan] P1S01_standing_qualification · 디렉터리 51 · 입구 통과 1(새 엔진 1 · 이미 판정 0) · dry-run(쓰기 없음)`.
  - 제외 사유: audit_not_passed 4 · combination 4 · dynamic_sign 11 · implementation_suspect 4 · long_leg_absent 1 · no_engine 4 · no_handoff 40 · not_routed 7.
  - 통과: `RP_AUTO_CLEAN_1908_01112` · 1908.01112 · new.
  - **v1 점검(51 · 통과 1 · 사유 분포)과 같다.** 전후 `git status --porcelain` md5 같음.
- 같은 시각 대조
  - `rc_standing_lane_candidates(v1 scan 설정)` 과 `(v2 scan 설정)` 의 표가 통째로 같다(51행 · all.equal 참).
  - 방향 층 분포: engine_native 36 · factor_db_asof 9 · orientation_layer 2 · 엔진 없음 4 · factor_db_static 0.
  - 인계 기록이 있는 `dynamic_sign`: factor_db_asof(2202.10721 · 2412.12350 · 2601.10732) · orientation_layer(1603.00751 · 1801.01777). v1 과 같다.
  - 통과 행: engine_native · `factor_db_vintage = stale` · pit clean · 롱 레그 0/95.
- 지금 factor_db_static 엔진은 0개다. 그래도 허용 집합이 identical 이라 앞으로 들어올 엔진에도 영향이 없다.

### 4. 새 핀 4개 · 커밋 상태 — 일치 · 깨끗

| 핀 | md5 | 마지막 커밋 | 7일 커밋 | 경로 역할(재도출) |
|---|---|---|---|---|
| `02_Infrastructure/reinforcement/rf_base_cache.R` | f6fef4f9 | 84f6d21be 10-05 | 0 | rf_cell_engine.R:111 — base_signal 이 engine · engine_blend 면 적재(상설 칸 전부) · 레인 시드는 run_paper_replication.R:655(조건부) |
| `02_Infrastructure/replication/replication_harness.R` | d0b94e14 | 1ace33edc 11-10 19:19 | 2 | run_paper_replication.R:62 |
| `02_Infrastructure/contracts/backtest_result_contract.R` | d1d6f81d | ce92a0fbe 10-17 | 0 | run_paper_replication.R:65 |
| `02_Infrastructure/validation/lookahead_detector.R` | 044f3ff1 | d3805fb92 10-17 | 0 | run_paper_replication.R:64 · 입구 `pit_static` = standing.R:379 |

- 넷 모두 실재 · 추적됨 · `git status` 빈 줄 · HEAD 블롭 md5 = 디스크. 사양 `pins.basis` 의 역할 서술(기저 신호 캐시 키 · 레인 하네스 · 산출 계약 · 입구 pit_static)과 맞다.
- R-4: `git status --porcelain -- <핀 26> test_round_core_v1_standing.R test_round_core_v1_flow.R 04_Research/programs/_lib/round_core/` = **빈 결과**(14:2x · 14:38). 판 폴더 수정분은 `drafts.json` · `prereg_draft.json` · `prereg_draft.md` 셋뿐이다(예외 대상).

### 5. 새 결론 범위 · 노출 문장 — 경계 위반 없음 · 사실 진술 대부분 맞음 · 2건 어긋남(R-6 · R-7)

- 경계: 새 문장 19개를 기계로 훑었다(노출 [3] · [6] · [7] · 결론 범위 [4..9] · changes 9줄 · pins.basis).
  - 찾은 패턴: % · 소수 · 2023 이후 연도 · 등급 글자 · '지표 = 값'.
  - 걸린 것은 노출 [7] 의 '2026'(무엇을 읽었는지의 고지 — 'BOOK_0001 2026 일별 성과' · 값 없음)과 결론 범위 [5] 의 '2002.06975'(논문 키)뿐이다.
  - **성과 수치 · 시험 창 값 · 등급 값 없음.**
- 사실 진술 대조
  - 결정 `P4-BASE-POOL-GRADE-PATH-TAU-20261111`: 작업 트리 · HEAD 모두 1건. status open · owner dohoon · decided_by 없음 · 선택지 3.
  - 리뷰 `R-20261111-001`: judgment · T1 · round = 전체 id · 파일 `20261111_1355_T1.md` 실재 · 77f8ab831 커밋.
  - 리뷰 `R-20261111-002`: philosophy · P1 · round = 전체 id · 파일 `20261111_1351_P1_P1S01.md` 실재 · 77f8ab831 커밋.
  - 사양 · DESIGN 이 인용한 도전 id 는 모두 실재하고, 적힌 리뷰 · 등급과 같다.
    - T1 challenge: C-001 · 002 · 003.
    - T1 note: C-004 · 005.
    - P1 challenge: C-013 · 014 · 015 · 016.
    - P1 note: C-017.
  - 커밋 e66d9f0aa(13:48:15 · +3/−2)는 `next_probe` 문자열 2줄 교체와 주석 1줄 추가다. L-code 경로이고 상설 측정은 `QVEST_RP_NO_LCODE=1` 로 돈다(standing.R:656) — '문자열 두 줄 · 측정 무영향' 맞음.
  - 헌장 대조
    - 원칙 5(상승장 55%) · 6(결국 시장을 이긴다).
    - 빈칸 1 = 집중의 문턱 · 7 = 강세 참여 단위 · 17 = 독립 엔진 · 엔진의 동일성 · 18 = 꾸준함의 단위 · 21 = 추첨 행운 · 24 = S 가 오른 현금 기계.
    - 인용 자리와 뜻이 맞다.
  - E3 구성(결론 범위 [6]): DB 팩터 3(M01_Mom_12_1 · V10_FCF_Yield · M08_Residual_Mom · direction 없음 = 기본 ic_asof) · weighting `lean:entropy` · rebalance `rank_buffer` ×2. 맞음.
  - 진단 패킷 `results/<code>/visible/`(결론 범위 [8]) = cell_eval.R:64. 맞음.
  - 기저 풀 결함 둘(결론 범위 [9]): 상설 행을 엔진 경로로 합침(p4.R:159-166 · 같은 경로 여러 상설 행이면 마지막이 덮음) · 등급 경로 A/B 로 자격(p4.R:177-181). 맞음.
  - 머리글 실재(본문 미열람): 규약 §13-2(읽기 경계 — 새 파일) · `DIRECTION_POLICY.md` §6 · 설계 README §1 · §8.
- 어긋남
  - `changes_after_review[1]`(round_spec.json:147) '(7일 1~4회)' — rf_rebalance.R 은 7일 0회다 → **R-6**.
  - 결론 범위 [8](round_spec.json:142) '판 1 원장은 … 만 넘긴다' — 원장에는 더 있다 → **R-7**.
- 참고(지적 아님): 노출 [5](기존 줄)의 '미리보기 뒤 입구 규칙을 바꾸지 않았다'.
  - v2 는 13:27 미리보기 뒤에 `orientation_admit` 표기를 바꿨다.
  - 실효 규칙은 같고(3절 재도출), `changes_after_superfan[4]` 가 공시했다 — 뜻으로는 참이다.
- 검증 밖: 노출 [7] 의 '둘 다 도전 근거에서 뺌' · DESIGN 의 '철학 N1 · T1 N2 · N3 · N4' 번호 · 'T1 C-20261111-002 대안 (a)'의 내용 · 도전 응답 내용이 도전에 답하는지. 모두 리뷰 · 도전 본문을 열어야 해서 보지 않았다.

### 6. 등록 조건 ①~⑧ — ②~⑧ 충족 · ⑥ 근거가 커밋 전(R-8)

- ① 마지막 초안 v2 의 점검 = 이 기록(`reviewed 2 … ok` 뒤 충족).
  - `rc_mark_reviewed` 전제(디스크 초안 = v2 md5 · register.R:71)는 참이다.
  - 이 파일 이름은 ⑦ 제외 정규식(`prereg_draft` · register.R:103)에 걸린다 — 쓰고 나서도 ⑦ 결과가 바뀌지 않는다.
- ② 사양 · 칸 사양 md5 = 초안(1절).
- ③ 핀 0건(1절).
- ④ 사양 `tests` 2종 재실행
  - `test_round_core_v1_standing.R` `{"test":"round_core_v1_standing","pass":94,"fail":0,"total":94}` · 17초.
  - `test_round_core_v1_flow.R` `{"pass":41,"fail":0}` · 4초.
  - 마지막 `{"test"` 줄 fail = 0 이다(register.R:124-125 가 읽는 줄). `RELEASES.json` tests_at_release 와 같다.
- ⑤ 리허설 기록 없음 → 건너뜀(register.R:120).
- ⑥ `rc_p1_check("P1S01_standing_qualification")` = **ok**.
  - reviews `R-20261111-002` · 파일 정규식(register.R:83 · 태그 P1S01) 일치 · 실재.
  - n_challenges(challenge | stop) = 4: C-20261111-013 · 014 · 015 · 016. 모두 accepted · 응답 1건(kind accept) · hold_request 거짓.
  - 나머지 8건은 endorse 3 · note 5(closed_note)라 조건 대상이 아니다.
  - 같은 라운드의 철학 P1 리뷰는 이것 하나다.
  - **단, 이 응답들은 작업 트리 원장에만 있다**(HEAD 에서는 open · 응답 0) → R-8.
- ⑦ `rc_uncommitted` = **0건**.
  - 범위: 판 폴더 · `round_core/v1` · 칸 사양 2.
  - 걸린 3줄(`drafts.json` · `prereg_draft.json` · `prereg_draft.md`)은 모두 제외 정규식 대상이다.
- ⑧ 사전등록 정본 `stage_artifacts/programs/P1_RETURN/P1S01_standing_qualification/prereg.json` 은 아직 없다(`RC_SA_ROOT` 미설정 = 저장소).

### 7. 정기 실행 인식 — 조건 그대로

- 발견 조건(standing_board_run.sh:36-45)을 v2 사양이 모두 만족한다.
  - L38: round_spec.json:10 `"standing": true`.
  - L40: round_spec.json:4 `  "round_id": "P1S01_standing_qualification"`(2칸 들여쓰기 · 최상위 · 끝 고정 없음이라 CRLF 무관).
  - L41: round_spec.json:3 → `P1_RETURN`(sed 추출값에 CR 없음 · od 확인).
  - L43: `$SA_ROOT/stage_artifacts/programs/P1_RETURN/P1S01_standing_qualification/prereg.json` = `rc_paths()$prereg_rel`(register.R:11-16).
  - v2 에서 더한 문장은 배열 안쪽(깊은 들여쓰기)이라 이 grep 들에 닿지 않는다.
- 모의 실행(드라이런)
  - 가짜 사전등록 + 배리어 대역: `[상설 정기 · 드라이런] 등록된 판 1 · 배리어 free(열림) · 잠금 없음`, 이어서 `[드라이런] 04_Research/programs/P1_RETURN/P1S01_standing_qualification: scan → pending(입구 통과 대기 항목) → 대기 있으면 standing-measure → standing-report --send`.
  - 실제 뿌리: 출력 없이 rc 0(등록 전).
  - 저장소의 `"standing": true` 사양은 이 판 하나다.
- 첫 틱 경로(`rc_standing_context` · `rc_registered` · 핀 대조)는 v1 점검 뒤 코어가 같아(매니페스트 e70ac0af) 그대로다.

### 8. DESIGN 새 문장 — 대부분 맞음 · 어긋남(R-6 · S-5 · S-6 · S-8) + 낡은 문장 2(S-7)

| 문장(DESIGN 행) | 재도출 | 결과 |
|---|---|---|
| §3-1 L32 P2R05 md5 이력 · 회계 264 | git: 67a049f81(11-06) 9ed7b23f → 3f6d3d50f(11-08 16:56) dedc7a49 → 1d2abf6bd(11-08 23:49) bf45f4e7 = 지금 파일 = 등록부 prereg_md5. 세 판 모두 칸 n_family 264(4칸) · `rc_standing_nf_prior` = 264 = 시드 두 사양 | 맞음(v1 S-1 반영) |
| §3-2 L53 '직접 호출 · `$` · `::` 형태는 제외' | 탐침: 직접 · `qm::` · `E$` → orientation_layer(입구 제외) | 맞음(v1 R-2 반영) |
| §3-2 L54 한계 | 탐침 4종(함수 값 `lapply` · `do.call` 문자열 · `match.fun` 문자열 · 별칭)은 단독이면 engine_native, 정적 커넥터와 함께면 factor_db_static 이다 — 모두 허용(4/4 놓침). 두 함수를 쓰는 레인 엔진은 1603.00751(L198) · 1801.01777(L236) 둘이고 둘 다 직접 호출이다(스캔 orientation_layer). 'misdeclared' 어휘 = `rf_fidelity_audit_lib.R` 등 6파일 | 맞음. 감사의 간접 형태 탐지력은 이 점검 밖 |
| §6 L73 정정 | GPU · 임대 grep 0건(standing.R · round.sh · standing_board_run.sh · rf_cell_worker.R). 엔진 = venv torch · cuda 면 워커 ≤ 8(engine.R:73 · 119). GPU 모델 RTX 4080 SUPER 16376 MiB 일치 | 맞음 · 표기 S-8 |
| §8 L87 새 계보 | SKILL §0-1 ② '새 계보를 만든다' · README §1-2 · §1-3 머리글 실재 · 헌장 빈칸 17 · blend 블록 = p4.R:25 | 맞음 |
| §8 L88 기저 = 상설 통과만 | 열 `standing_qualified` = p4.R:145 · 198. 결정은 open 이다 | 결정 선점 표기 → S-5 |
| §8 L89 기저 풀 정정 | p4.R:159-166 · 177-181 · T1 C-001 · C-002 실재 | 사실 맞음 · 'v1 정정' 모순 → S-6 |
| §8 L90 집중 필수 | p4.R:40 `worst_name_contrib_deep_vis`('N4 집중(빈칸 1)') · :1013 규칙이 쓸 때만 계산 · 철학 C-013 · 014 실재 | 맞음 · 번호 표기 → S-8 |
| §9-6 L100 판 2 후보 | `behavior_card.json::uc_floor` 실재(0.55 · p4.R:185 가 이미 읽음) · 격리 R-2 · R-3 나머지 · S-2 대응 맞음 | 맞음 |
| §9-7 L101 도훈 결정 | 결정 실재(open · dohoon · 선택지 (가) · (나) · (다)) · pit.md C1 '2026-09-23 도훈 확정 · D-E' · CLAUDE.md '기저 풀(상설 통과 ∪ 등급 B 이상 · …)' | 맞음 |
| §12 L125 초안 v1 → v2 | v1 13:33:09 · 029bcae4(drafts.json) · e66d9f0aa 13:48:15 · 문자열 2줄 + 주석 1줄 · 측정 무영향(standing.R:656) | 맞음 |
| §12 L126 핀 범위 | 22 → 26 · 네 파일 역할 맞음. 그러나 '7일 변경 1~4회'는 rf_rebalance.R 에 틀리고(0회), 제외 목록에 save_bt_result.R 등이 없다 | → R-6 |
| §12 L127 방향 층 표기 | 같은 시각 v1 · v2 설정 입구 표 동일 · 51 · 통과 1 | 맞음 |
| §12 L128 결론 범위 · 노출 | 4 → 10 · 6 → 8 | 맞음 |

## 2. 지적

### 필수 — 없음

### 권고

**R-6. 핀 범위 — 제외 근거 문장 하나가 사실과 다르고, 모든 상설 측정이 거치는 판정 경로 파일 하나가 핀에도 제외 목록에도 없다**
- 사실 1(고정 문장의 오류)
  - 사양 `changes_after_review[1]`(round_spec.json:147)과 DESIGN §12(L126)는 제외 4파일을 '변경이 잦아(7일 1~4회)'로 묶었다.
  - git log(11-04 14:00 ~ 지금) 실측:
    - `factor_db_connector.R` 3(11-09 ×3) · `weight_catalog.R` 1(11-10) · `factor_combinable.R` 4(11-09 ×2 · 11-10 ×2).
    - **`rf_rebalance.R` 0**(마지막 49302fb48 09-21).
  - rf_rebalance.R 은 rf_cell_engine.R:44 에서 모든 칸이 적재한다(spec$rebalance 가 없으면 항등). 시드 E3 의 순위 버퍼(`rank_buffer` ×2)가 이 파일로 돈다.
- 사실 2(빠진 파일)
  - `02_Infrastructure/contracts/save_bt_result.R` 는 모든 상설 측정이 거친다(run_paper_replication.R:68 적재 · :832 호출).
  - 판정이 읽는 월 수익의 원천 CSV(period_returns · benchmark — metrics.R:16-20 `.dp_read` → :24-31 β-통제 t(α))를 이 파일이 쓴다.
  - 그런데 핀에도 없고, DESIGN §12 의 제외 목록(처치 경로 · 결합용 뷰)에도 없다. 7일 0회(마지막 07-03)다. 앞선 등록 P2R05 operational_pins(51 경로)에는 있었다.
  - 같은 꼴(무조건 적재 · 핀 밖 · 판정 영향 작음)
    - `audit_bt_result.R`: :66 · :831 — 감사 표와 manifest 무결성 표식만 덧붙인다(수익 열은 그대로 · audit_bt_result.R:740-757) · 7일 0회 · 마지막 09-25.
    - `rf_sleeve.R`: rf_cell_engine.R:45 — defense_sleeve 가 없으면 NULL 경로 · 7일 1회(11-10).
- 비교(R-1 정지 위험)
  - 지금 핀 26 을 건드린 커밋은 7일 22건이다(11-09 4 · 11-10 15 · 11-11 3). 많은 순: run_paper_replication.R 6 · rf_cell_engine.R 6 · essence_score.R 5 · grade_v3.R 5 · grade_v3.json 5.
  - 제외 4파일의 커밋 6건 가운데 핀 파일을 함께 건드리지 않은 것은 4건이다. 더해도 정지 사건은 22 → 26 수준이다.
  - save_bt_result.R · rf_rebalance.R 을 더하는 비용은 0 이다.
- 결과
  - 등록 뒤 save_bt_result.R 이 바뀌면, 판은 멈추지 않은 채 판정 입력이 바뀔 수 있다. pins.R:1 '핀 = 판정에 닿는 전체'와 어긋난다(v1 R-3 과 같은 종류).
  - 사실 1 은 등록본에 그대로 남는 근거 문장의 오류다.
- 제안
  1. v3 를 만들면
     - `pins.files` 에 save_bt_result.R · rf_rebalance.R 을 더한다(둘 다 7일 0회). audit_bt_result.R · rf_sleeve.R 도 함께 정한다.
     - `changes_after_review[1]` · `pins.basis` 를 실측(3 · 1 · 0 · 4회)과 남는 제외 이유로 고친다.
  2. v3 를 만들지 않으면
     - DESIGN §12 에 정정을 적는다: rf_rebalance.R 0회 · save_bt_result.R 등 미핀 · 등록본 문장은 그대로 남는다는 사실.
     - §12 의 '첫 판정 때 git 변경 유무 기록' 대상에 save_bt_result.R · audit_bt_result.R · rf_sleeve.R 을 더한다.

**R-7. 결론 범위 9번째 줄(conclusion_scope[8] · round_spec.json:142)의 '판 1 원장은 … 만 넘긴다'가 코드와 다르다**
- 원장 verdict 의 `visible` = `RC_STANDING_VIS_COLS`(standing.R:53-54) ∩ 판정 표 열 + 자격 열 + window(standing.R:717-718 · 기록 :722).
  - 판정 표(p1.R:31-34)는 t_alpha_vis 외에 alpha_ann_vis · beta_vis · port_t_vis · n_vis · uc_vis · cagr_vis 를 싣는다.
  - judge 가 dd_capture_median · worst · n_crisis 를 붙인다(standing.R:705-708).
  - → 원장에는 문장의 목록 말고도 보는 창 연 α · β · PORT_t · 월 수 · CAGR 이 있다.
- 반대로 P4 기저 풀이 원장에서 받는 수치는 uc_vis 하나다(`rc_standing_qualified` standing.R:260-285 · 현금 기계 p4.R:184-186).
- 뒤 절('집중 · 숨은 현금 날 · 강세 구간별 참여 · MC8 귀속 · 하락/상승 β · 팩터 방향 값은 원장에 없다')은 맞다. 모두 보는 창 값이라 τ_D 문제는 없다.
- 제안
  - v3 를 만들면 '만'을 빼거나 실제 열로 적는다. 예: '원장의 보는 창 열 = t(α) · 연 α · β · PORT_t · 월 수 · 상승 포착 중앙값 · CAGR · 위기 하락노출(중앙 · 최악 · 수) — P4 기저 풀은 이 가운데 상승 포착만 읽는다'.
  - 이 건만으로 v3 를 만들 이유는 없다. v3 가 없으면 DESIGN 에 정정을 기록한다.

**R-8. 등록 조건 ⑥ 의 근거(도전 응답 7건)가 판단 원장 작업 트리에만 있다 — 등록 전에 커밋한다**
- `rc_p1_check`(register.R:80-96)는 작업 트리 원장을 읽어 ok 다(6절).
- HEAD(d19e631a6) 원장에도 두 리뷰는 있다(77f8ab831 커밋). 그러나 도전 C-20261111-001 · 002 · 003 · 013 · 014 · 015 · 016 이 모두 **open · 응답 0** 이다.
- 작업 트리 diff(+70/−15)는 이 7건의 상태 · 응답뿐이다. 다른 id · 리뷰 · 판단은 바뀌지 않았다(id 단위 대조).
- HEAD 상태로 ⑥ 을 돌리면 '응답 없는 도전'으로 거부된다. ⑦ `rc_uncommitted`(register.R:99-104)는 원장을 보지 않는다.
  - 그래서 지금 등록하면, 사전등록의 `philosophy_p1`(ok · n_challenges 4)이 git 이력에 없는 원장 상태를 근거로 남는다.
- 제안
  - 등록 직전(또는 등록 커밋에) 원장의 이 응답 줄을 커밋한다.
  - v1 S-4 처럼 다른 세션 변경이 섞이면 범위를 밝힌다. 지금 `research_programs.json` 에 다른 세션 미커밋 +319/−2 가 있다.

### 선택

- **S-5.** DESIGN §8 L88 '기저는 상설 판 통과 행만(standing_qualified = TRUE) 받는다'.
  - 도훈 결정 `P4-BASE-POOL-GRADE-PATH-TAU-20261111` 은 status open · owner dohoon · 선택지 3 이고, §9-7(L101)도 결정 대기로 적었다. L88 은 그중 (나)를 결정된 것처럼 적었다.
  - 사양 결론 범위 [5] 는 '첫 강화 사슬의 단독 기저'로 한정한다. DESIGN 도 그 범위('첫 사슬은' 또는 '결정 전까지는')로 좁힌다.
  - 열 이름 `standing_qualified` 는 p4.R:145 · 198 과 맞다.
- **S-6.** DESIGN §8 L89 '출시된 v1 을 다시 열지 않고 코어 v2(…) 또는 v1 정정 + 이 판의 새 판(P1S02)으로'.
  - 둘째 갈래 'v1 정정'은 같은 문장 앞 절('v1 을 다시 열지 않고')과 부딪친다. `RELEASES.json` immutability('출시된 판의 파일은 고치지 않는다')와도 부딪친다.
  - 사양 `changes_after_superfan[2]` 는 'v1 을 다시 열지 않고'만 적었다.
  - 'v1 정정'을 빼거나, 남기려면 '출시 원칙의 예외 — v1 매니페스트가 바뀌어 이 판은 핀 불일치로 멈춘다 → P1S02'로 적는다.
- **S-7.** DESIGN 의 낡은 문장 둘(새 문장은 아니다 · v2 가 사양에서 고친 '등록 문서만 읽어도 받는 범위가 읽히게'와 같은 종류).
  - §3-2 사유 표 `dynamic_sign` 행(L41)
    - '정본 커넥터 load_month_factors/load_daily_factors(as-of IC 3단 부호) → factor_db_asof' · '**기본 = engine_native 만**'.
    - 11-10 수리(standing.R:14-20 · 338)와 v2 사양(orientation_admit 명시)과 다르다. 바로 아래 '입구 수리' 절(L51-56)이 맞는 설명이다.
  - §7 머리(L75) '사양 `exposures` 와 같다'
    - §7 은 5줄(L76-80)이고 사양은 8줄이다.
    - 사양 4번째 줄의 새 문구와 '(11-11 등록 전 고지)' 4줄이 §7 에 없다. L80 은 사양에 없는 줄이다.
    - 머리를 '요약'으로 바꾸거나 사양 줄을 옮긴다.
- **S-8.** DESIGN 새 문장의 표기 셋.
  - §6 L73 'RAM 여유 약 11.8 GB = 셀 워커 1개 정점 약 7.5 GB'
    - '='는 '≥(워커 1개분)'으로 고친다.
    - 13:4x 시점 관측값(레인 THGNN 4.2 GB · RAM 여유)은 시점 기록이라 재도출할 수 없다.
  - §12 L126 '첫 판정 때 기록한다'
    - 기록 위치 · 방법이 없다(상설 원장은 코드만 쓴다 · standing.R:168).
    - 어디에 적을지(DESIGN §12 · 재개 저널 · 판단 원장) 정해 둔다. R-6 의 미핀 파일도 같은 기록에 싣는다.
  - N 번호
    - §8 L90 'N4 `worst_name_contrib_deep_vis`'(p4.R:40 꼬리표)와 §9-6 L100 '철학 N4'(q_uc 정본 참조)가 같은 'N4'로 다른 것을 가리킨다.
    - '철학 N1 · T1 N2 · 철학 N3'은 원장 id 가 아니라 리뷰 본문의 번호라 이 점검이 대조하지 못했다.
    - 원장 id(C-…)로 적으면 추적된다.

### v1 지적의 반영 상태(재도출)

- F-1: 해소(핀 0건).
- R-2: DESIGN 문장을 좁힘 · 판 2 로 미룸(§9-6).
- R-3: 일부 반영(+4). 남은 것 = R-6.
- S-1 · S-2: 반영(§3-1 · §6).
- S-3: round 전체 id · 파일 이름 형식 모두 맞음.
- R-1 · R-4 · R-5: 등록 시점의 절차라 재도출할 수 없다. 지금 상태 = 핀 26 · 시험 2 · 코어 깨끗.

## 3. v3 를 만들 경우의 차분 점검 기준

- 달라도 되는 키
  - `draft_version`(2 → 3) · `drafted_at` · `spec_md5`.
  - `spec.pins.files`(R-6 로 더한 경로) · `spec.pins.basis` · `spec.changes_after_review`(고친 [1] · 새 줄) · `spec.conclusion_scope[8]`(R-7).
  - 초안 `pins.files`: 더한 경로의 항목만 늘어난다.
- 같아야 하는 것
  - 사양: `rules` · `cells` · `selection` · `standing_cfg` 전부(scan · generator_pin · accounting · report · superfan) · `exposures` · `conclusion_scope` 의 나머지 줄 · `tests` · `behavior_card_cfg`.
  - 초안: `rules_resolved` · `sentences` · `cells[].md5`(fd9a012f · 398e153c) · `behavior_card_cfg.md5` 6a2a1d21 · 코어 매니페스트 e70ac0af(= `RELEASES.json`) · 패키지 · R 판.
  - 기존 핀 26 의 md5: 그 사이 바뀐 파일이 있으면 그 파일과 커밋을 적는다.
- 다시 재도출할 것
  - 이 기록의 항목 1(무결성 · 핀 수) · 2(차분) · 6(시험 재실행 · `rc_p1_check` · `rc_uncommitted`) · 7(발견 조건).
  - scan 설정을 건드리지 않으면 항목 3 은 승계된다.
- ⑥ 은 `rc_p1_check` 가 리뷰를 초안 판에 묶지 않아 v3 에도 같은 리뷰로 통과한다. 결론 범위 문장 변경이 철학 정렬에 닿는지는 원 세션이 판단한다.
- v3 를 만들지 않고 v2 를 등록하면: R-6 · R-7 정정을 DESIGN §12 에 적고, R-8(원장 응답 커밋)을 등록 전에 마친다.
