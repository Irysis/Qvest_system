# P1S01 사전등록 초안 격리 교차 점검 v3

- 점검자: 격리 교차 점검(서브에이전트 · v1 · v2 점검과 같은 정보 경계). 이 판의 설계 · 구현에 참여하지 않았고 측정 결과를 보지 않았다. 기술 점검만 했다(판단 · 철학 정렬은 다른 감독 몫). 점검 시각 2026-11-11 14:49~15:12.
- 점검 종류: 변경분 점검. 기준 = 점검 v2 3절('v3 를 만들 경우의 차분 점검 기준')과 2절 R-6 · R-7 · R-8 · S-5~S-8.
  - v2 항목 1(무결성 · 핀 수) · 2(차분) · 6(시험 · `rc_p1_check` · `rc_uncommitted`) · 7(발견 조건)을 다시 재도출했다.
  - scan 설정이 바뀌지 않아(2절) v2 항목 3(방향 층 · 입구 표)은 승계한다.
- 대상(md5 앞 8자리)
  - 판 폴더: `prereg_draft.json`(draft_version 3 · 8d867dd6) · `prereg_draft.md`(0b899ac7) · `drafts.json`(125451ca · v2 review = ok · v3 review = null) · `round_spec.json`(c54411a2) · `specs/P1S01_E2_C0.json`(fd9a012f) · `specs/P1S01_E3_RX0.json`(398e153c) · `standing_rules.md`(82d3597f) · `DESIGN.md`(22e0a08b) · `behavior_card_cfg_at_prereg.json`(6a2a1d21) · 점검 v2 `prereg_draft_review_v2.md`(4cc347d6)
  - 대조 기준 v2
    - 사양 v2 = `git show 77f8ab831:…/round_spec.json` = **bdb8b98d**(md5 확인).
    - 초안 v2 본문은 git 에 없다. `f6eba1e7f~1`(= d19e631a6)과 77f8ab831 의 `prereg_draft.json` 은 둘 다 029bcae4(= 초안 v1)다.
    - 그래서 사양 v2 + 지금 핀으로 `rc_draft` 식 재구성을 했다(판 2 · 시각 = drafts.json v2 `at` 14:15:28). 결과 **d7720f29 · md 7c4a292c — drafts.json v2 기록과 바이트 동일**. 이 재구성본을 v2 기준으로 썼다.
    - DESIGN v2 = `git show 77f8ab831:…/DESIGN.md` = d0116189(= 점검 v2 대상).
  - 코어 v1(매니페스트 e70ac0af): `standing.R`(83a57088) · `register.R`(d8629123) · `pins.R`(3c793976) · `p1.R`(004f1026) · `p4.R`(50a749c9) · `RELEASES.json`(44ee4449) · `round.sh`(0736dcc0) — v2 점검 때와 모두 같다
  - 운영: `02_Infrastructure/ops/standing_board_run.sh`(b661b6cb · 같다)
  - 시험: `08_Tests/programs/test_round_core_v1_standing.R`(0b5be604) · `test_round_core_v1_flow.R`(12a7cddf) — 같다
  - 판단 원장: `06_Registry/q_judgment_ledger.json`(30cf8773 · HEAD 블롭 = 작업 트리)
  - HEAD: 시작 · 끝 모두 f6eba1e7f(점검 중 새 커밋 없음).
- **판정: ok(등록 가능)** — 초안 v3 는 지금 등록 조건 ②~⑧ 을 모두 만족한다(① = 이 기록 · `reviewed 3 … ok` 뒤 충족).
  - 사양 v2 → v3 차분은 v2 3절이 허용한 네 곳뿐이다: `pins.files`(+5 · 끝에 덧붙임) · `pins.basis` · `changes_after_review`(고친 [1] · 새 줄 1) · `conclusion_scope[8]`. 나머지 최상위 블록 16개는 바이트 단위로 같다.
  - 핀 31 = 기본 18 + `pins.files` 9 + 엔진 1 + 칸 사양 2 + 행동 카드 사본 1 · 겹침 0 · `rc_pins_mismatches` 0건. 기존 핀 26 의 md5 는 초안 v2 뒤 하나도 바뀌지 않았다.
  - R-6 · R-7 · R-8 이 모두 반영됐고, 새 문장의 사실 진술은 코드 · git 재도출과 맞다. R-8 의 도전 응답 7건은 f6eba1e7f 로 커밋됐다(HEAD 원장 = 작업 트리 · 열린 도전 0).
  - 선택 셋: 제외 근거 문장 하나의 정밀도 · 미핀 두 파일의 추적 · DESIGN 표기 둘. 판정 규칙 · PIT 에 닿지 않고, 사양을 다시 고칠(v4) 이유가 아니다 — DESIGN 쪽 기록으로 충분하다.
- **건수: 필수 0 · 권고 0 · 선택 3**

## 0. 정보 경계 선언

- 연 것
  - 판 폴더
    - 전문: `round_spec.json` · `prereg_draft_review_v2.md` · `drafts.json`.
    - `prereg_draft.json`: 구조 · 기계 대조 · 바뀐 문장만 출력.
    - `DESIGN.md`: v2 → v3 diff 와 §3-2 일부 · §7 · §8 · §9 · §12.
    - `standing_rules.md` · `behavior_card_cfg_at_prereg.json` 은 md5 · 재생성 대조만. 칸 사양 2개는 md5 와 `defense_sleeve` · `kind` 키 grep 만.
  - git: `git show 77f8ab831:` 사양 · 초안 v1 · DESIGN, `git diff 77f8ab831 f6eba1e7f -- DESIGN.md`, `git show --stat`(f6eba1e7f · d6ea880ed · d19e631a6), log · status · ls-files.
  - 코어 v1
    - 전문: `pins.R` · `load.R` · `spec.R`.
    - 일부: `register.R`(1-140) · `standing.R`(12-21 · 50-56 · 198 · 218-228 · 258-290 · 672-730 · grep) · `p1.R`(15-52 · `rc_p1_cell_spec`) · `metrics.R`(1-60) · `cell_eval.R`(45-85) · `p4.R`(38-41 · grep) · `util.R`(grep) · `measure_cell.R`(18-33).
  - 측정 경로(줄 범위 · grep)
    - `rf_cell_engine.R`(38-60 · 70-80 · 106-113 · 270-280 · 545-556 · 580-590 · 808-818) · `run_paper_replication.R`(source 줄 · 894-904 · 940-962) · `rf_cell_worker.R`(100-135).
    - `save_bt_result.R` · `audit_bt_result.R`(715-760) · `rf_sleeve.R`(79-83 · 최상위 문장) · `diagnosis_packet.R` — grep 과 해당 줄.
    - `RP_AUTO_2002_06975/engine.R` 은 source · 커넥터 · 결합용 뷰 grep 만(0건). P0R01 선례 칸 사양은 키 목록 · `defense_sleeve` 값만.
  - 운영 · 출시: `standing_board_run.sh`(30-50) · `RELEASES.json`(v1 키 · 매니페스트 · tests_at_release).
  - 판단 원장(메타만)
    - 도전 C-20261111-001~005 · 013~021: id · review · role · grade · status · hold_request · responses 개수와 kind.
    - 리뷰 R-20261111-001 · 002: role · trigger · round · file · challenges 목록.
    - HEAD 블롭과 작업 트리를 대조했다. claim · evidence · alternative · 응답 본문은 출력하지 않았다.
  - 결정 기록부 `P4-BASE-POOL-GRADE-PATH-TAU-20261111`: 키 목록 · status · owner · decided_by · opened_at · decided_at · options 개수와 머리 6자 · `default_until_decided` 앞 120자.
    - 마지막 필드는 v2 경계보다 하나 더 본 것이다(DESIGN §8 '결정 전 기본값' 대조용 · 절차 문장 · 수치 없음).
- 안 연 것
  - 모든 `results/`. P1S01 `results/` 는 파일 수만 셌다(0).
  - `authoritative_remeasure.json` · `stage_artifacts/replication/**` · 산출물 `behavior_card.json` · `results/standing/*`.
  - Superfan 리뷰 본문 · 판단 원장의 리뷰 · 도전 본문 · 2023 이후 성과 수치 · 설계 README 본문 · 등록부 `research_programs.json`(이번 점검엔 필요 없었다).
  - 하네스가 넣은 MEMORY 문맥은 판정 · 지적에 쓰지 않았다.
- 간접 접근 고지
  - 시험 2종은 P0R01 공유 측정 `eval.json` 을 읽는다. 출력은 임시 파일로 받아 `[ok]` 줄 수 · `[FAIL]` 줄 수 · 마지막 JSON 줄만 봤다.
  - `rc_p1_check` 는 원장 전체를 읽는다. 화면에는 ok · why · reviews · n_challenges · files 만 띄웠다.
- 우연 열람: 없음.
- 실행한 것
  - Rscript 임시 스크립트 2개(`mktemp -d` 폴더 · 점검 뒤 삭제)
    - 무결성 · 초안 재구성(v3 · v2) · 핀 구성 · 매니페스트 · 규칙 문서 재생성 · `rc_standing_validate`.
    - 등록 조건: `rc_p1_check`(작업 트리 원장 · HEAD 원장 사본) · `rc_uncommitted` · ⑧ 경로.
  - python(표준 라이브러리): JSON 경로 차분 · 배열 정렬 대조 · 새 문장 패턴 검사 · 원장 메타 추출.
  - `Rscript` 시험 2종. 부수 효과: `.cache/round_core/perf/{P1R99_core_selftest,P1S98_standing_selftest2,P1S99_standing_selftest}.jsonl` 에 줄이 더해졌다(시험 설계상 · git 무시 경로 · check-ignore 확인).
  - `round.sh` 는 어떤 하위 명령도 돌리지 않았다. `standing_board_run.sh` 도 돌리지 않았다(발견 조건은 코드 · 사양 바이트 대조로 승계 — 6절).
  - 점검 중 작업 트리 변화는 15:01 에 다른 세션 · 훅이 쓴 2개뿐이다(`04_Research/01_reports/qvest_v10_2_audit_redesign_20261110/README.md` · `qepm/observability/events.jsonl`). 핀 · 판 폴더 · 코어 · 원장 밖이다.
- 쓴 것: 이 파일 1개.

## 1. 항목별 결과(재도출 값 · 파일:행)

### 1. 초안 무결성 — 일치

| 대조 | 재도출 | 결과 |
|---|---|---|
| `drafts.json` 마지막 판(v3) md5 = 디스크 초안 | 판 수 3 · v3 md5 8d867dd6 = 디스크 · md5_md 0b899ac7 = 디스크 · at 14:48:05 = 초안 drafted_at · review null. v2 기록 = d7720f29 · review ok · file_md5 4cc347d6 = 디스크 점검 v2 · git_head d19e631a6 | 일치 |
| 초안 `spec_md5` = 지금 `round_spec.json` | c54411a2 = c54411a2 · 초안 `spec` = `rc_spec_load` 결과(.path · .md5 제외) identical · 초안 `spec` → `rc_json_write` = c54411a2(사양 파일 바이트 재현) | 일치 |
| 초안 `cells[].md5` = 지금 칸 사양 | E2 fd9a012f · E3 398e153c = 디스크(v2 와 같다) | 일치 |
| `rc_pins_mismatches(초안 pins)` | **0건**(14:5x · HEAD f6eba1e7f) | 일치 |
| `rc_pins_compute(사양)` = 초안 pins | files · core · packages · r_version 모두 identical | 일치 |
| 핀 구성 | 기본 18(pins.R:6-13) + `pins.files` 9(round_spec.json:160-170) + 엔진 1(`RP_AUTO_2002_06975/engine.R` · pins.R:27-35) + 칸 사양 2 + 행동 카드 사본 1 = **31**. 겹침 0 · 합집합 31 = 초안 경로 집합 | 일치 |
| 코어 매니페스트 | 지금 e70ac0af = `RELEASES.json` v1 `manifest_md5` = 초안 `core` · 파일별 md5 20/20 · 초안 `pins.core.files` identical | 일치 |
| 패키지 · R 판 | data.table 1.18.6.1 · jsonlite 2.0.0 · arrow 26.0.0 · PerformanceAnalytics 2.0.8 · bbdetection 1.0 · R 4.6.2(2026-10-29 ucrt) — v1 · v2 와 같다 | 일치 |
| 초안 전체 재구성(`rc_draft` 식 · register.R:45-63 · 판 3 · 시각 = 초안 값) | md5 8d867dd6(바이트 동일) · `rc_prereg_md` = 0b899ac7 · `rules_resolved` identical | 일치 |
| 규칙 문서 · 상설 검사 | `rc_standing_rules_md(v3 사양)` = 82d3597f = 디스크(v2 와 같다) · `rc_standing_validate(check_pin = TRUE)` 통과 · 허용 방향 층 = engine_native · factor_db_static(standing.R:446) | 일치 |

핀 31(md5 앞 8자리 · ★ = v3 새 핀)

- `02_Infrastructure/`
  - `alpha_search/run_paper_replication.R` 6fe62365 · `backtest_harness.R` 12b6c291 · `config.R` 6ec23fe8
  - `contracts/`: backtest_result_contract.R d1d6f81d · behavior_card.R 5ee201eb · beta_controlled_alpha.R cf44057a · diagnosis_packet.R a9dfc1ab · essence_score.R 484a0e46 · grade_v3.R b7ebf223 · matched_controls.R 1b9d8152 · measurement_axis.R 113e9efc · ★save_bt_result.R d724252b · tilt_attribution.R 54a200ba · tilt_attribution_config.json 29030383
  - `factor_db/`: ★factor_combinable.R 077bf8f4 · ★factor_db_connector.R fcf7e529
  - `ops/rf_cell_worker.R` 522f7fe2 · ★`portfolio/weight_catalog.R` 3944fdee
  - `reinforcement/`: rf_axes.R 861cd5ea · rf_base_cache.R f6fef4f9 · rf_cell_engine.R 26993a04 · ★rf_rebalance.R d94bdf3a
  - `replication/replication_harness.R` d0b94e14 · `validation/lookahead_detector.R` 044f3ff1 · `worktask/constraint_defaults.json` 3397e490
- 판 폴더: behavior_card_cfg_at_prereg.json 6a2a1d21 · specs/P1S01_E2_C0.json fd9a012f · specs/P1S01_E3_RX0.json 398e153c
- `04_Research/strategies/RP_AUTO_2002_06975/engine.R` 6b6a8e1a · `06_Registry/grade_v3.json` 97f8b60c · `06_Registry/matched_controls.json` f0cf960a

### 2. v2 → v3 차분 — 허용된 네 곳뿐

- 사양 JSON 경로 차분(사양 v2 bdb8b98d → v3 c54411a2 · 최상위 키 순서 같다)
  - ① `$.pins.files[4..8]` 추가 5개 — 끝에 덧붙였다(앞 4개 그대로).
  - ② `$.pins.basis` 고침.
  - ③ `$.changes_after_review`: 4 → 5줄. 배열 정렬 대조(difflib) 결과는 다음과 같다.
    - [0] 같음. v2 [1] → v3 [1](고침) + v3 [2](새 줄).
    - v2 [2..3] = v3 [3..4](바이트 같음 · 한 칸 밀림).
    - 판 폴더 문서에 이 배열의 위치 참조는 없다(grep 0). 점검 v2 가 인용한 `[1]` 은 지금도 같은 줄(고친 줄)을 가리킨다.
  - ④ `$.conclusion_scope[8]` 고침. 10줄 그대로 · [0..7] · [9] 같음.
  - 인덱스 기준 경로 차분 11건 = 위 네 곳뿐이다(③ 의 밀림 3건 포함).
- 불변(블록 단위 바이트 비교)
  - schema · program · round_id · template · core_version · tau_d · purpose · hypothesis · standing.
  - `standing_cfg` 전부: edition · program · generator · generator_pin(fn_md5 80f8311f · like_md5 080cfea8 · canon) · scan(orientation_admit 포함 9 키) · accounting · rejudge_prior_editions · report · superfan.
  - cells · rules · selection · exposures(8줄) · changes_after_superfan(5줄) · tests · behavior_card_cfg.
  - 사양 1-122행은 v2 와 바이트 동일하다.
- 초안 수준(재구성 v2 d7720f29 ↔ v3)
  - 같은 것: schema · program · round_id · status · core · `rules_resolved` · `sentences` · `cells` · `behavior_card_cfg`(6a2a1d21).
  - git 의 초안 v1(029bcae4)과도 `rules_resolved` · `sentences` · `cells` · `behavior_card_cfg` · `core` · `pins.core` · `pins.packages` · `pins.r_version` 이 identical 이다.
  - 다른 것: `draft_version` · `drafted_at` · `spec_md5` · `spec` · `pins` 뿐이다. `pins` 는 files 에 5 항목이 더해졌을 뿐이고, 기존 26 의 md5 는 26/26 같다.
- 기존 핀 26
  - 초안 v2(14:15:28) 뒤 31 핀 어느 것에도 커밋이 없다(`git log --since` 0건).
  - 다른 세션 커밋 2건(d6ea880ed · d19e631a6 · 14:33)은 핀 · 판 폴더 · 코어 밖이다(파일 목록 대조).
  - 바뀐 파일 없음 — 적을 커밋이 없다.
- `prereg_draft.md`(63줄)
  - 다른 줄은 넷이다: 제목 v2 → v3 · 사양 md5 · 결론 범위 9번째 줄 · '파일 26' → '파일 31'.
  - `changes_after_review` · `pins.basis` 는 md 에 실리지 않는다(`rc_prereg_md` · register.R:28-42). 사양 차분과 같다.

### 3. 새 핀 5개 — 실재 · 커밋됨 · R-6 근거가 코드와 맞다

| 핀 | md5 | 마지막 커밋 | 7일 커밋(11-04 14:00~) | `git status` |
|---|---|---|---|---|
| `contracts/save_bt_result.R` | d724252b | 918dcbc0b 07-03 | 0 | 빈 줄 |
| `reinforcement/rf_rebalance.R` | d94bdf3a | 49302fb48 09-21 | 0 | 빈 줄 |
| `factor_db/factor_db_connector.R` | fcf7e529 | 357cedcc4 11-09 | 3 | 빈 줄 |
| `portfolio/weight_catalog.R` | 3944fdee | fdc172b49 11-10 | 1 | 빈 줄 |
| `factor_db/factor_combinable.R` | 077bf8f4 | 61868edf2 11-10 | 4 | 빈 줄 |

- 다섯 모두 실재 · 추적됨 · 디스크 = HEAD 블롭이다.
- 31 핀 전체 + 시험 2 + `round_core/` 의 `git status --porcelain` = 빈 결과다. 31 모두 추적되고 디스크 = HEAD 블롭이다.
- R-6 근거(코드 줄)
  - save_bt_result.R 이 판정 입력을 쓴다.
    - 적재 · 호출: run_paper_replication.R:68 적재 → :831 `bt <- audit_bt_result(bt)` → :832 `save_bt_result(bt, OUT_DIR, …)`.
    - 쓰는 파일: save_bt_result.R:54-57 · :69 가 `02_nav.csv` · `03_period_returns.csv` · `04_holdings.csv` · `05_benchmark_returns.csv` 를 쓴다.
    - 판정이 읽는 길 ①: diagnosis_packet.R:82 `.dp_read` 가 03 · 05 · 02 를 읽는다. metrics.R:16-31 이 이를 월 복리로 묶어 `t_alpha_vis` 등을 낸다.
    - 판정이 읽는 길 ②: cell_eval.R:62-63 의 축 감사(04_holdings)와 진단 패킷(상승 포착 · CAGR · 위기 하락노출)도 이 파일들에서 나온다.
    - → 맞음.
  - rf_rebalance.R 을 모든 칸이 적재한다.
    - rf_cell_engine.R:44 최상위 적재(조건 없음) · :47 `rf_rb_parse(SPEC[["rebalance"]])`(없으면 항등 — :41-42 주석).
    - 시드 E3 칸 사양 :44-45 `rebalance.kind = rank_buffer`.
    - → 맞음.
  - 처치 · 방향 경로 셋
    - factor_db_connector.R = rf_cell_engine.R:276(팩터 kind db — 시드 E3 의 DB 팩터 3).
    - weight_catalog.R = :552(카탈로그 arm — E3 weighting kind catalog).
    - factor_combinable.R 은 셀 엔진 · 러너 · 워커 · 시드 엔진이 적재하지 않는다. 레인 엔진이 결합용 뷰(`fc_*` · standing.R:19)를 부를 때의 경로다(지금 factor_db_static 엔진 0개 — v2 3절).
    - `pins.basis` 의 '시드 E3 와 factor_db_static 엔진의 측정'은 셋을 묶어 말한 것으로 맞다.
  - 7일 변경 실측 3 · 1 · 4회는 문장과 같다. 기존 26 핀 7일 22커밋(11-09 4 · 11-10 15 · 11-11 3)도 v2 실측과 같다.
- 제외 둘의 근거(사양 `changes_after_review[1]` · `pins.basis`)
  - `audit_bt_result.R`
    - 돌려준 bt 가 그대로 저장된다(run_paper_replication.R:831-832). 수익 표는 읽기만 한다(:104 · :154 · :258 · :349 · :609 · 그 표에 `:=` 없음).
    - 덧붙이는 것: 감사 표(:721) · manifest `integrity_status`(:737-743) · `frequency_mislabel_detected`(:747) · critical FAIL 이면 metrics `is_official` · `metric_type`(:732-734).
    - 상설 판정 경로는 이 표식을 읽지 않는다. round_core v1 · diagnosis_packet · behavior_card · beta_controlled_alpha · essence_score · grade_v3 · 워커에서 `integrity_status` · `is_official` grep 0건이다.
    - 워커는 `authoritative_remeasure.json` 이 있으면 그 `status` 와 무관하게 ok 를 쓴다(rf_cell_worker.R:129-132 · 러너 :901 의 FAIL 은 판정에 닿지 않는다).
    - → '판정 입력 아님'은 맞다. '감사 표만'은 코드보다 좁다 → S-9.
  - `rf_sleeve.R`
    - rf_cell_engine.R:45 최상위 적재 · :48 `rf_sl_parse(SPEC[["defense_sleeve"]])` 를 모든 칸이 부른다.
    - NULL 이면 NULL 을 돌려주고(rf_sleeve.R:80) 엔진 :484 블록을 건너뛴다. 최상위 문장은 library · 상수뿐이다.
    - 시드 두 칸은 `defense_sleeve: null` 이다. 생성 함수(p1.R `rc_p1_cell_spec`)는 선례 P0R01_E2_C0(080cfea8 · 생성 함수 핀)를 복사하는데 그 값이 null 이고 바꾸지 않는다.
    - → '이 판의 칸은 전부 없음 · 무동작'은 지금 코드 기준으로 맞다. 추적 문제는 S-10.

### 4. `conclusion_scope[8]` 새 문장 — 원장 열과 맞다 · 경계 위반 없음

- 문장의 보는 창 열 10개 ↔ `RC_STANDING_VIS_COLS`(standing.R:53-54)의 지표 열 10개가 1:1 이다.
  - t(α) = `t_alpha_vis` · 연 α = `alpha_ann_vis` · β = `beta_vis` · PORT_t = `port_t_vis` · 월 수 = `n_vis` — 판정 표 p1.R:32 ← metrics.R:25-31.
  - 상승 포착 중앙값 = `uc_vis` · CAGR = `cagr_vis` — p1.R:33 ← metrics.R:35-41 ← cell_eval.R:72(`behavior.summary.bull_up_capture_median` · `performance.strategy.cagr`).
  - 위기 하락노출(중앙 · 최악 · 수) = `dd_capture_median_vis` · `dd_capture_worst_vis` · `n_crisis_vis` — judge 가 붙인다(standing.R:705-708).
  - 기록: `vis <- row[RC_STANDING_VIS_COLS ∪ qualify ∩ 열]` + window(standing.R:717-718) → verdict 사건 `visible`(:722).
  - 지표 아닌 칸(engine · code · status · error · qualify · window)은 '보는 창 열' 목록 밖이라 빠진 것이 아니다.
  - 시험 창 열(t_alpha_test · alpha_ann_test · n_test · uc_test)은 `visible` 에 없고, 사람 쪽 판정 파일에만 있다(standing.R:713-716). r2_violation 판정(:679)에는 `visible` 이 없다.
- 'P4 기저 풀은 이 가운데 상승 포착 중앙값만 읽는다'
  - p4.R 은 원장을 `rc_standing_qualified()` 로만 읽는다(p4.R:149 · 다른 원장 판독 grep 0).
  - 그 함수가 verdict `visible` 에서 꺼내는 값은 `uc_vis` 하나다(standing.R:278). 나머지는 경로 · md5 · paper_key · artifacts · verdict_at 이다.
  - 소비처는 p4.R:185(현금 기계)다. → 맞음.
- 뒤 절('집중 · 숨은 현금 날 · … 은 원장에 없다(판 2) · P2 진단 패킷 판독')은 v2 와 바이트 같다(점검 v2 5절에서 맞음).
- 경계
  - 바뀐 사양 문장 4개(conclusion_scope[8] · changes_after_review[1] · [2] · pins.basis)를 패턴으로 훑었다: % · 소수 · 2023 이후 연도 · 등급 글자 · '지표 = 값' · 시험 창 · OOS. **0건**이다.
  - 문장 안의 수는 식별자(판 1 · 판 2 · 빈칸 1 · 7 · 24 · MC8)와 커밋 · 변경 횟수뿐이다.
  - **성과 수치 · 시험 창 정보 · 등급 값 없음.**

### 5. 등록 조건 ①~⑧ — ②~⑧ 충족

- ① 마지막 초안 v3 의 점검 = 이 기록(`reviewed 3 … ok` 뒤 충족).
  - `rc_mark_reviewed` 전제(디스크 초안 = v3 md5 · register.R:71)는 참이다.
  - 이 파일 이름은 ⑦ 제외 정규식(`prereg_draft` · register.R:103)에 걸린다 — 쓰고 나서도 ⑦ 결과가 바뀌지 않는다.
- ② 사양 · 칸 사양 md5 = 초안(1절).
- ③ 핀 0건(1절).
- ④ 사양 `tests` 2종 재실행
  - `test_round_core_v1_standing.R`: `{"test":"round_core_v1_standing","pass":94,"fail":0,"total":94}` · 16초 · `[ok]` 94 · `[FAIL]` 0.
  - `test_round_core_v1_flow.R`: `{"test":"round_core_v1_flow","pass":41,"fail":0,"total":41}` · 3초 · `[ok]` 41 · `[FAIL]` 0.
  - 마지막 `{"test"` 줄 fail = 0 이다(register.R:124-125 가 읽는 줄). `RELEASES.json` tests_at_release(94/0 · 41/0)와 같다.
- ⑤ 리허설 기록 없음 → 건너뜀(register.R:120).
- ⑥ `rc_p1_check("P1S01_standing_qualification")` = **ok**(작업 트리 원장 · HEAD 원장 사본 둘 다).
  - reviews `R-20261111-002` · 파일 `_supervision/superfan/philosophy/20261111_1351_P1_P1S01.md`(정규식 register.R:83 · 실재).
  - n_challenges(challenge | stop) = 4.
- R-8 재도출(HEAD f6eba1e7f 원장 블롭 = 작업 트리 30cf8773 · 원장 `git status` 빈 줄 · 도전 184 · 리뷰 20 같음)

| 도전 | 리뷰 · 역할 | status | 응답(개수 · kind) | hold_request |
|---|---|---|---|---|
| C-20261111-001 | R-…-001 · judgment | rebutted | 1 · rebut | 거짓 |
| C-20261111-002 · 003 | R-…-001 · judgment | accepted | 1 · accept | 거짓 |
| C-20261111-013 · 014 · 015 · 016 | R-…-002 · philosophy | accepted | 1 · accept | 거짓 |

  - **open 0** · 응답 없는 도전 0. v2 때 'HEAD 에서는 open · 응답 0'이던 상태가 f6eba1e7f 로 커밋됐다 — R-8 해소.
  - C-001~003 은 판단 T1 도전이라 `rc_p1_check` 대상 밖이다(status 만 봤다).
- ⑦ `rc_uncommitted` = **0건**.
  - 같은 범위(판 폴더 · `round_core/v1` · 칸 사양 2)의 날 `git status --porcelain` 도 0줄이다 — 초안 · drafts.json 까지 커밋돼 있다.
- ⑧ 사전등록 정본 `stage_artifacts/programs/P1_RETURN/P1S01_standing_qualification/prereg.json` 은 아직 없다(`RC_SA_ROOT` 미설정 = 저장소).

### 6. 정기 실행 인식 — v2 와 같다(승계)

- 판단 근거가 모두 v2 점검 때와 같다.
  - 발견 코드 `standing_board_run.sh`(b661b6cb · L36-45)와 `rc_paths`(register.R:10-17 · d8629123)가 같다.
  - 사양 1-122행이 v2 와 바이트 동일하다. 그 안에 :3 program · :4 round_id(2칸 들여쓰기 최상위) · :10 `"standing": true` 가 있다.
  - v3 가 바꾼 줄(:142 · :147-148 · :164-169 · :171)은 배열 · 객체 안쪽(깊은 들여쓰기)이라 L38 · L40 · L41 의 grep · sed 에 닿지 않는다.
  - 저장소의 `"standing": true` 사양은 이 판 하나다.
- → v2 항목 7(모의 실행 두 벌 · 첫 틱 경로)을 승계한다. 첫 틱의 핀 대조(standing.R:222-223)는 31 핀 판 초안 그대로 돈다.

### 7. DESIGN v3 수정 문장 — 사실 어긋남 없음 · 표기 둘(S-11)

| 문장(DESIGN 행) | 재도출 | 결과 |
|---|---|---|
| §3-2 L41 `dynamic_sign` 행(S-7) | '허용 = engine_native · factor_db_static(11-10 수리 · orientation_admit 명시 · factor_db_asof 허용 = 9절 결정 대기 1)'. 사양 :37-40 · `rc_standing_orient_admitted` · §9 '11-11 상태' 줄과 맞다. 앞 절 '정본 커넥터(as-of IC 3단 부호) → factor_db_asof'는 as-of 조건이 붙어 standing.R:14-16(인자 없음 · ic_asof · 비상수 → asof · registry/defensive 상수 → static)과 어긋나지 않는다 | 맞음 · S-7 반영 |
| §6 L73(S-8) | '≥' · '13:4x 시점 관측값'으로 고쳤다 | 반영(관측값 자체는 재도출 불가) |
| §7 L75 머리(S-7) | '요약(정본 = 사양 exposures 8줄 · 11-11 등록 전 고지 4줄 포함)'. 사양 exposures 8줄 가운데 '(11-11 등록 전 고지)' 머리 줄은 [4..7] 4줄이다 | 맞음 · S-7 반영 |
| §8 L88(S-5) | '도훈 결정 전까지 … 결정 전 기본값 · (가)(나)(다) 가운데 도훈'. 결정 기록: status open · owner dohoon · decided_by 없음 · options 3((가) · (나) · (다)) · `default_until_decided` 필드 실재(사슬 판 등록 없음 · 정정 전까지 사슬을 열지 않음 · 기저를 고를 때는 상설 통과 행) | 맞음 · S-5 반영 |
| §8 L89(S-6) | 'v1 은 다시 열지 않는다 — 코어 v2 · 예외로 v1 을 고치면 매니페스트가 바뀌어 핀 불일치로 멈추고 P1S02'. pins.R:55-58(매니페스트 대조) · standing.R:222-223(불일치 = 넣기 · 측정 · 판정 멈춤 · 새 판) · RELEASES immutability 와 맞다 | 맞음 · S-6 반영 |
| §8 L90(S-8) | 'p4.R 지표 `worst_name_contrib_deep_vis` — 꼬리표 N4' — p4.R:40 '# N4 집중(빈칸 1)' | 맞음 · 뜻 겹침 해소 |
| §9-6 L100(S-8) | '철학 note C-20261111-019' · 'C-20261111-020'. 둘 다 실재 · review R-20261111-002 · role philosophy · grade note · closed_note | id · 역할 · 등급 맞음 · 내용 대응은 검증 밖(본문 미열람) |
| §12 L126 새 행 '초안 v2 → v3' | d7720f29 · 점검 v2 ok · 필수 0 · R-6(핀 +5) · R-7 · R-8 — 사실 맞음. 'v2(14:16'은 drafts.json at 14:15:28 이다 | 맞음 · 표기 S-11 |
| §12 L127 핀 행 | 26 → 31 · 다섯 파일 · run_paper_replication.R:68 · :832 · rf_cell_engine.R:44 · '실측 0회 · 마지막 09-21' · '7일 3 · 1 · 4회' · '26개 7일 22커밋' — 모두 재도출과 같다. 제외 둘은 3절('감사 표만'이 좁다 → S-9). 옛 행의 '첫 판정 때 git 변경 유무 기록' 절은 빠졌다 — 대상 4파일이 핀에 들어가 필요 없어졌다. 남은 제외 2파일은 추적이 없다 → S-10 | 맞음 · S-9 · S-10 |
| (안 바뀐 행) §12 L128 | '(철학 N1 · T1 N2)' — 리뷰 본문 번호가 남아 있다 | 표기 S-11 |

## 2. 지적

### 필수 — 없음

### 권고 — 없음

### 선택

- **S-9.** 제외 근거 문장 '`audit_bt_result.R`(감사 표만 덧붙임 · 판정 입력 아님)'(사양 `changes_after_review[1]` · `pins.basis` · DESIGN §12 L127)은 코드보다 좁다.
  - 실제로는 감사 표(:721) 말고도 manifest `integrity_status`(:737-743) · `frequency_mislabel_detected`(:747)를 붙이고, critical FAIL 이면 metrics 의 공식 여부를 내린다(:732-734).
  - 돌려준 bt 전체가 저장 입력이다(run_paper_replication.R:831-832).
  - 결론('판정 입력 아님')은 맞다. 수익 표를 바꾸지 않고, 상설 판정 · 워커가 이 표식을 읽지 않는다(3절).
  - 사양을 고칠(v4) 이유는 아니다. DESIGN §12 에 정밀한 문장을 남긴다. 예: '감사 표 · manifest 무결성 표식(critical FAIL 이면 metrics 공식 여부)만 덧붙이고 수익 표는 바꾸지 않는다 — 상설 판정은 그 표식을 읽지 않는다'.
- **S-10.** 제외 2파일은 모든 상설 측정이 적재하지만 핀 밖이다. v3 는 '첫 판정 때 git 변경 유무 기록' 절도 지웠다 — 지금은 이 둘의 변경을 잡는 장치가 없다.
  - `audit_bt_result.R`: run_paper_replication.R:66 · :831 · 7일 0회 · 마지막 09-25.
  - `rf_sleeve.R`: rf_cell_engine.R:45 · :48 · 7일 1회 · 9a35a915b 11-10.
  - '무동작 · 판정 입력 아님'은 지금 코드의 성질이다. 등록 뒤 이 파일이 바뀌면(예: `rf_sl_parse(NULL)` 의 거동 · 감사가 수익 표를 고침) 판은 멈추지 않은 채 측정이 달라질 수 있다.
  - 실제로 일어날 확률은 낮다. 그러나 v2 R-6 이 지적한 종류(pins.R:1 '핀 = 판정에 닿는 전체')의 남은 몫이다.
  - 제안(사양 변경 없음): DESIGN §9-6 판 2 핀 후보에 두 파일을 적거나, 첫 판정 때 `git log <등록 커밋>.. -- <두 파일>` 결과를 재개 저널 · DESIGN §12 중 한 곳에 남긴다고 위치까지 정한다(v2 S-8 ② 와 같은 요구).
- **S-11.** DESIGN 표기 둘.
  - §12 L126 'v2(14:16 …)' → drafts.json v2 `at` 은 14:15:28 이다. 바로 위 v1 → v2 행은 13:33:09 를 '13:33'으로 적었다 — 같은 방식이면 '14:15'.
  - §12 L128 '(철학 N1 · T1 N2)' 는 리뷰 본문 번호라 추적되지 않는다(v2 S-8 ③ 의 남은 하나). 사양 `changes_after_superfan[4]` 가 같은 조치를 '철학 P1 note C-20261111-017 · 판단 T1 note C-20261111-005'로 적었다 — 원장 id 로 바꾼다. (N 번호 ↔ id 대응은 사양 문장에서 추정했다 · 리뷰 본문으로 확인하지 않았다.)

### v2 지적의 반영 상태(재도출)

- R-6: 반영. 핀 +5 · 근거 문장 정정(rf_rebalance.R 0회 · 3 · 1 · 4회) · 제외 둘을 정했다. 남은 것 = S-9 · S-10(선택).
- R-7: 반영. `conclusion_scope[8]` = 실제 보는 창 열 10개 · P4 가 읽는 값 = 상승 포착 하나(4절).
- R-8: 반영. f6eba1e7f · HEAD 원장 = 작업 트리 · 열린 도전 0(5절).
- S-5 · S-6 · S-7: 반영(7절).
- S-8
  - ① '≥': 반영.
  - ② '첫 판정 때 기록' 절: 삭제됐다. 대상이 핀으로 들어가 필요 없어졌고, 남은 제외 2파일 몫은 S-10 이다.
  - ③ N 번호: L90 · L100 은 반영됐고 L128 이 남았다(S-11).

## 3. 등록까지 남은 것(참고 · 재도출 아님)

- `round.sh <판> reviewed 3 <이 파일> ok` 뒤 등록이다.
- 등록 직전 R-1 · R-4 · R-5 절차(다른 세션 동결 질의 · 핀 31 `git status` · 직전 틱 종료 직후 한 창)를 밟는다.
- v3 에서 핀에 든 셋은 7일 3 · 1 · 4회 바뀐 파일이다. 등록 직전 `rc_pins_mismatches` 0건을 한 번 더 보고, 어긋나면 v4 다. 그 경우 이 기록의 1 · 2 · 5절을 다시 재도출하고, 6절은 사양 1-122행이 같으면 승계한다.
- 이 파일은 ⑦ 제외 정규식에 걸려 미커밋이어도 등록을 막지 않는다. 등록 커밋에 함께 싣는다.
