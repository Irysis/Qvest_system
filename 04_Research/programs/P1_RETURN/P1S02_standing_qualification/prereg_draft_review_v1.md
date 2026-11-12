# P1S02 사전등록 초안 격리 교차 점검 v1

- 점검자: 격리 교차 점검(서브에이전트). 초안을 만든 세션과 맥락을 공유하지 않았다. 이 판의 설계 · 구현에 참여하지 않았고 측정 결과를 보지 않았다. 기술 점검만 했다(판단 · 철학 정렬은 다른 감독 몫). 점검 시각 2026-11-11 23:33~23:52 · HEAD 시작 · 끝 모두 `1b1bda18d`.
- 점검 종류: 첫 점검(초안 v1 전체).
- 대상(md5 앞 8자리)
  - 판 폴더: `prereg_draft.json`(draft_version 1 · **de259d86**) · `prereg_draft.md`(71a0c8e9) · `drafts.json`(v1 review = null) · `round_spec.json`(89b014c4) · `specs/P1S02_E2_C0.json`(687d6517) · `specs/P1S02_E3_RX0.json`(3a085178) · `standing_rules.md`(3c0213bb) · `DESIGN.md`(63fe7eff) · `behavior_card_cfg_at_prereg.json`(6a2a1d21) · `tools/`(init_p1s02.R · prejudge_check.R · p1s02_seed_watch.sh)
  - 코어 v3(매니페스트 4d00113a = `RELEASES.json` v3) · 앞 판 `P1S01_standing_qualification/`(사양 · 등록본 prereg.json · 원장 사건 종류만)
  - 운영: `02_Infrastructure/ops/standing_board_run.sh` · 예약 작업 `Qvest_StandingBoard`(상태 · 트리거 · 실행 줄만)
- **판정: revise** — 판정 규칙 · 문턱 · 선택 규칙 · 시드 사양 · 핀 md5 는 모두 재도출과 맞고 지정 시험 4종도 통과한다. 그러나 등록 전에 막아야 할 것이 둘 있다.
  - F-1: 등록과 `tick_hold` 사이에 무인 틱이 판을 먼저 집는 창이 있다. 무인 틱은 '측정 + 판정 + 실발송'을 한 번에 한다.
  - F-2: 사양의 '핀 = 판정에 닿는 전체'에 판정 경로 파일 3개가 빠졌다.
  - 판정이 아니라 해석에 닿는 사실 진술도 고쳐야 한다: 시드 재학습 문장 · 측정 관문 문장 · 입구 격자 문장 · 공시 누락.
  - 사양을 고치는 항목(F-2 · R-1~R-4 · R-6)은 한 번에 초안 v2 로 묶을 수 있다. F-1 은 사양 밖(판 폴더 파일 · 절차)이라 초안을 바꾸지 않는다.
- **건수: 필수 2 · 권고 6 · 선택 6**

## 0. 정보 경계 선언

- 연 것
  - 판 폴더 전문: `round_spec.json` · `prereg_draft.md` · `prereg_draft.json` · `DESIGN.md` · `standing_rules.md` · 칸 사양 2개 · `tools/` 3개 · `drafts.json`.
  - 코어 v3 전문: `pins.R` · `register.R`. 일부 · grep: `standing.R`(1-65 · 86-335 · 440-970 · 1055-1075 · 1160-1189) · `p1.R`(9-17 · grep) · `metrics.R`(grep) · `rules.R`(grep) · `cell_eval.R`(grep) · `round.sh`(120-150 · grep).
  - 측정 경로: `rf_cell_engine.R`(40-200 · 280-300 · 560-615 · 828-840 · source 줄) · `run_paper_replication.R`(source 줄 · 625-660) · `measurement_axis.R`(140-180) · `weight_catalog.R`(150-170 · 270-300 · 505-535 · 226-238 · 696-711 · grep) · `backtest_harness.R`(40-60) · `factor_db_connector.R`(55-80 · 130-142).
  - 앞 판: P1S01 사양 대조(R 스크립트) · 등록본 prereg.json 의 `rules_resolved` 값 · 핀 경로 · 생성 함수 핀 · `tick_hold` 문장 · 상설 원장의 사건 종류 · code · ok 만 · `prereg_draft_review_v3.md`(형식 선례 · 1-130).
  - 설계 README §2-3 · §2-4 · §2-6 · §6-3 · §6-4 · §8 · §9 · `BUILD_EDITION2.md` 57-163 · `staging/sched_test.R`.
  - `RELEASES.json` v3(키 · known_limits 10줄) · 레인 엔진 7개의 `VARIANT <-` 줄과 FIDELITY `headline_variant` 줄(grep).
- 안 연 것
  - 모든 `results/`(P1S02 는 비어 있다) · `stage_artifacts/replication/**` · `authoritative_remeasure.json` · 산출 `behavior_card.json` · `results/standing/*`.
  - Superfan 리뷰 본문 · 판단 원장 본문 · 설계 README 의 분류표.
  - 2023 이후 성과 수치 · 등급.
- 우연 열람(1건): `git diff -- 02_Infrastructure/factor_db/factor_registry.json`(다른 세션의 미커밋 변경) 출력에서 맞춤 팩터 `RP_1603_00751` 정의 문자열 속 '등급 B' 표기를 보았다. 이 판의 판정 · 지적에는 쓰지 않았다. 판정 경로 대조 목적의 diff 였다.
- 실행한 것
  - Rscript 임시 스크립트(세션 스크래치 폴더): 핀 md5 대조 · 사양 대조(P1S01 ↔ P1S02) · 시드 칸 사양 재생성(임시 파일) · 생성 함수 핀 · `rc_standing_validate` · 규칙 문서 재생성 md5 · 시행 회계 출처 추적 · 변형 기본값 대조.
  - `staging/sched_test.R <구판(git show 526d72f12:…/engine.R → 스크래치)> <신판>`.
  - 시험 7종: 사양 `tests` 4종 + 관련 3종. 출력은 스크래치 파일로 받아 마지막 JSON 줄 · FAIL 줄 수만 봤다.
  - `git status` · `git log` · `git show --stat` · `git diff --stat`. PowerShell `Get-ScheduledTask`(읽기) · job `.cmd` · `.bat` 읽기.
  - `round.sh` 의 하위 명령은 하나도 돌리지 않았다. `standing_board_run.sh` · `prejudge_check.R` · `p1s02_seed_watch.sh` 도 돌리지 않았다(읽기만).
- 쓴 것: 이 파일 1개. 다만 사고가 하나 있다 — 첫 명령에 섞인 `cat > "$TMP/x"`(표준 입력 대기)가 멈춰 TaskStop 했다. 저장소 밖 임시 경로이고 저장소에는 아무것도 쓰지 않았다.

## 1. 판정

**revise.** 필수 F-1 · F-2 를 해소하면 ok 다. 권고를 함께 반영해 초안 v2 를 만들면 변경분 점검으로 충분하다(3절).

## 2. 지적

### 필수

**F-1. 등록 직후 무인 틱이 판 2 를 먼저 집는다 — 첫 판정 절차(판정 전 점검 10항목)를 건너뛰고 측정 · 판정 · 실발송까지 간다**

- 주장
  - DESIGN §5 의 첫 판정 절차는 두 가지를 정했다. 판정 전 점검 10항목을 본 뒤에 `judge` 한다. 그리고 "등록 직후 `tick_hold` 를 두고 첫 판정 뒤 지운다"(DESIGN.md:56).
  - BUILD 진행표의 순서는 `register → 등록 커밋 → tick_hold 두기 → scan` 이다(BUILD_EDITION2.md:119).
  - 그런데 무인 틱은 이미 켜져 있고, 등록본(prereg.json)만 생기면 그 판을 처리한다. `register` 와 `tick_hold` 사이(등록 커밋 시간 포함)에 매시 :37 틱이 닿으면 다음이 일어난다.
    - 시드 2건과 입구 통과 엔진을 넣는다.
    - DNN 시드를 잰다. 시드 감시 셸이 지키는 측정 시각 창 · 메모리 하한 · 지문 20분 안정은 거치지 않는다.
    - 판정 전 점검 없이 판정하고, 결과를 실발송한다.
- 근거
  - 예약 작업 `Qvest_StandingBoard`: State = Ready · 반복 PT1H · 시작 2026-11-10T18:37. 실행 줄은 `02_Infrastructure/ops/scheduler/Qvest_StandingBoard.bat` → `bash 02_Infrastructure/ops/standing_board_run.sh --send`.
  - 판을 고르는 규칙(standing_board_run.sh:41-49): `standing: true` · round_id = 폴더 이름 · `stage_artifacts/programs/<prog>/<rid>/prereg.json` 존재 · `tick_hold` 없음. 셋째 조건은 `rc_register` 가 쓴다(register.R:138).
  - 한 틱 = scan → 대기 항목이 있으면 `standing-measure` → `standing-report --send`(standing_board_run.sh:5 · 120-121).
  - `standing-measure` = 대기 항목마다 `measure-item` → 곧바로 `judge`(round.sh:136-143). 판정 전 점검이 끼어들 자리가 없다.
  - `rc_standing_measure_item` 의 관문은 데이터 신선도 · GPU(레인 측정 0 + 임대)뿐이다(standing.R:864-871). 시각 창 · 메모리 하한은 감시 셸에만 있다(p1s02_seed_watch.sh:6 · 84-89).
  - `tick_hold` 를 등록 **전에** 두면 등록 조건 ⑦ 에 걸린다. 미커밋 검사의 제외 정규식은 `prereg_draft|drafts[.]json|/results/|rehearsal/out` 뿐이다(register.R:103). 그래서 `tick_hold` 를 먼저 두려면 함께 커밋해야 한다.
- 고치는 법
  - `tick_hold`(첫 줄 = 사유 · 예: "판 2 첫 판정 전 점검 전 — 세션이 measure-item → prejudge_check → judge")를 판 폴더 커밋에 **함께 넣은 뒤** `register` 한다. 등록 직후 틱이 와도 HELD 로 건너뛴다(standing_board_run.sh:47).
  - DESIGN §5-4 · BUILD S5 의 순서 문장을 'tick_hold(커밋) → register' 로 고친다.
  - 사양 · 초안은 바뀌지 않는다(`tick_hold` 는 핀 · 사양 밖).

**F-2. 핀 '판정에 닿는 전체'에 판정 경로 파일 3개가 빠졌다 — 바뀌어도 판이 멈추지 않은 채 판정 입력이 바뀐다**

- 주장: 사양 `pins.basis`(round_spec.json:171)는 "pins.R '핀 = 판정에 닿는 전체'"라고 말한다. 다음 3개는 핀(기본 18 + `pins.files` 10 + 엔진 · 칸 사양 · 카드 사본)에도, basis 의 제외 목록에도 없다.

| 파일(md5 앞 8 · 마지막 커밋) | 판정에 닿는 호출 경로 | 닿는 칸 |
|---|---|---|
| `02_Infrastructure/factor_db/factor_z_standard.R`(c82870c7 · 61095bae1 10-14) | 워커 `rf_cell_worker.R:79` → `run_paper_replication.R:634-636` `ma_inject_universe` → `measurement_axis.R:171` `ma_membership` → :148-155 `sys.source(factor_z_standard.R)` · `corp_action_member`(위생 멤버십 = K200 열) → `rf_cell_engine.R:227-232` `.universe_filter` | **모든 칸**(유니버스 ALL_HYG) |
| `02_Infrastructure/portfolio/advanced_weights.R`(9706fcba · 68f2367b7 09-07) | 시드 E3 `weighting = catalog lean:entropy` → `rf_cell_engine.R:569`(`backtest_harness.R` 적재) → `backtest_harness.R:53` `source(advanced_weights.R)` → `weight_catalog.R:226-238` `.wc_lean_carrier_fn` 가 `calc_entropy_weights`(advanced_weights.R:348) 호출 | E3 비중 |
| `02_Infrastructure/methods/method_registry.R`(a4a8d90b · fdc172b49 11-10) | `weight_catalog.R:686`(래퍼 환경 적재) → :709-710 `wrap_adapter(raw, …)` — 카탈로그 arm 비중의 정규화(Σw · 상한) · 실패 시 EW 폴백 | E3 비중 · 이후 카탈로그 칸 전부 |

- 근거(대조)
  - 핀 32 의 경로 집합 = 초안 `pins.files`(prereg_draft.json:261-390). 세 파일은 없다.
  - basis 의 제외 목록은 `audit_bt_result.R` · `rf_sleeve.R` · 비중 카탈로그 JSON 뿐이다.
  - P1S01 점검 v1 R-3 · v2 R-6(`save_bt_result.R`)이 같은 종류를 권고로 지적했다. 이번에 필수로 올린 이유는 둘이다. 위생 멤버십은 모든 칸의 유니버스를 정하는 판정 입력이다. 그리고 basis 문장이 '전체'를 단언한다.
- 덜 중요한 미핀(판단 근거만 · 핀 불요로 본다): `factor_db/factor_dup_scan.R`(dedup 켤 때만 · factor_db_connector.R:134-141), `F1. QT_to_xts.r`(backtest_harness.R:46 · 형 변환 도구), `ops/refresh_barrier.R`(운영 관문 · 값에 닿지 않음), `factor_registry.json`(E3 의 DB 팩터 3개는 방향 = ic_asof 기본이라 등록부 방향을 읽지 않는다 · 자료면).
- 고치는 법
  - 세 파일을 `pins.files` 에 더하고, basis 에 위 덜 중요한 4개의 제외 이유를 한 줄 적는다.
  - 사양 md5 가 바뀌므로 초안 v2 → 변경분 점검을 거친다.
  - 대안: 코어 기본 핀(pins.R:6-13)에 넣으려면 v4 가 필요하다. 이번 판은 사양 쪽이 맞다.

### 권고

**R-1. '다시 학습되므로 같은 값이 아니다' — 재학습이 원인이라는 서술이 스케줄 대조 결과와 어긋난다**

- 위치: `hypothesis`(round_spec.json:9) · `exposures[1]`(:125).
- 근거
  - `sched_test.R` 재현(7/0): S4 = 신판 268개월 · 첫 달 2004-07-30. S5 = "겹치는 달(2005-01 이후 262개월)은 시작일과 무관하게 창 · 번호 · 시드가 같다".
  - BUILD_EDITION2.md:81: "겹치는 달의 학습은 같은 입력 · 같은 시드다".
  - 값이 달라지는 원인은 보는 창 앞에 6개월(2004-07~12)이 더해진 것이다. 실효 시작 · 월 수가 바뀐다. GPU 학습의 비결정성이 있다면 그것도 원인이다. 2005 이후 달의 재학습 입력은 같다.
- 고치는 법: "판 2 의 시드는 기저 신호가 6개월 앞당겨져(2004-07 월말~ · 겹치는 2005-01 이후 달의 학습 창 · 시드는 같다) 측정 창이 달라지므로 그 결과와 같은 값이 아니다"처럼 고친다.

**R-2. 측정 관문 · 입구 격자 문장이 코드 조건보다 넓거나 좁다**

- `conclusion_scope[3]`(round_spec.json:138) "월말 격자 밖 신호의 측정은 판정으로 가지 않는다"
  - 코드 조건은 `n_superseded > 0 ∨ n_offcal > 0` 이다(standing.R:845-848 · rf_base_align.R:26). 즉 한 달에 신호 둘 이상이거나 달력 밖 날짜인 경우다.
  - 월말이 아닌 날짜의 신호가 한 달에 하나뿐이면(`n_moved > 0`) 통과한다. 바로 다음 줄 `[4]` 도 분기 · 60거래일 격자 엔진을 잰다고 말한다. 두 줄이 서로 다른 말을 한다.
- `conclusion_scope[2]` · DESIGN §4 의 `base_off_month_grid` = "주간 · 일간 신호 엔진"
  - 코드 조건은 보는 창에서 한 달력 월에 신호일이 2개 이상인 달이 **하나라도** 있는 경우다(standing.R:515-518 · 모수 없음).
  - 그래서 20거래일 격자처럼 '대략 월간'인 엔진도 가끔 한 달에 두 번 걸리면 제외된다(측정에 가도 관문에서 실패).
- 고치는 법
  - [3] → "기저가 한 달에 신호 둘 이상(덮임 n_superseded > 0)이거나 달력 밖 날짜(n_offcal > 0)인 측정".
  - [2] → "보는 창에 신호일이 2개 이상인 달력 월이 하나라도 있는 엔진(주간 · 일간 · 20거래일 격자 포함)".

**R-3. RELEASES v3 known_limits 가운데 판정 해석에 닿는 둘과, 달 스냅의 지연이 결론 범위에 없다**

- 대조(known_limits 10줄 → `conclusion_scope`)
  - 실렸다: 1(주간 미구현 · [2]) · 2(변형 스위치 · [12]) · 3(열 확장 · [13]) · 4(폭 필요조건 · [2] — 단 '패널 판독 불가면 막지 않는다'는 문장 없음).
  - 해석에 닿지 않는다: 7(P2 상설 판 없음 · 이 판 판정 무관) · 8(출시본 대조 없음 · 이 초안은 매니페스트 4d00113a 를 핀해 보증된다) · 10(v1 시험 격리).
  - 빠졌다
    - **6. 실효 시작 규칙의 보유 수가 수치 먼지를 센다.** `Weight != 0`(README §2-6). 시드 E3 는 entropy 비중이라 작은 비중이 생길 수 있다. 보유 수가 부풀면 '폭 ≥ 보유 × 2'가 늦게 서서 실효 시작(측정 창)이 바뀔 수 있다.
    - **9. 최신 판 우선은 읽을 수 있는 원장만 본다.** `[6]`(round_spec.json:140)은 "기저 풀은 최신 판의 판정을 읽는다"고 무조건으로 적었다. 실제로는 사슬이 끊긴 뒤 판 원장은 건너뛰고 앞 판 통과가 되살아날 수 있다(standing.R:276). 판 1 은 판정 0건이라 지금 판 1 → 2 사이에는 실제 영향이 없다. 판 3 부터 닿는다.
    - (known_limits 밖) **달 스냅의 지연.** 월말이 아닌 날짜에 내는 신호(60거래일 격자 · 월초 신호 월간 엔진)는 그 달 월말로 옮겨진다. 지연은 최대 약 21거래일이다(README §6-3 · BUILD:65). `[4]` 는 '항등 · 갈아탄다'만 적었다.
    - 5(레인 하네스 체결 지연)는 셀 경로 판정에 직접 닿지 않는다. 입구 `long_leg` 가 레인 보유 표를 읽지만 날짜만 보고 판정하지 않는다. 생략해도 된다.
- 고치는 법: `conclusion_scope` 에 위 셋을 한 줄씩 더한다(4 의 '판독 불가 = 사유 없음'도 [2] 에 덧붙인다).

**R-4. "판 2 가 판 1 의 항목을 다시 받는다" — 자동 승계가 아니라 '입구를 다시 지나면 넣는다'이다**

- 근거
  - `rejudge_prior_editions = true` 가 하는 일은 둘뿐이다. 옛 판 원장에 있는 엔진 md5 를 '이미 판정'으로 치지 않고(standing.R:741), 옛 판에 있어도 넣는 것을 막지 않는다(standing.R:662-665).
  - 판 1 원장의 항목(1908.01112)은 판 2 입구(v3 사유)를 다시 지나야 들어온다. DESIGN §6 은 그 엔진이 `portfolio_only_base` 로 빠진다고 적었다.
  - 판 1 시드 2건은 판 2 시드(새 code · 새 사양)로 대체된다.
- 위치: `conclusion_scope[6]`(round_spec.json:140) · DESIGN §2 '옛 판 항목'.
- 고치는 법: "판 1 원장에 있는 엔진도 판 2 입구를 다시 지나면 넣는다(자동 승계 없음 · 1908.01112 는 지금 portfolio_only_base)".

**R-5. 판정 전 점검 스크립트가 10항목 중 셋(5 · 9 · 10)을 '대조'가 아니라 '출력'으로만 본다**

- 근거(prejudge_check.R)
  - 5: 권위 기록의 실효 시작 날짜가 **있는지**만 본다(:40). 기대 날짜(2005 기본값이 남지 않았는가)와 대조하지 않는다. 대신 `start_injected` 를 본다(:54).
  - 9: 덮임 · 달력 밖만 멈춤 사유다(:55). 엔진 신호일 수 · 첫 날짜는 찍기만 한다. 레인 패널 대조(:57-61)도 개수 출력이다.
  - 10(후보 폭): 별도 검사가 없다. 머리(:5)는 '실효 시작 규칙이 선 날이 있는가'라고 했지만 5 의 날짜 존재로만 대신한다.
- 시드는 기대값을 이미 안다: `sched_test` 로 첫 엔진 신호일 2004-07-30 · 268개월(2005-01 이후 262).
- 고치는 법: DESIGN §5 에 시드 기대값(첫 엔진 신호일 · 엔진 신호일 수 · 시작 주입 · 실효 시작이 2005-01 이 아님)을 적고 세션이 대조한다. 또는 스크립트에 `--expect-first` · `--expect-n` 인자를 둔다(판 폴더 도구라 핀 · 사양 밖).

**R-6. 사양 `tests` 에 판 2 변경의 검증 시험 셋이 없다 — 등록 조건 ④ 가 다시 돌리지 않는다**

- 근거
  - DESIGN §2 표는 기저 캐시 판 v3 의 검증을 `test_rf_base_cache_key.R` · `test_rf_base_cache_seed.R` 로 적었다(DESIGN.md:22).
  - BUILD S4 는 진단 계약 시험 `test_round_core_v3_diag_contract.R`(실제 셀 엔진 진단 ↔ 관문)을 출시 근거로 적었다(BUILD:118).
  - 사양 `tests`(round_spec.json:151-156)에는 셋 다 없다.
- 지금 상태: 셋 다 통과한다 — 38/0 · 18/0 · 8/0(마지막 줄 JSON 확인).
- 고치는 법: 사양 `tests` 에 셋을 더한다(초안 v2 에 함께).

### 선택

- **S-1.** DESIGN §5 1단계에 `scan`(시드 넣기)이 없다. 원장에 시드가 없으면 `measure-item` 은 "상설 원장에 그런 항목이 없다"로 멈춘다(standing.R:856). 감시 셸도 scan 을 하지 않는다. BUILD S5 에는 있다(:119). §5 에 '`tick_hold` 아래 손으로 `scan` → 시드 2건 넣기'를 적는다.
- **S-2.** `prejudge_check.R --eval` 은 `results/<code>/eval.json` · `eval.key` 를 쓴다(cell_eval.R:51 · 86). 뒤의 `judge` 가 그 파일을 읽는다(standing.R:932-933). 같은 함수라 판정을 바꾸지 않지만 '읽기 전용 점검'은 아니다. 머리 주석에 적어 둔다.
- **S-3.** 노출 '입구 규칙은 성과 수치를 읽지 않는다'는 '성과 필드를 쓰지 않는다'가 정확하다. `rc_standing_paper` 는 레인 `authoritative_remeasure.json` 을 통째로 읽고 `replication.source_paper` 만 쓴다(standing.R:526-531).
- **S-4.** 코어가 생성한 `standing_rules.md` 25행 "같은 엔진은 판 사이에서도 다시 판정하지 않는다(새 판의 rejudge_prior_editions = true 일 때만)"는 rejudge = true 인 이 판에서 거꾸로 읽힌다. §4 는 v3 측정 관문(base_alignment_missing · base_not_score_panel · base_off_month_grid)을 싣지 않는다. 코어 v3 는 고칠 수 없다(불변) — v4 후보로 적고, 이 판은 `conclusion_scope[3]` 이 보완한다.
- **S-5.** 시드 칸 사양의 `base_signal.path` 가 절대 경로(`C:/Users/99922/…` · E3 는 역슬래시 섞임)다. 지금 기계에서는 그 경로가 있고 재생성 md5 · 기저 정합 키(basename 두 단)가 맞는다. 다른 기계로 옮기면 R2 가 막는다(안전 쪽). 기록만.
- **S-6.** 감시 셸은 측정 창을 기다리는 동안(최대 `MAX_WAIT_S` 48시간) GPU 임대를 쥐고 있어 레인 GPU 새 claim 을 보류시킨다(p1s02_seed_watch.sh:4 · 32). 판정에는 닿지 않는다. 다만 이른 창(02:30)을 노리고 낮에 띄우면 레인이 한나절 선다. 띄우는 시각을 창 직전으로 잡는 운영 메모를 남긴다.

## 3. 초안 v2 를 만들 때의 변경분 점검 기준

- 사양에서 바뀌어야 할 곳
  - `pins.files`(+3) · `pins.basis`(F-2)
  - `hypothesis` · `exposures[1]`(R-1)
  - `conclusion_scope[2] · [3] · [4] · [6]` + 새 줄(R-2 · R-3 · R-4)
  - `tests`(+3 · R-6)
  - `changes_after_review` 에 이 점검의 항목 id 를 적는다.
  - 나머지 블록(rules · selection · standing_cfg · cells · tau_d · behavior_card_cfg)은 바이트 동일이어야 한다.
- 다시 재도출할 것
  - 핀 35 = 기본 18 + `pins.files` 13 + 엔진 1 + 칸 사양 2 + 카드 1 · `rc_pins_mismatches` 0.
  - 시험 7종 마지막 줄 JSON fail 0.
  - 규칙 문서 재생성 md5(사양의 rules · standing_cfg 가 같으면 3c0213bb 그대로여야 한다).
  - 시드 칸 사양 md5 불변(687d6517 · 3a085178 — 생성 입력이 바뀌지 않는다).
- F-1 은 사양 밖이다. 등록 직전에 확인한다: `tick_hold` 가 판 폴더 커밋에 들어 있는가 · 그 커밋 뒤 `git status --porcelain -- <판 폴더>` 가 초안 · drafts · results 말고 비었는가.

## 4. 확인한 것(통과 · 근거)

| # | 항목 | 재도출 · 근거 | 결과 |
|---|---|---|---|
| 1 | 규칙 불변 | P1S01 ↔ P1S02 사양을 블록 단위로 비교했다. `rules` identical · `selection` identical · `standing_cfg` 에서 다른 것은 `edition`(1 → 2) · `rejudge_prior_editions`(→ true)뿐이다. `generator_pin` · `scan` · `accounting` · `report` · `superfan` 은 identical | 일치 |
| 1 | 해석된 문턱 | `t_alpha_vis >= 2` = `constraint_defaults.json::tier_graduation.grade_b_min_portfolio_alpha_t` = 2(지금 파일) · `uc_vis >= 0.55`(선언값). P1S01 등록본 `rules_resolved` = 2 · 0.55 | 일치 |
| 1 | 초안 문장 = 사양 = 규칙 문서 | 초안 `sentences` · md 규칙 절 · `standing_rules.md` §1 이 같은 두 문장 · 같은 표다. `rc_standing_rules_md(사양)` 재생성 md5 = 3c0213bb = 디스크 | 일치 |
| 2a | 핀 md5 | 초안 핀 파일 32/32 = 지금 md5(불일치 0). 코어 파일 20/20 = 초안 `pins.core.files` · 매니페스트 4d00113a = RELEASES v3. 사양 md5 89b014c4 = 초안 `spec_md5`. 카드 사본 6a2a1d21 = `06_Registry/behavior_card.json` = P1S01 사본 | 일치 |
| 2b | 판 2 에서 새로 들어온 경로 | `rf_base_align.R`(e9b28528) · `rf_base_cache.R`(3794bc7b) · `run_paper_replication.R`(04b18146) · `rf_cell_engine.R`(25fa9a4a) · 시드 엔진 `RP_AUTO_2002_06975/engine.R`(fe301130)이 모두 핀에 있고, md5 가 BUILD 'S1 · S2 완료 기록' 표(:129-133)와 같다. 커밋 64ee89013 이 바꾼 판정 경로 파일 5개는 전부 핀에 있다(`git show --stat`) | 일치(빠진 것 = F-2) |
| 2b | 핀 대상 커밋 상태 | 핀 32 중 미커밋은 판 폴더 3개뿐이다(칸 사양 2 · 카드 사본 · 판 폴더 전체가 `??`) | → 등록 전 커밋(8절 ⑦) |
| 3 | 시드 칸 사양 재생성 | `rc_p1_cell_spec`(E2) · `rc_standing_seed_respec`(P0R01_E3_C0 1b9b4052 → E3)를 임시 파일에 다시 돌렸다. **687d6517 · 3a085178 = 디스크** | 일치 |
| 3 | 시행 회계 264 | `rc_standing_nf_prior("2002.06975")` = 264. 출처 = 등록본 `P2R05_distribution_target` 칸들의 `n_family` 264(P2R04 260 · P2R03 252 · P3R03 238 …). 상설 원장에는 이 계보 variant 가 없다(P1S01 시드는 reference) | 일치 |
| 3 | 시드 엔진 | E2 · E3 의 `base_signal.path` → `RP_AUTO_2002_06975/engine.R` · 지금 md5 fe301130 = 핀 = BUILD 기록 | 일치 |
| 4 | 생성 함수 핀이 판 1 과 같다 | 사양 `generator_pin` = P1S01 사양 = `rc_standing_generator_pin()`(fn_md5 80f8311f · like_md5 080cfea8 · canon 5종) · `rc_standing_pin_diff` 0 · `rc_standing_validate(check_pin = TRUE)` 통과 | 맞음 |
| 4 | 변형 스위치 엔진 7개 기본값 = 대표 | `.RP_VARIANT` 를 가진 레인 엔진 7개(1109_3488 · 1309_7119 · 1603_00751 · 2106_06164 · 2412_12350 · 2601_04602 · 2604_16773)의 기본값 = FIDELITY `headline_variant` 7/7 | 맞음 |
| 4 | 시드 스케줄 2004-07 · 268개월 | `sched_test.R` 7/0. 구판 = 2005-01 기본 262개월 · 시작 2000-01-01 에서 멈춤. 신판 = 268개월 · 첫 달 2004-07-30 · 앵커 전 제외 7 | 맞음(서술 = R-1) |
| 4 | 판 1 판정 0건 | P1S01 상설 원장 7줄 = enqueue 3 · scan 2 · measure 2(1908.01112 · ok = FALSE ×2) · verdict 0 | 맞음 |
| 4 | 판 1 보류가 기계적으로 고정되는가 | 판 2 등록 뒤 판 1 의 enqueue 는 '더 높은 판'으로 거부된다(standing.R:232-236). 판 1 의 측정 · 판정 맥락은 핀 불일치로 멈춘다 — P1S01 등록본 핀의 `rf_cell_engine.R` 26993a04 ≠ 지금 25fa9a4a(점검 v3 기록 대조). `tick_hold` 도 있다 | 맞음 |
| 4 | 입구 사유 설명 = 코드 | `portfolio_only_base`(standing.R:600 — 산출 대입이 있고 FACTORS 없음) · `breadth_insufficient`(:506-511 · 473-487 — 보는 창 절단 뒤 충족 날 0 · 배수 = 축 epoch · 상한 = 정본) · `base_off_month_grid`(:515-518) | 대체로 맞음(R-2) |
| 5 | τ_D | 판정 규칙의 지표 = `t_alpha_vis` · `uc_vis`. `rc_rules_test_window_use` 결과 0건(p1.R:9-17 · `_test` 는 report 규칙에만) · 등록 · 판정 때 다시 검사(standing.R:127 · 930). 원장 보는 창 열에 `_test` 열 없음(standing.R:61-62 · 962-965 τ_D 날짜 누출 멈춤). 사양 문장에 τ_D 뒤 성과 값 없음(날짜는 2004-07 · 2005-01 · 결정일뿐). 입구는 패널 Date · Ticker(τ_D 절단 :501) · 보유 date · weight(:464) · 정적 코드 · 인계 메타만 쓴다 | 맞음(S-3) |
| 7 | 보유자 이름 | 감시 셸 `rc_standing:P1S02:P1S02_E2_C0` · `…E3_RX0`(p1s02_seed_watch.sh:21-22) = 코어 `sprintf("rc_standing:%s:%s", ctx$tag, code)`(standing.R:868) · `ctx$tag = rc_round_tag("P1S02_standing_qualification")` = "P1S02"(register.R:19 · standing.R:238) | 일치 |
| 7 | 측정 · 판정 분리 | 감시 셸은 `measure-item` E2 → E3 → `standing-status` 만 부른다(:99-108). `judge` · `standing-report` · 발송 호출이 없다. E2 성공 판독 문자열은 코어 출력 형식(standing.R:895)과 같다 | 맞음 |
| 7 | 점검 스크립트 코드 | `prejudge_check.R` 의 코어 함수(`.rc_artifact_dir` · `RC_EVAL_KEY_FILES` · `rc_axis_audit` · `rc_deps` · `rc_metric_beta_alpha` · `rc_eval_env` · `rc_eval_cell` · `rc_metric_from_eval`)가 v3 에 모두 있다. 시험 창 값은 유한 여부만 출력한다(:66-67 · 77-79) | 맞음(R-5 · S-2) |
| 8 | 시험(사양 `tests`) | `test_round_core_v3.R` 68/0 · `test_round_core_v3_v2parity.R` 33/0 · `test_rf_cell_base_alignment.R` 25/0 · `test_rf_base_align.R` 26/0. 넷 다 마지막 줄이 `{"test":…,"fail":0,…}` 이다(register.R:124 판독 형식) | 통과 |
| 8 | 관련 시험(사양 밖) | `test_rf_base_cache_key.R` 38/0 · `test_rf_base_cache_seed.R` 18/0 · `test_round_core_v3_diag_contract.R` 8/0 | 통과(R-6) |

### 등록 조건 ①~⑧ 의 지금 상태(register.R:3-4 · 106-145)

| 조건 | 지금 | 등록 전 할 일 |
|---|---|---|
| ① 마지막 초안 = 격리 점검 ok | v1 review = null · 이 점검 = revise | F 해소 → (v2 면 변경분 점검 ok) → `reviewed` |
| ② 사양 · 칸 사양 md5 = 초안 | 89b014c4 · 687d6517 · 3a085178 일치 | v2 를 만들면 다시 |
| ③ 핀 재대조 | 불일치 0 | 핀을 더하면 다시 |
| ④ 라운드 시험 | 4/4 fail 0(위) | R-6 반영 시 7종 |
| ⑤ 리허설 | 초안에 `rehearsal` 없음 → 건너뜀(register.R:120) | — |
| ⑥ 철학 P1 | 원장에 `round = P1S02_standing_qualification` · role philosophy · trigger P1 리뷰 없음 · `_supervision/superfan/philosophy/*_P1_P1S02.md` 없음(P1S01 것만) → 지금은 거부된다 | P1 수령 · 도전 응답(진행 중이라 DESIGN §7 에 적혀 있다) |
| ⑦ 고정 대상 미커밋 | 판 폴더 전체가 `??`(untracked) · 제외 정규식에 걸리지 않음 → 지금은 거부된다. 코어 v3 폴더는 깨끗하다 | 판 폴더 커밋(F-1 의 `tick_hold` 포함). 이 점검 파일은 이름에 `prereg_draft` 가 들어 있어 검사에서 제외된다 |
| ⑧ 두 사본 + 등록부 | 실행하지 않았다 | — |

## 5. 못 본 것

- 셀 엔진 · 러너의 나머지 줄 전부. 판정 경로 대조는 source 줄과 해당 분기만 봤다.
- 시드 · 레인 엔진의 실제 측정과 기저 정합 진단(실자료). 감시 셸 · 판정 전 점검 · `standing_board_run.sh` 는 실행하지 않았다.
- 입구 미리보기(`scan --dry-run`) 재실행 — 통과 0 · `portfolio_only_base` 21(BUILD:118)은 재도출하지 않았다.
- GPU 관문(`rf_replication_slots.py` · `qv_lock`)의 동작과 `already_held` 의미.
- 철학 P1 · 판단 T1 리뷰의 내용(감독 몫 · 아직 없음).
- 맞춤 팩터 등록부 미커밋 변경(다른 세션)이 E3 의 DB 팩터 판독에 닿지 않는다는 판단은 커넥터 코드 일부(방향 = ic_asof 기본)에 기댄 것이다. 등록부 전체 사용처는 추적하지 않았다.
- `sched_test.R` 은 스케줄 절만 떼어 돌린다. 엔진 전체의 학습 결정성(GPU)은 보지 않았다.
