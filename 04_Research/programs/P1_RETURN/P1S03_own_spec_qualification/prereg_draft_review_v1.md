# P1S03 사전등록 초안 격리 교차 점검 v1

- 점검자: 격리 교차 점검(서브에이전트)입니다. 이 판의 설계 · 구현에 참여하지 않았고, 측정 결과를 보지 않았습니다. 기술 점검만 했습니다(판단 · 철학 정렬은 다른 감독 몫). 코어 v4 자체는 다른 점검자 몫이라 이 판이 코어를 맞게 쓰는지만 봤습니다.
- 대상(md5): `prereg_draft.json` v1 **52741cbcd091ce1b0221eb67d9ce737e** · `prereg_draft.md` 08c49b1d · `round_spec.json` 48bd40f4 · `specs/P1S03_FVALU_RX0.json` 86737c39 · `behavior_card_cfg_at_prereg.json` 6a2a1d21 · `tools/init_p1s03.R` 21e736c8 · `tick_hold` 5590de23 · 코어 v4 매니페스트 320611fa
- 시각: 2026-11-13 09:12 ~ 09:50 KST · HEAD 시작 `1f7c00288` · 끝 `bbfc49f3d`(다른 세션 커밋 4건 — 핀 대상 변경 0 · 끝에서 `rc_pins_mismatches` 0 재확인)
- **판정: revise**
- **건수: 필수 2 · 권고 3 · 선택 6**
  - 규칙 · 문턱 · 시드 사양 · standing_cfg · 핀 md5 · 초안 문서는 모두 재도출과 맞습니다(사양 전체 재생성 md5 = 디스크 — 손 편집 0).
  - 필수 F-1(시드 행이 v4 자체 사양 관문을 비켜 감)은 코어 또는 사양을 고쳐야 해서 **초안 v2** 가 필요합니다. 필수 F-2(시드 먼저 판정)는 판 폴더 절차만 고치면 됩니다(사양 md5 불변).

## 0. 정보 경계 · 한 일

- 연 것
  - 판 폴더 전문: `round_spec.json` · `prereg_draft.json` · `prereg_draft.md` · `drafts.json` · `DESIGN.md` · `specs/P1S03_FVALU_RX0.json` · `tools/init_p1s03.R` · `tick_hold`(카드 사본은 md5 만).
  - 코어 v4: `standing.R`(1-435 · 606-1434) · `register.R` 전문 · `pins.R` · `spec.R` · `load.R` · `p1.R` · `rules.R`(80-100) · `util.R`(rc_root · rc_after_tau_leaks · rc_input_issues 일부) · `p4.R`(140-250 · 385-410 · 855-900 · 940-985) · `fingerprint.sh` · `round.sh`. README 상설 판 절 · v4 절. `RELEASES.json`(판 · 매니페스트만).
  - 선례: `P1S02_standing_qualification/tools/init_p1s02.R` · 점검 v1 · v2(목차 · 일부). P1R03 · P1R04 의 사양 · 사전등록(칸 · 핀 · 시험 기록 · 규칙만).
  - 입구 · 엔진 경로: `fc_engine_gen.R`(fce_engine_text) · `fc_combiner_gen.R`(fcc_engine_text) · `factor_combinable.R`(1-120 · 160-345) · `factor_db_connector.R`(55-100 · 364-470 · 845-900) · `rf_cell_engine.R`(108-168 · 295-330) · `rf_base_cache.R`(1-170). 엔진 `FC_FAM_value/engine.R` 전문 · `FC_TOTAL_ICW/engine.R`(1-60 · 360-500) · `FC_FAM_value_ICW/engine.R`(머리 · grep).
  - 운영: `standing_board_run.sh` 전문 · `Qvest_StandingBoard.bat` · job `.cmd` · `schtasks` 조회 · `refresh_barrier.sh`(머리 · status). `factor_db_vintage.R` 머리 · `factor_db_vintage.json` 항목 요약 · 이 점검 중 들어온 새 항목(git diff). `seam_scale_repair.R` 머리. `research_programs.json`(P1 라운드 상태만). `q_judgment_ledger.json`(P1S03 리뷰 유무만).
- 안 연 것: 모든 `results/**` · `verdict.json` · `evaluation_visible.json` · `authoritative_remeasure.json` · `standing_visible.json` · 상설 원장 본문 · 텔레그램 기록 · 철학 · 판단 리뷰 본문.
- 우연 열람(1건): 판 표식 원장 새 항목 `RAWDATA-SEAM-0330-REPAIR-20261113` 의 note 에 자료 결함 크기(이음매 수익 이상의 크기 · 정정 행 수)가 적혀 있었습니다. 전략 성과가 아니며 이 점검에 쓰지 않았습니다. 원장 판독 함수(`rc_standing_known` · `rc_standing_nf_prior`)는 상설 원장을 읽지만 출력은 엔진 md5 · n_family 만 찍었습니다.
- 돌린 것
  - Rscript 5개(스크래치 폴더 · `R_ENVIRON_USER` = 빈 파일 · `QM_ROOT` 명시): `verify_p1s03.R`(매니페스트 · 사양 검사 · 생성 함수 핀 · 시드 재생성 · 사양 전체 재생성 · 핀 · 규칙 해석 · 초안 md 재생성 · 갈래 · 입구 판독 표 · 원천 라운드 칸) · `construction.R` · `tau_text.R` · `pins_end.R` · `list_exprs.R`. `init_p1s03.R` 는 parse 한 뒤 쓰기 식(9 · 11 · 12 · 19 · 23)을 빼고, 사양은 임시 판 폴더에 다시 만들었습니다.
  - `round.sh <판> scan --dry-run` 1회 — 쓰기 없음 확인(`results/` 비어 있음 · `stage_artifacts/programs/P1_RETURN/P1S03_*` 없음).
  - md5sum · git log/status/show/diff · python 읽기 · schtasks 조회 · `refresh_barrier.sh status`.
- 쓴 것: 이 파일 1개(저장소). 그 밖은 스크래치 폴더뿐입니다.

## 1. 항목 점검 (1–9)

| # | 항목 | 결과 | 근거(file:line · 재도출) |
|---|---|---|---|
| 1 | 규칙 = P1 템플릿 · 문턱 동일 | 일치 | `round_spec.json:81-119` = `.rcs_p1_template_rules`(standing.R:1308-1312) JSON 동일(재도출 TRUE) · P1S01 · P1S02 · P1R03 rules 블록 JSON 동일 · P1R04 는 자격 규칙만 동일(보고 규칙 test_hold 없음 → S-1) · value_ref `constraint_defaults.json::tier_graduation.grade_b_min_portfolio_alpha_t` = 2.0(초안 2) · q_uc 0.55 · 등록된 P1S02 · P1R03 · P1R04 `rules_resolved` 같은 값 · `rc_rules_resolve` · 문장 = 초안 |
| 2 | 시드 사양 = P1R03_FVALU_C0 + 허용 필드만 | 일치 | P1R03 칸 사양 844fdc6d(= P1R03 사전등록 칸 md5) 대비 차이 = code · label · idea · selection_accounting(n_family 1→2 · n_trials_basis · n_trials_note · remeasure_of)뿐 · measurement_axis 는 이미 활성 epoch(같은 값) · 키 순서 같음 · `init_p1s03.R:12` 재생성 → 86737c39 = 디스크 · `rc_standing_nf_prior("FC:value")` = 2(P1R03 변형 1 · P1R04 IVALU 변형 2 · P1R04 FVALU_R0 = 기준 칸 무가산 — standing.R:420-441) |
| 3 | standing_cfg | 일치 | track own_spec · edition 1 · scan = `RC_STANDING_SCAN_OWN_DEFAULT`(standing.R:57-61) 동일 · accounting = 코어 생성 문구(standing.R:1336-1337) · generator_pin = 지금 `rc_standing_generator_pin()`(fn_md5 80f8311f · like_md5 080cfea8 · canon = constraint_defaults) 차이 0 · P1S02 와 같은 핀 · report · superfan(T1 · P1 / T2 · P2 / daily_batch) · rejudge false · `rc_standing_validate(check_pin = TRUE)` 통과 · **사양 전체 재생성 md5 48bd40f4 = 디스크** · 갈래: 등록부 상설 판 = P1S01(1 · lane) · P1S02(2 · lane) → 넣기 정지 검사(standing.R:288)는 같은 갈래만 봄 · v3 P1S02 는 edition > 2 만 봄 → 서로 막지 않음 |
| 4 | 핀 = 판정 경로 전체 · 제외 근거 | 일치 · 근거 문장 1곳 사실 아님(F-5) | `rc_pins_compute` 37 = 기본 18(pins.R:6-13) + pins.files 16 + 엔진 1 + 칸 1 + 카드 1 · 경로 · md5 = 초안 · 불일치 0(09:44 재확인) · P1S02 판정 경로 13 포함 · P1R03 · P1R04 의 전략 폴더 밖 핀 전부 포함 · 공통 경로 md5 차이 0. **등록부 제외 검증**: 값 부호 = 뷰 부호표(factor_combinable.R:232-247 빌드마다 그때 등록부로 다시 · :294-310 읽을 때 곱함) · 메타 s_reg = 같은 부호표(:331) · category = 읽을 때 지금 등록부(:316-323) → 엔진 단정(FC_FAM_value/engine.R:99-106 · FC_TOTAL_ICW/engine.R:429-436)이 선언 부호 · 가족과 대조. 방향 변경 = 다음 뷰 빌드에서 멈춤(그 전엔 선언 부호 그대로 → 결과 불변) · 범주 변경 = 즉시 멈춤 · 구성원 삭제 = category NA 로 멈춤 · 새 팩터 = `factors=` 로 무영향 · dedup FALSE. 조용히 바뀌는 길 없음. T1 가중 = `compute_rolling_ic_all`(IC 원장만 · factor_db_connector.R:845-895). 셀 엔진은 표준 구성(factors 없음)에서 등록부를 안 읽음(rf_cell_engine.R:311-316) |
| 5 | 빈 tests 등록 · 갈음 | 등록 가능 · 갈음 성립(조건부) | `register.R:121-127` = tests 를 도는 반복뿐(빈 목록 = 0회 · 거부 없음 · 등록본 tests = []) · 코어 v4 시험 = 커밋 25b5193d0 메시지 '46 PASS · 0 FAIL · v4 매니페스트 320611fa' = 초안 pins.core · 생성기 시험 = P1R03 등록 `test_fc_engine_gen.R`(6724f1c8 · 9/0) · P1R04 등록 `test_fc_combiner_gen.R`(aee44109 · 12/0) — 시험 파일 · 생성기 md5 지금과 같음 · 입구 재생성 대조 = dry-run 30/30. 조건: 코어 v4 점검이 코어를 고치면 매니페스트가 바뀌어 등록이 핀 불일치로 멈춤(register.R:118-119) → 새 초안. 근거 포인터가 사양에 없음(S-4) |
| 6 | 첫 scan: 시드 → FC_FAM_value 중복 | 일치(시드 행 경로는 F-1) | `rc_standing_scan` 이 시드를 먼저 넣음(standing.R:970) → 새 엔진마다 `rc_standing_enqueue` 가 이 판 원장 항목의 engine_md5 와 같으면 `duplicate`(:870-871) · 시드 엔진 `FC_FAM_value/engine.R` faba4b41 = 스캔 행 md5 → 항목 30 = 시드 1 + 스캔 29(DESIGN.md:19 · :38) · scan 기록 n_new 는 30(중복 전 셈) · 나머지 29 회계: source_rounds = T0 P1R03+P1R04 · T1 P1R04 · 계보 최댓값 2 → n_family 2(+1 없음 · standing.R:884-887) |
| 7 | tick_hold · 무인 틱 | 일치(지운 뒤 절차 = F-2 · F-3) | `standing_board_run.sh:39-49` — standing true · round_id = 폴더 · 사전등록 있음 · tick_hold 있으면 HELD(scan · 측정 · 보고 없음 · 사유 1줄 :51-54) · 손으로 부르는 round.sh 는 안 막음(:16) · 예약 작업 `Qvest_StandingBoard` 사용 중 · 매시 :37 · `--send` · `rc_uncommitted`(register.R:99-104)가 판 폴더 미커밋을 거부 → 등록 때 hold 는 이미 커밋돼 있음(P1S02 v1 F-1 의 창 없음) · 지운 뒤 첫 틱 = scan → 대기 전부 측정(round.sh:140) → judge 1회(:141 · standing.R:1135) → 발송 |
| 8 | 문장(결론 범위 · 노출 · 가설) | 대체로 일치 · 어긋남 5 | 성과 수치 없음(문턱 · 설정 · 칸 수 · '자격 8/15' · '불일치 3 · 불명 9' = 보는 창 판정 수 · 비성과 감사 셈의 노출 고지) · τ_D 뒤 ISO 날짜 1건 = `round_spec.json:137` '2026-03-30'(`rc_after_tau_leaks` 적중 → F-4) · 결정 id 의 2026 날짜는 P1S02 선례와 같은 관례 · 3치(rules.R:89-91 · standing.R:1209) ✓ · 위기 하락노출 = 보고 열(standing.R:84-85) ✓ · 방향 줄(:141) ✓. 어긋남: :136 시드 먼저 읽기(F-2) · :139 기저 풀 관문(F-1) · :170 기저 캐시 키(F-5) · :144 토탈 T1 대체 규칙 · :8 P1R04 규칙(S-1) |
| 9 | 첫 측정을 막거나 무효로 만드는 것 | 막는 것 없음 · 무효 위험 2(F-2 · F-5) | P1R04 미측정은 상설 측정을 안 막음 — 원천 라운드 판독은 등록본 · 핀만(standing.R:739-765) · 측정 · 판정은 원천 라운드와 무관. 막히는 것 = 사슬 등록(원천 시행 산출 필수 · p4.R:876-887 · README.md:119)과 T1 엔진의 원천 라운드 영수증(P1R04 영수증 또는 이 판 pass P2 기록). 자료 판: 이 점검 중 판 표식 원장에 `RAWDATA-SEAM-0330-REPAIR-20261113`(scope all · completed_at 09:36:10 · 커밋 bdf79b30b)이 들어와 그 뒤 측정만 current → :137 '판 표식' 주장이 코드로 성립. 측정 지문에 결합용 뷰 · IC 원장 있음(fingerprint.sh:17-21). P1R04 는 등록 · 결과 0(등록부 registered) |

등록 조건(register.R:106-145)의 지금 상태: ① 이 점검 = revise → 초안 v2 · 점검 필요 · ② 사양 · 칸 md5 = 초안 · ③ 핀 37 · 불일치 0 · ④ 시험 없음(빈 목록) · ⑤ 리허설 필드 없음(선택) · ⑥ 철학 P1 리뷰 없음(판단 원장 P1S03 리뷰 0) · ⑦ 판 폴더 전체 미추적(`??`) — 커밋 필요 · 코어 v4 폴더는 깨끗 · ⑧ 미실행.

## 2. 지적

### 필수

**F-1. 시드 행은 v4 자체 사양 관문을 지나지 않습니다 — 이 판에서 FVALU 의 행은 시드 하나뿐입니다**

- 근거
  - 시드는 인계 기록 없이 원장에 들어갑니다(standing.R:908-925 — handoff 필드 없음).
  - 자격 표의 origin 은 source 가 seed 면 무조건 `"seed"` 입니다(standing.R:353). 그래서 own_spec · families · source_rounds 가 NA 입니다.
  - 기저 풀의 v4 관문(philosophy_unread · philosophy_hold · lowrisk_confirm_pending)은 origin = own_spec 일 때만 걸립니다(p4.R:225-235). FC_FAM_value 는 등록부 행도 없어(research_programs.json 0건) 레인 꼬리표 검사도 없습니다(p4.R:215-218). 남는 검사는 자격 · 현금 기계 · 판 표식 · 엔진 동일 · 구성뿐입니다(시드 구성 = standard 재확인).
  - 사슬 원천 시행도 origin = own_spec 일 때만 모읍니다(p4.R:876-887 · :893). blend 상대는 풀 eligible 경로만 봅니다(p4.R:963).
  - 첫 scan 에서 FC_FAM_value 는 시드와 엔진 md5 가 같아 duplicate 로 빠집니다(standing.R:870-871).
- 왜
  - 결론 범위 :139 '기저 풀은 통과 칸에 철학 P2 판독과 저위험 확인을 요구한다'와 DESIGN §6(:30) '사슬 등록 때 원천 라운드 전 칸이 사슬 시행 집합에 들어간다'가 FVALU 에는 지켜지지 않습니다.
  - 시드는 양성 대조라 통과가 예상되는 길입니다. 예외가 아니라 본길입니다.
  - FVALU 를 기저로 한 사슬은 P1R03 15칸 + P1R04 30칸을 선택 현실 점검 시행 집합에 넣지 않습니다. 다중 검정 보정이 약해집니다.
  - 시드 선정 규칙(P1R03 자격 8 중 왜 FVALU 인가)이 적혀 있지 않습니다. 시드만 다른 풀 경로를 받으면 그 선정이 결과에 닿습니다(노출 :125 — 자격 칸의 시험 창 표식을 본 상태).
- 고치는 법
  - (가 · 권장) 코어 v4 출시 전 수리 — 코어 점검 쪽에 넘깁니다. 자체 사양 갈래 판의 시드도 스캔 행과 같은 자체 사양 기록(origin own_spec · own_spec · own_spec_md5 · generator · families · source_rounds)을 원장에 남깁니다(`.rcs_enqueue_seeds` 가 그 엔진 폴더를 `.rcs_scan_own_dir` 로 판독). `rc_standing_qualified` 는 handoff origin 이 있으면 그것을 씁니다(standing.R:353). 또는 기저 풀이 origin 대신 엔진 폴더의 자체 사양(재생성 대조 통과)으로 관문을 겁니다. 시험 = 자체 사양 갈래 시드 통과 행의 philosophy_unread · 원천 시행 양방향.
  - (나 · 차선) 코어를 안 고치면 결론 범위에 한 줄을 더합니다: '시드 행(origin seed)은 v4 관문 · 원천 시행 회계를 지나지 않는다 — FVALU 를 사슬 기저 · blend 상대로 쓰기 전에 철학 P2 판독 · 원천 시행(P1R03 · P1R04)을 사슬 등록 기록에 손으로 싣는다' + 시드 선정 규칙. 코드가 지키지 않는 약속이라 차선입니다.
  - 사양 md5: (가) 매니페스트가 바뀌어 pins.core 가 달라짐 → **초안 v2 필요**. (나) conclusion_scope 변경 → **초안 v2 필요**.

**F-2. tick_hold 를 지운 뒤 첫 무인 틱이 시드 판정 전에 30칸을 모두 판정 · 발송합니다 — 양성 대조가 관문 노릇을 못 합니다**

- 근거
  - DESIGN §8(:37): 지운 뒤 매시 틱이 scan → standing-measure → standing-report 를 합니다.
  - standing-measure = 대기 항목 전부 measure-item → judge 한 번(round.sh:140-141). judge 는 측정된 항목 전부를 판정합니다(standing.R:1135).
  - 판정은 추가 전용 원장에 남고 다시 재지 않습니다(standing.R:1089). 예약 작업은 `--send` 입니다. 통과는 엔진마다 push 됩니다(standing.R:1235-1250). 자격 표(`rc_standing_qualified`)는 판정 즉시 그 통과를 읽습니다.
- 왜
  - 결론 범위 :136 '시드 미달이면 다른 판정을 읽기 전에 판 경로를 먼저 확인한다'와 사다리 루프 ①('관문은 아는 답을 한 번 통과시킨 뒤에 믿는다')이 기계 순서로 지켜지지 않습니다.
  - 판 경로 결함이면 29개 판정이 이미 원장 · 기저 풀 입력 · 텔레그램에 있습니다. 되돌리려면 새 판(rejudge)이 필요합니다. P1S02 점검 v1 F-1 과 같은 종류입니다.
- 고치는 법(판 폴더 절차 · **사양 md5 불변 — 정정 기록**)
  - tick_hold 를 지우기 전에 한 셸에서 손으로: `round.sh <판> scan` → `measure-item P1S03_FVALU_RX0` → `judge`(그때 측정된 항목은 시드뿐이라 시드만 판정) → `standing-status` · `results/standing_visible.json` 으로 시드 판정을 봅니다.
  - 시드 통과(또는 판 경로 이상 없음 확인) 뒤에 tick_hold 를 지웁니다. 미달이면 hold 를 둔 채 경로를 봅니다.
  - DESIGN §8 과 tick_hold 첫 줄에 이 순서를 적고 등록 커밋에 넣습니다.

### 권고

**F-3. tick_hold 해제 조건에 RELEASES v4 출시가 없습니다**

- 근거: README.md:115 — v3 기저 풀(`round.sh - p4-pool` 의 기본 판)은 자체 사양 판 원장도 읽고 v4 관문 없이 자격을 줍니다. '첫 통과 전에 RELEASES 기본 판을 v4 로'라고 적었습니다. RELEASES.json 에 v4 항목이 없습니다(README.md:120). DESIGN §9(:41)는 '기본 판 = v4 · RELEASES 항목 뒤'라 적었지만 tick_hold(:1) · DESIGN §8(:37)의 해제 조건에는 없습니다.
- 왜: 첫 통과가 나온 뒤 기본 판으로 풀을 부르면 v4 관문(철학 P2 · 저위험)이 없는 풀이 나옵니다.
- 고치는 법: tick_hold 첫 줄 · DESIGN §8 해제 조건에 'RELEASES.json v4 출시 항목'을 더합니다. 자료 판 조건은 판 표식 id 로 적습니다 — 이 점검 중 `RAWDATA-SEAM-0330-REPAIR-20261113`(completed_at 09:36:10)이 원장에 들어왔으니 그 id 로 확인할 수 있습니다. **사양 md5 불변(정정 기록).**

**F-4. 사양 글에 τ_D 뒤 ISO 날짜와 근거 없는 자료 주장이 있습니다**

- 근거
  - `round_spec.json:137` 'RAWDATA 2026-03-30 수정주가 이음매 수리' — `rc_after_tau_leaks` 적중(이 점검 재실행).
  - 가설(:9) 'IS 구간 자료는 수정주가 이음매 수리의 영향 밖' — 근거 경로가 없습니다. 수리 기록(판 표식 원장 새 항목)은 '전 전환점 재판정'을 포함하고, 가격 수준 기반 팩터의 수준 이음매는 수리 범위 밖이라고 적었습니다.
- 왜: 요청 점검 항목(사양 글에 τ_D 뒤 날짜 없음)입니다. 이 문장을 사슬 판 글(p4.R:705 검사)이나 결과 원장 글로 옮기면 기계 검사가 멈춥니다. IS 무영향 주장은 시드 양성 대조 해석의 전제입니다.
- 고치는 법: 날짜 대신 판 표식 id(`RAWDATA-SEAM-0330-REPAIR-20261113`)로 적습니다. IS 무영향은 수리 감사 산출 경로(판 표식 원장 evidence 의 감사 파일 · README)를 달거나 '예상'으로 낮춥니다. tick_hold · DESIGN 의 같은 날짜도 맞춥니다. **사양 md5 바뀜 → 초안 v2.**

**F-5. 핀 근거의 '기저 캐시 키가 결합용 뷰 · IC 원장을 다룬다'는 사실이 아닙니다**

- 근거
  - `round_spec.json:170`.
  - 기저 신호 캐시 키 = 엔진 md5 · RAWDATA · 벤치 · 팩터 DB(build_hash + factor_db_YYYYMM) · 보조 파일(fundamental · ecos · investor · consensus) · 메모리 지문 · 행 수 · 시작일입니다(rf_base_cache.R:44-46 · :145-161 · rf_cell_engine.R:124-127). `.cache/factor_combinable` · `factor_ic_monthly.parquet` 는 없습니다.
  - 측정 지문(fingerprint.sh:17-21)에는 둘 다 있습니다. 다만 한 측정 안의 변화만 잡습니다.
- 왜
  - 자체 사양 엔진의 팩터 입력은 결합용 뷰(T0)와 IC 원장(T1)뿐입니다.
  - RAWDATA · 팩터 DB 도장이 같은 채로 뷰 · IC 원장만 다시 지어지면, 그 사이 만든 캐시가 뒤 측정에 적중해 옛 뷰 신호를 씁니다. 이 점검 중 실제 순서가 RAWDATA 09:07 → 팩터 DB 09:27 → IC 원장 09:35 → 뷰 09:36 이었고, 그동안 배리어는 free 였습니다.
  - DESIGN §8(:38)은 P1R04 캐시 적중을 기대합니다. rf_base_cache.R 머리 주석도 '새 엔진이 다른 패널을 읽으면 여기에 더한다'고 적었습니다.
- 고치는 법
  - (1) 핀 근거 문장을 '측정 지문(한 측정 안) · 판 표식이 다룬다 — 기저 캐시 키에는 없다'로 고칩니다. **사양 md5 바뀜 → 초안 v2.**
  - (2) DESIGN §8: 첫 측정 전에 FC_* 엔진의 기저 캐시 파일(`.cache/rf_base_signal/base_v3_<엔진 md5 앞 12>_*.rds`)이 마지막 뷰 · IC 원장 빌드보다 뒤에 만들어졌는지 보고, 아니면 지웁니다(다시 계산 비용만). 사양 불변.
  - (3) `rf_base_cache.R` 보조 목록에 factor_combinable · factor_ic_monthly.parquet 를 더하는 수리는 인프라 과제로 넘깁니다. 그 파일은 P1S02 · P1R03 · P1R04 · 이 판이 핀으로 걸어서, 바꾸면 등록된 판이 멈춥니다(새 판 필요).

### 선택

- **S-1. 문장 정밀도**(사양 md5 바뀜 — 초안 v2 에 묶음)
  - :8 '판 1 · 판 2 · P1R03 · P1R04 와 같은 규칙' — P1R04 는 자격 규칙 · 문턱만 같고 보고 규칙 test_hold 가 없습니다.
  - :9 '입구로 들어오는 엔진(T0 14 + 토탈 · T1 14 + 토탈)' — FC_FAM_value 는 시드로 들어오고 스캔에서는 duplicate 입니다. 스캔 항목은 29 입니다.
  - :144 T1 대체 규칙 — 가족 엔진은 '구성원 가중이 모두 0 이면 등가중'(FC_FAM_value_ICW/engine.R:142-145)이 맞습니다. 토탈은 가중 0 인 가족을 그 달 빼고, 모든 구성원이 0 일 때만 T0 입니다(FC_TOTAL_ICW/engine.R:451-463).
  - :135 own_spec_missing 에는 schema ≠ fc_own_spec_v0 도 들어갑니다(standing.R:81).
  - :8 '같은 생성기로 늘어날 결합기 단계' — 생성기 파일은 핀이라 고치면 이 판 전체(대기 항목 포함)가 멈춥니다(standing.R:282-283). 새 단계는 새 생성기 파일(own_generator_unknown → 새 판)이거나, 같은 종류의 새 사양뿐입니다.
- **S-2. 핀 근거 제외 목록**(사양 md5 바뀜): own_spec.json(P1R03 · P1R04 는 핀 · 이 판은 엔진이 실행 때 안 읽고, 시드는 칸 사양으로 넣고, 스캔 항목은 넣을 때 own_spec_md5 를 원장에 남김)과 factor_dup_scan.R(`.fc_env` 가 적재 · dedup FALSE 라 값에 안 닿음 · 판 2 제외 사유 승계)을 적습니다. 등록부 문장은 '뷰 부호표(빌드 때 등록부)와 대조 — 방향 변경은 다음 뷰 빌드에서 멈춘다 · 그 전에는 선언 부호 · 캐시 적중이면 엔진이 안 돌지만 값은 선언 부호'로 정밀하게 씁니다.
- **S-3. standing-check**(사양 불변): 판 폴더에 standing_rules.md 가 없습니다(P1S02 는 있음 · 점검자 대조용). 등록 직전에 standing-check 를 돌리면 규칙 문서와 시드 회계 대조(지금 앞선 최댓값 2 = 사양 2)를 함께 봅니다. 이 점검의 임시 생성본 md5 는 5e765599 입니다. 커밋 대상이 하나 늘어납니다.
- **S-4. 시험 갈음 포인터**(사양 md5 바뀜): :145 에 커밋 25b5193d0(매니페스트 320611fa · 46 PASS) · P1R03 등록 시험(test_fc_engine_gen.R 6724f1c8 · 9/0) · P1R04 등록 시험(test_fc_combiner_gen.R aee44109 · 12/0)을 적습니다. 등록본 tests = [] 라 다른 흔적이 남지 않습니다.
- **S-5. 코어 회계 문구**(코어 점검 쪽 · 이 판 불변): accounting.rule '원천 라운드가 그 계보로 회계했으면'과 코드 조건(standing.R:884 — 원천 라운드 있음 ∧ 계보 최댓값 ≥ 1 · 최댓값은 모든 사전등록 · 원장에서)이 다릅니다. 이 판은 원천 라운드 칸이 같은 계보(FC:<카테고리>)라 결과가 같습니다(재도출 29행 모두 2).
- **S-6. 시드와 방향 수정 순서**(사양 불변): 시드 FC_FAM_value 는 방향 불일치 구성원 V23_RAFI_Weight 가 든 가족입니다(:141). 시드 판정 전에 등록부 방향을 고치고 뷰를 다시 지으면, 시드 엔진이 단정으로 멈추거나(측정 실패) 다시 만들어져 R2(engine_md5_changed)로 막힙니다. 양성 대조를 잃습니다. 방향 수정은 시드 판정 뒤로 두고 DESIGN §8 에 적습니다.

### 초안 v2 를 만들 때

- 사양을 바꾸는 것: F-1(가면 코어 → pins.core · 나면 conclusion_scope) · F-4 · F-5(1) · S-1 · S-2 · S-4.
- 판 폴더 정정(사양 불변 · 등록 커밋에 포함): F-2 · F-3 · F-5(2) · S-3 · S-6.
- 변경분 점검 기준: rules · cells · 시드 사양(86737c39) · standing_cfg 는 그대로여야 합니다. F-1 (가)를 택하면 코어 매니페스트 · 코어 시험 결과를 새로 대조합니다.

## 3. 못 본 것

- 코어 v4 자체(다른 점검자 몫). F-1 · S-5 는 이 판이 코어를 쓰는 관점에서만 봤습니다.
- 측정 · 판정 실행(standing-measure · judge · report) · 셀 워커 · 기저 정합 관문의 실제 동작 — 돌리지 않았습니다.
- 시험 묶음(test_round_core_v4.R · 생성기 시험) 재실행 — 커밋 기록과 md5 대조로만 봤습니다.
- IC 원장의 부호 규약(원값 기준 IC 인가) — T1 가중 s_reg × ICIR 의 전제입니다.
- 이음매 수리 감사 산출의 내용(IS 구간 정정 여부).
- 철학 P1 · 판단 T1 리뷰(아직 없음).
- 나머지 27개 엔진 본문 전문 — 생성기 재생성 md5 대조(dry-run 30/30)로 갈음했습니다.
- superfan_watch.py · chain_tick.sh 동작.
- 결과 · 판정 파일 · 권위 기록 · 텔레그램 기록 일체(정보 경계).
