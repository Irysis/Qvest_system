# P1S01 사전등록 초안 격리 교차 점검 v1

- 점검자: 격리 교차 점검(서브에이전트). 이 판의 설계 · 구현에 참여하지 않았고 측정 결과를 보지 않았다. 기술 점검만 했다(판단 · 철학 정렬은 다른 감독 몫). 점검 시각 2026-11-11 13:45~14:05.
- 대상(md5 앞 8자리)
  - 판 폴더: `prereg_draft.json`(draft_version 1 · 029bcae4) · `prereg_draft.md`(465aa0ed) · `drafts.json`(f3511b4f · v1 review = null) · `round_spec.json`(52d8eecc) · `specs/P1S01_E2_C0.json`(fd9a012f) · `specs/P1S01_E3_RX0.json`(398e153c) · `standing_rules.md`(2e01cddd) · `DESIGN.md`(1e64e2e0) · `behavior_card_cfg_at_prereg.json`(6a2a1d21)
  - 코어 v1(매니페스트 e70ac0af): `standing.R`(83a57088) · `p1.R`(004f1026) · `register.R`(d8629123) · `rules.R`(0cf24c4d) · `pins.R`(3c793976) · `spec.R`(ad95e361)
  - 그 밖: `RELEASES.json`(44ee4449) · `round.sh`(0736dcc0) · `README.md`(82530f4a) · `02_Infrastructure/ops/standing_board_run.sh`(b661b6cb)
  - 시험: `test_round_core_v1_standing.R`(0b5be604) · `test_round_core_v1_flow.R`(12a7cddf)
  - 점검 시점 HEAD = eaa899df9
- **판정: revise** — 초안 v1 은 지금 등록할 수 없다.
  - 판정 경로 핀 22개 가운데 1개(`02_Infrastructure/alpha_search/run_paper_replication.R`)가 초안을 만든 13:33 뒤에 다른 커밋(e66d9f0aa · 13:48:15)으로 바뀌었다. 그래서 `rc_pins_mismatches` = 1건이고, `rc_register` 조건 ③(register.R:118-119)이 등록을 거부한다.
  - 나머지 여덟 항목은 재도출 값이 모두 맞았다: 초안 재구성 · 재핀 · 규칙 승계 · 생성 함수 핀 · 입구 규칙 문서 · 시행 회계 · 시험 · 정기 실행 배선.
  - 그 핀 1건만 초안 시점 md5 로 두면, `rc_draft` 식이 지금의 사양에서 초안을 바이트 그대로 다시 만든다(029bcae4).
- **건수: 필수 1 · 권고 5 · 선택 4**

## 0. 정보 경계 선언

- 연 것
  - 판 폴더: `prereg_draft.json` · `prereg_draft.md` · `drafts.json` · `round_spec.json` · `specs/` 2개 · `standing_rules.md` · `DESIGN.md` 전문 · `git diff HEAD` · `git show HEAD:specs/*` · `behavior_card_cfg_at_prereg.json`(md5만).
  - 코어 v1
    - 전문: `standing.R` · `p1.R` · `register.R` · `rules.R` · `pins.R` · `spec.R` · `load.R`.
    - 일부: `util.R`(1-47 · 225-249) · `driver.R`(31-37 · 120-140) · `metrics.R`(17-40) · `cell_eval.R`(72-80) · `p4.R`(860-895 · grep).
    - `round.sh` 전문 · `README.md`(1-67 · 119-175) · `RELEASES.json`(메타 · 파일 md5 대조).
  - 운영
    - `standing_board_run.sh` 전문 · `ops/scheduler/Qvest_StandingBoard.bat` · 예약 작업 `Qvest_StandingBoard` 메타(Get-ScheduledTask) · 작업 명령 `jobs/Qvest_StandingBoard.cmd`.
    - `.cache/scheduler_logs/standing_board_task.log` 꼬리 5줄(rc 줄만) · `data_selfheal_tick.sh`(grep).
  - 시험: `test_round_core_v1_standing.R` 전문 · `test_round_core_v1_flow.R`(1-40 · grep).
  - 계약 · 설정
    - 서명 줄 · 기본값만: `factor_db_connector.R` · `factor_combinable.R` · `06_Registry/factor_combinable.json`(direction).
    - grep: `rf_cell_engine.R` · `rf_replication_verify.R`(315-345 · n_variants) · `beta_controlled_alpha.R`(lag) · 헌장(55%) · `superfan_protocol.md` §11-1 · `superfan-philosophy.md` · `q_judgment_ledger.py`.
    - git log 만: `lookahead_detector.R` · `factor_db_vintage.R` · 커넥터 · 결합용 뷰.
  - 사전등록(규칙 · 회계 · 핀 경로만)
    - P1R01 `prereg.json`: rules · metrics · 최상위 키.
    - P2R05 `prereg.json`: registered_at · status · operational_pins 경로 목록 · git md5 이력.
    - `stage_artifacts/programs/*/*/prereg.json`: 코드로 회계 값만(경로 · 칸 · n).
  - 등록부 `research_programs.json`: P1R01 · P2R05 round 항목의 round_id · status · prereg · prereg_md5 키만. `grade` · `cr_verdict` · 성과 키는 출력하지 않았다.
  - 판단 원장 `q_judgment_ledger.json`: reviews 메타(id · role · trigger · round · file · at)만. 리뷰 · 도전 본문은 열지 않았다.
  - `06_Registry/behavior_card.json` · `grade_v3.json`: md5 · 최상위 키만.
- 안 연 것
  - 모든 라운드의 `results/`. P1S01 `results/` 는 파일 수만 셌다(0 · 이름 · 내용 미열람).
  - `authoritative_remeasure.json` · `stage_artifacts/replication/**` · 산출물 `behavior_card.json` · `results/standing/*`.
  - Superfan 리뷰 본문(`_supervision/superfan/philosophy/` 는 파일 이름 목록만) · 판단 원장 리뷰 본문 · 2023 이후 성과 수치.
  - 하네스가 넣은 MEMORY 문맥의 성과 문장은 판정 · 권고에 쓰지 않았다.
- 간접 접근 고지
  - 입구 dry-run 은 코드가 레인 산출을 읽는다: `04_holdings.csv` 의 date · weight 두 열, `authoritative_remeasure.json` 의 `replication.source_paper`, 판 표식 메타. 화면에는 사유 코드 · 방향 층 · 판 표식만 띄웠고, 표에 성과 열이 없음을 확인했다.
  - 시험 2종은 P0R01 공유 측정 `eval.json` 을 읽는다. 출력은 `[ok]` 줄 수와 마지막 JSON 줄만 봤다(FAIL 0 — 세부 줄 없음).
- 실행한 것
  - Rscript 임시 스크립트 4개(`mktemp -d` 폴더 · 점검 뒤 삭제). 다음을 재도출했다:
    - 초안 재구성 · 핀 대조 · 시드 재생성 · 계보 회계
    - 규칙 승계 · 생성 함수 핀 · 규칙 문서 재생성
    - 방향 층 탐침 34종 · 입구 dry-run(`rc_standing_scan(dry_run = TRUE)`)
  - `Rscript 08_Tests/programs/test_round_core_v1_standing.R`(94/0) · `test_round_core_v1_flow.R`(41/0).
    - 부수 효과: `.cache/round_core/perf/{P1S99,P1S98,P1R99}_*.jsonl` 에 줄이 더해졌다(시험 설계상 · 저장소 추적 밖).
  - `bash standing_board_run.sh --dry-run` 2회. 환경은 `RC_SA_ROOT` = 임시 가짜 사전등록, `RB_SH` = 임시 배리어 대역이고, 잠금 · 로그는 남지 않는다.
  - git status · diff · log · show, md5sum, Get-ScheduledTask(읽기).
  - `round.sh` 의 register · reviewed · measure · scan(비드라이런) · standing-check 는 돌리지 않았다. standing-check 는 `standing_rules.md` 를 다시 쓰므로 같은 함수를 메모리에서 불러 대조했다.
- 쓴 것: 이 파일 1개.

## 1. 항목별 결과(재도출 값 · 파일:행)

### 1. 초안 무결성 — **핀 1건 불일치(필수 F-1)** · 나머지 일치

| 대조 | 재도출 | 결과 |
|---|---|---|
| `drafts.json` v1 md5 = 디스크 초안 | 029bcae44e00a246bc50a6efe63c3bbf = 029bcae4… · md5_md 465aa0ed = 디스크 md · 판 수 1 · review null | 일치 |
| 초안 `spec_md5` = 지금 `round_spec.json` | 52d8eecc = 52d8eecc · 초안 `spec` 본문 = `rc_spec_load` 결과(.path · .md5 제외) identical | 일치 |
| 초안 `cells[].md5` = 지금 칸 사양 | E2 fd9a012f = fd9a012f · E3 398e153c = 398e153c | 일치 |
| 초안 `pins` → `rc_pins_mismatches()` | **1건** — `핀 파일 md5 변경: 02_Infrastructure/alpha_search/run_paper_replication.R`(초안 65580501 → 지금 6fe62365 · HEAD 블롭도 6fe62365 · 커밋 e66d9f0aa 13:48:15 '충실구현 L-code 의 다음 탐침 문구' · +3/−2) | **불일치** |
| 코어 · 패키지 · R 판 | 매니페스트 e70ac0af(모듈 20) = 지금 = `RELEASES.json`(d10a95697 13:44:49 · 파일별 md5 20/20 일치) · 패키지 5종 · R 4.6.2 | 일치 |
| 초안 전체 재구성(`rc_draft` 식 · register.R:45-63) | 핀 1건을 초안 시점 md5 로 두면 재구성 md5 = 029bcae4(바이트 동일). `rules_resolved` · `sentences` 는 JSON 직렬화 동일. `identical` 거짓은 정수 2L 과 실수 2 의 차이일 뿐이다. `rc_prereg_md` 재생성 = 465aa0ed | 일치 |

- 핀 대상 22 = 기본 18(pins.R:6-13) + 칸 엔진 1(`RP_AUTO_2002_06975/engine.R`) + 칸 사양 2 + 행동 카드 사본 1.
- 바뀐 줄은 L-code `next_probe` 문구다. 상설 측정은 `QVEST_RP_NO_LCODE=1` 로 돈다(standing.R:656). 그래서 측정 경로의 실행 줄은 아니지만, 핀은 파일 단위라 ③ 이 거부한다.

### 2. 재핀 주장(DESIGN §3-1 · §12) — 일치

- **바이트 대조**: HEAD 블롭(E2 157d4c6d · E3 1e0cf370)과 지금 파일은 CRLF 로 50/90줄이다. 다른 줄은 E2 43-44 · E3 84-85 뿐이다. HEAD 바이트에서 `"n_family_at_registration": 260` → 264 와 basis 문장의 '최댓값 260 그대로' → 264 두 군데만 바꾸면 지금 바이트와 같다. 두 필드를 뺀 JSON 도 동일하다.
- **재생성**(같은 인자 · `rc_json_write` 직렬화)
  - `rc_p1_cell_spec("P1S01_E2_C0", "04_Research/strategies/RP_AUTO_2002_06975/engine.R", <사양 root_paper>, "2002.06975", 264, <basis>)` → fd9a012f = 디스크.
  - `rc_standing_seed_respec("…/P0R01_E3_C0.json", "P1S01_E3_RX0", 264, <basis>)` → 398e153c = 디스크.
  - 같은 함수에 260 을 넣으면 HEAD 블롭 두 개(157d4c6d · 1e0cf370)가 그대로 나온다. 재핀 앞뒤 모두 등록 생성 함수의 출력이다.
  - basis 문장은 두 시드 모두 `P1S01 시드(… P2R04 RX0 선례): 계보 2002.06975 앞선 사전등록 회계 최댓값 264 그대로` 문형과 일치한다.
- **회계 재계산**: `rc_standing_nf_prior("2002.06975")` = **264** = 사양.
  - 최댓값을 낸 사전등록: `stage_artifacts/programs/P2_DEFENSE/P2R05_distribution_target/prereg.json`(rx_prereg_v1 칸 4개가 264).
  - 다음 값은 P2R04 260 · P2R03 252 · P3R03 238 · P3R02 228 · P3R01 226 · P0R01 216 순이다.
  - 상설 원장은 아직 없다. `stage_artifacts/programs/P1_RETURN/P1S01_standing_qualification/` 도 없다.
- **`round_spec.json` 차분**: `exposures` 에 2줄을 더한 것뿐이다(DESIGN §12 '4줄 + 2줄'과 같다). `standing_cfg` · `rules` · `cells` 는 HEAD 그대로다.
- P1S01 `results/` 는 파일 0개다. 등록 전 측정 흔적이 없다(R2).

### 3. 규칙 승계 — 일치

- 사양 `rules` 는 `.rcs_p1_template_rules()`(standing.R:828-832 → `rc_init_p1` 선언 p1.R:92-99)와 identical 이다.
- **P1R01 사전등록**(md5 5d577e5d = 등록부 prereg_md5)의 규칙
  - `qualify` = 보는 창 t(α) ≥ `tier_graduation.grade_b_min_portfolio_alpha_t`(t_alpha_min 2) ∧ 보는 창 상승 포착 ≥ uc_floor 0.55.
  - `test_window` = 자격 엔진만 시험 창 alpha_ann > 0 → 사람 쪽 보고.
  - `selection` = 선택 없음.
- **지표 정의**
  - P1R01 `metrics`: `beta_controlled_alpha` · 월간 순수익 vs KOSPI200 · NW lag 3 · 보는 창 / uc = 보는 창 패킷 `behavior.summary.bull_up_capture_median`.
  - 코어: metrics.R:25-31(`ym ≤ τ_D` · `nw_lag = 3`) · cell_eval.R:72(같은 키).
  - 결론: 같은 뜻이다.
- 유일한 차이는 미측정 처리다(P1R01 은 미달로 접었고, P1S01 은 미시험). DESIGN §2 가 공개했다.
- `rc_rules_test_window_use(사양 rules)` = 빈 결과다. 양성 대조로 q_t_alpha 지표를 `t_alpha_test` 로 바꾸면 `[q_t_alpha]` 가 나온다.
  - 판정 시작에서도 다시 검사한다: standing.R:119(사양 검사) · 701(판정 직전) · p1.R:9-17(threshold 만 · report 허용).
- 문턱: `rc_ref_value("02_Infrastructure/worktask/constraint_defaults.json::tier_graduation.grade_b_min_portfolio_alpha_t")` = 2 = 초안 해석값 · value_source 같음. `constraint_defaults.json` 은 핀 3397e490 이다.

### 4. 생성 함수 핀 · 행동 카드 사본 — 일치

- `rc_standing_pin_diff(사양 generator_pin, rc_standing_generator_pin())` = 0건.
  - fn_md5 80f8311f · like_md5 080cfea8.
  - canon: all_hyg_px1000_2000_v1 · 25 · 15 · 200000000 · TRUE(standing.R:80-86).
  - `rc_standing_validate(check_pin = TRUE)` 통과.
- 행동 카드 사본 6a2a1d21 = `06_Registry/behavior_card.json` 6a2a1d21.

### 5. 입구 수리 — 문장과 코드 일치 · 단, 부호 층 간접 사용 미검출(권고 R-2)

- `rc_standing_rules_md(사양)` 재생성 = 디스크 `standing_rules.md` 바이트 동일(2e01cddd).
- 사유 표 14행은 `RC_STANDING_REASONS`(standing.R:38-52)와 코드 · 뜻 모두 identical 이다(규칙 문서 생성 = standing.R:887). DESIGN §3-2 표의 코드 집합 = 코어 집합(어느 쪽에만 있는 것 없음).
- 문장 ↔ 코드 줄

  | 문장 | 코드 |
  |---|---|
  | factor_db_static = 등록부 방향 상수로만 부름 | standing.R:20(상수 집합 registry · defensive) · 347 · 360(문자열 상수만 정적) · 338(모든 호출이 정적일 때만 factor_db_static) |
  | engine_native 허용 시 함께 허용 | standing.R:446(허용 확장) · 476(`dynamic_sign` 판정이 확장 집합을 씀). 탐침 결과: `engine_native` → {engine_native, factor_db_static} · `factor_db_asof` → 그대로 |
  | factor_db_asof = 인자 없음 · ic_asof · 판정 불가 | standing.R:359(인자 없음 = ic_asof) · 360 + 347(ic_asof · 그 밖 상수 = 비정적) · 361(변수 · 식) · 357(대응 실패) · 367-368(do.call · match.fun · get 문자열) · 372(함수 값) |
  | 결합용 뷰 포함 | standing.R:19(`fc_load_month` · `fc_load_months` · `fc_daily`) |
  | 낡은 판 = 표식만 | standing.R:483-486 · 496(열 `factor_db_vintage` 만 · 사유 코드 추가 없음) |

- **기본값 정합**: 커넥터 두 함수는 `match.arg` 첫 값이 `"ic_asof"`다. `fc_*` 는 NULL → `06_Registry/factor_combinable.json` direction.default = `ic_asof` 다. 분류기의 '인자 없음 = ic_asof'와 같다.
- **위치 인자 대응표**(standing.R:22-27)
  - 정본 서명과 같다: load_month_factors · load_daily_factors · fc_load_month · fc_daily(시험 J6 과 같은 판독).
  - `fc_load_months` 는 정본이 `(sig_dates, ...)` 이고 `fc_load_month(d, family = FALSE, ...)` 로 넘긴다. 위치 · 이름 대응이 같음을 손으로 확인했다(J6 대조 밖).
- **탐침 26종 전부 기대대로**
  - `direction = "registry"` · `'defensive'` · `dir =` 부분 일치 → static.
  - `fc_load_month(d, 'registry')` → static. 반면 `fc_load_month(d, dir = 'registry')` 는 `dir` 이 정확히 맞는 별도 인자라 asof.
  - `fc_load_months(ds, 'defensive')` · `fc_daily(1, NULL, NULL, 'registry')` · `load_daily_factors(1, NULL, NULL, TRUE, 'registry')` → static.
  - `qm::` · `E$` 형태 → static. `c('registry')` · 변수 · 'foo' → asof.
  - `lapply(ds, fc_load_month)` · `do.call('fc_daily', …)` · `get('load_month_factors')(…)` → asof.
  - 주석 · 문자열 → engine_native. `IC_Sign` 대소문자 → orientation_layer.
  - `x[, 1]` · 함수 정의(기본값 · `...`)에서도 오류가 없었다.
- **미검출**: 부호 층 함수(`align_factor_direction` · `compute_rolling_ic_all`)를 간접으로 쓰면 탐침 8종 중 4종을 놓친다 — 함수 값(`lapply(…, align_factor_direction)`) · `do.call('align_factor_direction', …)` · `match.fun('compute_rolling_ic_all')` · 별칭 대입. 이 넷은 factor_db_static 또는 engine_native 로 분류돼 **입구를 통과**한다. 원인은 standing.R:334 가 부호 층 함수를 `SYMBOL_FUNCTION_CALL` 토큰으로만 보기 때문이다. 같은 형태의 커넥터 호출은 372 · 367-368 이 보수 판정한다. 직접 호출 · `$` · `::` 형태는 잡힌다 → R-2.

### 6. 시행 회계 — 일치

- 스캔 항목(standing.R:530-531): `nf = max(nf0, lane_n) + 1`.
  - `nf0 = rc_standing_nf_prior(fam)`(288-309)는 다음 셋의 최댓값이다.
    - 앞선 사전등록의 구판 칸 n_family(297-298).
    - 코어 판 칸 가운데 **variant 칸만**의 n_family_at_registration(299-301).
    - 상설 원장 enqueue 의 **variant 행만**(305-307).
  - `lane_n` = `variants_summary.json::n_variants`(311-316). 없으면 대표 1이다. n_variants 는 '논문 방법 N종 — 대표 …' 의 N 이라 대표를 포함한다(rf_replication_verify.R:494 · 518).
  - 결론: 'max(앞선 사전등록 · 상설 원장, 레인 측정 수) + 1'과 같다.
- **시드 무가산**: 시드는 사양의 n 을 그대로 실어 role = reference 로 넣는다(545-558). `nf_prior` 는 reference 칸 · 행을 세지 않는다. `family_root` = paper_key 다(스캔 넣기 611 이 `r$paper_key` 를 넘김).
- 사양 `accounting.rule` 문장 = 골격 문장(855) 동일.
- 시험 C7(새 계보 2 · 변형 3 레인 4 · 시드 무가산)과 H3(판 사이 +1 = 3) 통과.

### 7. 등록 조건 ①~⑧ — 시험 통과 · ⑥ 은 미수령 · ⑦ 범위는 권고 R-4

- **④ 시험**: 사양 `tests` 2종이 실재하고 통과했다.
  - `test_round_core_v1_standing.R` `{"pass":94,"fail":0}` · 17초.
  - `test_round_core_v1_flow.R` `{"pass":41,"fail":0}` · 4초.
  - `RELEASES.json` 의 tests_at_release 값과 같다. register.R:121-127 은 마지막 `{"test"` 줄의 fail 을 읽는다.
- **⑥ 철학 P1**(register.R:80-96)
  - 파일 정규식: `^04_Research/programs/_supervision/superfan/philosophy/[0-9]{8}_[0-9]{4}_P1_P1S01\.md$`(`rc_round_tag` = P1S01).
  - 원장 조건: role philosophy · trigger P1 · **round = `P1S01_standing_qualification`**(전체 id · identical) · 파일 실재 · challenge/stop 도전이 모두 응답되고 open 이 아님 · 열린 보류 요청 없음.
  - 지금 원장에는 P1S01 P1 리뷰가 없다. P1 리뷰 6건 중 최근 것은 P2T0(11-06)이다 → 미충족(동시 진행 예정이라 정상) · 선택 S-3.
- **⑦ 커밋 검사**(register.R:99-104)
  - 범위: 판 폴더(초안 · 점검 목록 · `/results/` 제외) · 코어 v1 · 칸 사양 · ext.
  - 지금 판 폴더 수정분 5개(DESIGN · round_spec · specs 2 · standing_rules.md)는 등록 전 커밋 대상이다(정상).
  - **빠진 고정 대상**
    - 판 폴더 · 코어 밖의 핀 파일 19개(기본 18 + `engine.R`). md5 로 고정되지만 커밋 여부는 검사하지 않는다.
    - 시험 2종(등록 때 md5 만 기록) · `RELEASES.json` · `round.sh` · `standing_board_run.sh`.
    - 입구 의존 `02_Infrastructure/validation/lookahead_detector.R`(사유 `pit_static`). 핀에도 없다 → R-3 · R-4.
- ① · ② · ③ · ⑤ · ⑧: 코드 흐름은 확인했다(register.R:111-143). 이 판은 리허설 기록이 없어 ⑤ 를 건너뛴다. ③ 은 F-1 로 지금 거부된다.

### 8. 정기 실행이 이 판을 알아보는가 — 배선 결함 없음 · 단, 핀 유지(R-1) · 커밋 순서(R-5)

- **발견 조건**(standing_board_run.sh:36-45)을 이 사양이 모두 만족한다.
  - `"standing": true`(L38).
  - 최상위 `  "round_id": "P1S01_standing_qualification"` = 디렉터리 이름(L40 · 2칸 들여쓰기 · CRLF 무관).
  - program `P1_RETURN`(L41).
  - 사전등록 정본 `stage_artifacts/programs/P1_RETURN/P1S01_standing_qualification/prereg.json`(L43) = `rc_paths()$prereg`(register.R:11-16 · `RC_SA_ROOT` 미설정 = 저장소).
- **모의 실행**
  - 가짜 사전등록 + 배리어 대역: `[상설 정기 · 드라이런] 등록된 판 1 · 배리어 free(열림)` · `… P1S01_standing_qualification: scan → pending → 대기 있으면 standing-measure → standing-report --send`.
  - 사전등록이 없으면 조용히 0(지금 상태).
  - 저장소의 상설 판은 이 판 하나다.
- **예약 작업** `Qvest_StandingBoard`
  - 상태 Ready · 매시 :37(시작 11-10 18:37 · PT1H) · 마지막 13:37 rc 0 · 다음 14:37.
  - 작업 명령은 11-11 08:16:19 생성이다. 순서: 관문 → `Qvest_StandingBoard.bat` → `data_selfheal_tick.sh` → `standing_board_run.sh --send` → `chain_tick.sh`. DESIGN §9-4 와 같다.
- **첫 틱 경로**
  - `scan` → `rc_standing_context(mode = "enqueue")`(standing.R:210-231) → `rc_registered`(driver.R:31-37 · 사전등록 md5 = 등록부 — `rc_register` 가 같은 값을 쓴다).
  - 사양 md5 → 생성 함수 핀 → `rc_pins_mismatches` → 판 목록 → 시드 2 + 입구 통과 넣기 → pending → measure-item → judge → report.
  - 건너뛸 결함은 없다. 단, 등록 시점과 틱 사이에 핀 대상이 바뀌면 scan · pending · report 가 모두 '판정 경로 핀 불일치(R2)'로 멈춘다(R-1).
- **입구 미리보기 재도출**(dry-run · 지금)
  - 51 디렉터리 · 입구 통과 1(`RP_AUTO_CLEAN_1908_01112` · 1908.01112 · engine_native · 판 표식 stale · new).
  - 제외 사유: no_handoff 40 · dynamic_sign 11 · not_routed 7 · audit_not_passed 4 · combination 4 · implementation_suspect 4 · no_engine 4 · long_leg_absent 1.
  - 인계 기록이 있는 11편 가운데 dynamic_sign: factor_db_asof(2202.10721 · 2412.12350 · 2601.10732) · orientation_layer(1603.00751 · 1801.01777).
  - DESIGN §3-2 11-11 미리보기 · 사양 `exposures` 마지막 줄과 같다. 스캔 표에 성과 열은 없다.

### 9. DESIGN · 초안 사실 진술 — 대부분 맞음 · 어긋남 3건

- **맞음**
  - 커밋 `838f7147a`(11-10 12:10 · `v1/standing.R` · `test_round_core_v1_standing.R`).
  - fn 80f8311f · 선례 080cfea8 · 핀 파일 22 · P1R01 md5 5d577e5d.
  - 시험 I1 · I2 · B6 · B7 · D6 · H3 · J1~J9 실재 · 통과.
  - 검증기 `.v1001_handoff`(rf_replication_verify.R:315). 인계 항목에 engine_md5 가 없는 것은 §9-3 미결과 같다.
  - E3 의 DB 팩터 3종은 기본 `ic_asof`(rf_cell_engine.R:277-304 · 사양 factors 에 direction 없음).
  - NW lag 3(beta_controlled_alpha.R:24-25) · 헌장 55%(L11 · L19) · 예약 작업 배선(§9-4).
  - §10 '코어 v1 = 11-11 출시 기록(RELEASES.json · e70ac0af)' — DESIGN 을 쓴 13:30 에는 파일이 없었지만 13:44:49 커밋(d10a95697)으로 지금은 참이다. 다만 출시 판 불변을 막는 검사는 미구현이다(RELEASES.json format_note) → R-1.
- **어긋남**
  - §3-1 P2R05 'md5 9ed7b23f' → S-1.
  - §3-2 '1801 교훈이 겨누는 층은 여전히 제외된다' → R-2.
  - §6 'DNN 엔진은 GPU 임대 규칙(WP3) 아래서' → S-2.

## 2. 지적

### 필수

**F-1. 초안 v1 의 판정 경로 핀 1건이 지금과 다르다 → 등록 ③ 거부(등록 불가)**
- 무엇: `02_Infrastructure/alpha_search/run_paper_replication.R` 핀 md5. 초안(13:33:09)은 65580501 인데, 지금(작업 트리 = HEAD)은 6fe62365 다.
- 원인: 커밋 e66d9f0aa(13:48:15 · L-code `next_probe` 문구 +3/−2 · 다른 세션 작업)이다.
- 결과: `rc_register` 의 `rc_pins_mismatches`(register.R:118-119)가 '핀 불일치(초안 뒤 판정 경로가 바뀌었다)'로 멈춘다. v1 에 ok 를 기록해도 등록되지 않는다.
- 고치는 법
  1. 핀 대상(아래 R-4 목록)과 코어 v1 에 진행 중인 편집이 없는지 확인한다.
  2. `round.sh <판> draft` 로 v2 를 만든다.
  3. 3절 기준으로 v1 → v2 차분을 확인한다.
  4. v2 점검 기록 → `reviewed 2 … ok` → 등록한다.
- 그 밖의 재도출(항목 1~9)은 v1 에서 모두 맞았다. 차분이 3절 그대로면 이 점검의 나머지 결과는 v2 에 그대로 승계된다.

### 권고

**R-1. 핀 유지 — 출시 판 불변이 관례뿐이라 등록 뒤 짧은 시간 안에 판이 멈출 수 있다**
- 사실 1: 이 판은 v1 매니페스트 전체(모듈 20 — 상설 경로와 무관한 `p2.R` · `p3.R` · `p4.R` · `pair.R` 포함)와 레인 러너 `run_paper_replication.R` 를 md5 로 쥔다.
- 사실 2: `RELEASES.json` format_note 스스로 'load.R:2 의 검사가 막는다는 미구현'이라고 적었다.
- 근거: 11-10 하루에만 코어 v1 커밋이 8건(p4 · driver · util · register · standing …)이었다. 오늘은 핀 파일 1개가 초안 15분 뒤에 바뀌었다(F-1).
- 결과: 등록 뒤 이런 편집이 한 번만 들어와도 fail-closed 로 판 전체가 멈춘다. scan · pending · judge · report 가 '판정 경로 핀 불일치(R2) — 새 판 등록이 필요하다'로 서고, P1S02 의식(초안 · 교차 점검 · P1 · 등록)이 다시 필요하다. 상설 판의 목적(의식 1회)과 부딪친다.
- 제안
  1. 등록 직전에 다른 세션에 '22개 핀 + `round_core/v1/` 동결'을 알린다(재개 저널 · 세션 메모).
  2. P4 사슬 수리 같은 코어 변경은 v2 로 낸다(출시 원칙 그대로).
  3. `RELEASES.json` 대조 검사(v1 디렉터리 매니페스트 ≠ 출시 값이면 실패)를 후속 과제로 앞당긴다.
  4. 멈춤 감지는 superfan_watch `standing_board.scan_stale`(26시간)뿐이니, 핀이 깨진 날은 사람이 바로 볼 수 있게 standing-status 확인을 운영 순서에 둔다.

**R-2. 부호 층 함수의 간접 사용이 입구를 통과한다(정적 판정 비대칭) · DESIGN §3-2 문장이 넓다**
- 코드: standing.R:334 는 `align_factor_direction` · `compute_rolling_ic_all` 을 호출 토큰(`SYMBOL_FUNCTION_CALL`)으로만 본다. 커넥터 · 결합용 뷰는 함수 값 · 간접 호출까지 동적으로 본다(372 · 367-368).
- 영향: 11-10 수리로 factor_db_static 이 허용됐다. 그래서 '등록부 방향으로 부른 뒤 `lapply(…, align_factor_direction)` · `do.call('align_factor_direction', …)` · `match.fun('compute_rolling_ic_all')` · 별칭으로 다시 정렬'하는 엔진이 factor_db_static(또는 engine_native)으로 입구를 통과한다(탐침 4/4).
- 지금 레인 엔진 가운데 두 함수를 쓰는 것은 1603.00751 · 1801.01777 둘뿐이고 둘 다 직접 호출이라 잡힌다. 현재 영향은 0이다.
- 제안
  1. v2 코어: 두 이름을 커넥터처럼 다룬다(어느 기호 토큰이든 · do.call/match.fun/get 문자열 포함).
  2. 지금: DESIGN §3-2 '1801 교훈이 겨누는 층은 여전히 제외된다'를 '직접 호출 · `$` · `::` 형태의 부호 층은 제외된다'로 좁힌다. 간접 형태는 충실도 감사(`audit_not_passed`)가 받친다고 적는다.
- PIT 문제는 아니다(as-of 정렬은 C13 허용 경로). 자격의 귀속(엔진 기전인가, 부호 타이밍인가) 문제다.

**R-3. 핀이 '판정에 닿는 전체'(pins.R:1)에 못 미친다 — 시드 E3 측정 경로 · 입구 의존이 빠졌다**
- 이 판의 핀은 코어 기본 18 + 엔진 + 칸 사양 2 + 행동 카드 사본(22)이다.
- 시드 E3(DB 팩터 3 · entropy · 순위 버퍼)의 측정 경로는 다음 파일을 직접 부른다(rf_cell_engine.R source 목록). 모두 앞선 등록 P2R05 의 operational_pins(50개)에는 있었고 여기에는 없다.
  - `02_Infrastructure/factor_db/factor_db_connector.R` — 11-09 방향 의미 변경 3회.
  - `02_Infrastructure/portfolio/weight_catalog.R` · `02_Infrastructure/reinforcement/rf_rebalance.R` · `02_Infrastructure/reinforcement/rf_base_cache.R`(기저 신호 캐시 키).
  - `02_Infrastructure/replication/replication_harness.R` · `02_Infrastructure/contracts/backtest_result_contract.R`.
- 입구 사유 `pit_static` 의 판정 함수 `02_Infrastructure/validation/lookahead_detector.R` 도 핀 밖이다. 등록 뒤 바뀌면 새 판 없이 입구 결과가 바뀐다('입구 규칙은 등록본에 고정' — DESIGN §2 와 어긋남).
- 제안: 어차피 v2 초안을 만들어야 하므로 사양 `pins.files`(pins.R:38)에 위 파일을 더한다. factor_db_static 엔진이 쓰는 `factor_db/factor_combinable.R` 도 넣을지 함께 정한다.
- 대가: 핀이 늘면 R-1 의 멈춤 빈도가 오른다. 더하면 사양 md5 가 바뀌므로 v2 점검은 차분 대조가 아니라 항목 1 · 7 · 8 재도출이 필요하다.

**R-4. 등록 직전 커밋 상태를 핀 전체로 확인한다(⑦ 범위 밖)**
- register.R:100 의 ⑦ 은 판 폴더 · 코어 v1 · 칸 사양만 본다. 판 폴더 · 코어 밖 핀 19개와 시험 2종은 md5 로만 고정되고 커밋 여부는 보지 않는다.
- 미커밋 상태로 등록하면 핀 md5 가 git 이력에 없는 바이트를 가리킨다(재현 불가).
- 제안: 등록 직전 `git status --porcelain -- <초안 pins.files 22경로> 08_Tests/programs/test_round_core_v1_standing.R 08_Tests/programs/test_round_core_v1_flow.R 04_Research/programs/_lib/round_core/` 가 비어 있는지 본다(곧 커밋할 판 폴더 파일은 예외).
- 지금 상태
  - 핀 19개는 깨끗하다. `run_paper_replication.R` 은 커밋됐지만 초안과 md5 가 다르다 = F-1.
  - 핀 밖이지만 `ic_asof` 대체 방향 · 등록부 방향의 원천인 `02_Infrastructure/factor_db/factor_registry.json` · `custom_factors.json` 은 미커밋 수정 중이다(다른 세션).

**R-5. 등록 → 커밋 → 측정 순서가 매시 틱과 경합한다**
- 경합: `standing_board_run.sh` 는 `prereg.json` 이 생기는 순간 이 판을 잡는다(L43). 다음 :37 틱(관문 대기 뒤)이 scan → 시드 측정 → 판정 → `--send` 보고까지 간다.
- 상설 경로에는 '사전등록이 커밋됐는가' 검사가 없다(standing.R · round.sh standing-measure · driver precheck 모두). 등록과 커밋 사이에 틱이 끼면 '사전등록 → 커밋 → 측정'이 시각상 뒤집힌다.
- 제안: 직전 틱이 끝난 직후 한 창에서 등록 → 커밋(사전등록 두 사본 + 등록부)까지 마친다. 직전 틱 종료는 `.cache/standing_board_run.lock` 이 없고 `standing_board_task.log` 끝 줄이 rc 줄인 것으로 확인한다. 다음 틱은 14:37 이다.

### 선택

- **S-1.** DESIGN §3-1 'P2R05 … 사전등록 md5 9ed7b23f'는 11-06 등록 판의 md5 다. 지금 정본(파일 · 등록부)은 11-08 R2 재핀 2회(3f6d3d50f → dedc7a49 · 1d2abf6bd → bf45f4e7) 뒤의 **bf45f4e7** 이다. 회계 264 는 바뀌지 않았다. '11-06 등록 9ed7b23f → 11-08 환경 재핀 bf45f4e7'로 적는 편이 정확하다.
- **S-2.** DESIGN §6 'DNN 엔진은 GPU 임대 규칙(WP3) 아래서'에 대응하는 코드가 상설 경로에 없다(standing.R · round.sh · standing_board_run.sh · rf_cell_worker.R grep 0).
  - 첫 틱은 입구 통과 1건(1908.01112 · DNN)을 메인 PC 에서 정본 셀 워커로 바로 잰다.
  - 'WP3'는 §9-5 · §10 에서 쓰기 잠금 뜻으로도 쓰인다.
  - 실제 운영 기대(로컬 측정 · 시간 · RAM)로 고치거나 문장을 지운다.
- **S-3.** 철학 P1 리뷰를 띄울 때 지킬 것
  - 원장 `--round` 는 전체 id `P1S01_standing_qualification` 이어야 한다(register.R:84 identical · 규약 §11-1). 앞선 P3R03 리뷰는 태그 `P3R03` 으로 적혔다 — 그 꼴이면 ⑥ 이 '원장에 없다'로 멈춘다.
  - 파일 이름은 `<YYYYMMDD_HHMM>_P1_P1S01.md` 다.
  - `rc_p1_check` 는 리뷰를 초안 판에 묶지 않는다. 리뷰에 본 초안(json 029bcae4 · md 465aa0ed)을 적어 두면 v1 → v2(핀만) 승계가 추적된다.
- **S-4.** 등록 뒤 등록부를 커밋할 때 주의한다. `06_Registry/research_programs.json` 에 다른 세션의 미커밋 변경 +319/−2줄이 있다(`q_judgment_ledger.json` 도 수정 중). 통째로 커밋하면 남의 변경이 함께 실린다. 등록 줄만 따로 담거나 커밋 서술에 범위를 밝힌다.

## 3. v2 초안 차분 점검 기준(F-1 해소 · R-3 미반영 시)

- v1 → v2 에서 달라도 되는 키는 셋뿐이다.
  - `draft_version`(1 → 2) · `drafted_at`.
  - `pins.files[path = 02_Infrastructure/alpha_search/run_paper_replication.R].md5`(65580501 → 그때 md5).
  - 그 사이 다른 핀 파일이 바뀌었다면 그 항목도 바뀐다. 그 경우 바뀐 파일과 커밋을 적는다.
- 같아야 하는 것
  - `spec_md5` 52d8eecc · `spec` 본문 · `cells[].md5`(fd9a012f · 398e153c).
  - `core.manifest_md5` e70ac0af(= `RELEASES.json`) · `rules_resolved` · `sentences` · `behavior_card_cfg.md5` 6a2a1d21 · 패키지 · R 판.
  - `prereg_draft.md` 는 첫 줄 '초안 v2'만 다르다.
- 이것을 기계 대조(JSON 차분 경로 목록)로 확인하고, 그 결과와 이 파일을 근거로 v2 점검 기록을 남기면 된다.
- R-3 을 반영해 `pins.files` 를 더하면 사양 md5 가 바뀐다. 그때는 항목 1 · 7(시험 재실행) · 8(발견 조건)을 다시 재도출해야 한다.
