# P2R04 사전등록 초안 격리 교차 점검 v1

- 점검자: 격리 교차 점검(서브에이전트 · 이 라운드 설계 · 구현 비참여 · 측정 결과 없음) · 2026-10-18
- 대상(md5 앞 8자리): `prereg_draft.json`(draft_version 1 · 79f3ff1d) · `evaluate.R`(76e41a4e) · `evaluate_fixture.R`(2dbcd8c3) · `round_rules.R`(91fc0e05) · `rehearse.R`(ef6584ec) · `rehearsal/summary.json`(ec347c91) · `register.R`(1268505c) · `precheck.R`(22a55366) · `measure.sh`(ed0446c1) · `measure_now.sh`(e23e0dd8) · `measure_now_vram.sh`(9fb89be3) · `fingerprint.sh`(f7e1974a) · `notify_done.sh` · `notify.R` · `specs/` 23 · `DESIGN.md` v3(1eab9087)
- **판정: revise(수정 후 등록)** — 규칙 ①~⑬ · β 짝 · 빠른 급락 · 정보 경계 · PIT 골격은 문장과 코드가 맞는다. 다만 묶일 문장과 코드가 어긋나는 곳이 넷(⑭ 문턱 · tested ⑥ · ⑭ 미측정 판정어 · 진단 칸 지문), 측정 입력 핀 빈칸 하나(러너 수수료 · 종목 수), 설계 정본의 낡은 문장 셋이 있다. evaluate.R · precheck.R 은 평가 경로 핀이라 **전부 등록 전에만 고칠 수 있다.**
- **건수: 필수 6 · 권고 11 · 선택 7**

## 0. 정보 경계 선언

- 연 것: P2R04 폴더 전 파일(위 목록 · specs 23 전부는 파이썬으로 판독) · `rehearsal/summary.json`(단계 통과 · 판정어 · 사유 분류만) · `_design_notes/defense_direction_agreement.md`(IC 부호 정렬 — 부호만)
- 계약 · 엔진(코드만): `diagnosis_packet.R`(1~320) · `behavior_card.R`(195~374) · `matched_controls.R`(grep) · `factor_db_connector.R`(40~85 · 160~395 · 605~695) · `rf_cell_engine.R`(1~410 · 600~625 · 1185~1214) · `rf_cell_worker.R`(전문) · `_lib/{round_kit.R, measure_round_cell.R, eval_parallel.sh}` · `compute_quality.R`(머리 · Q08 절) · `parse_fundamental_xlsx.R`(190~225) · `replication_harness.R` · `backtest_harness.R` · `run_paper_replication.R`(grep)
- 참고: 판단 T1 `20261018_1227_T1.md`(C-028 절 · 자기 점검) · P2R03 `prereg_draft_review_v1.md` · P2R03 사양 `P2R03_E?_RX0.json` · P2R03 `prereg.json` 의 rules 문장(tested · vintage_group) · `06_Registry/reinforce_program.json` fixed_axes · `matched_controls.json` 키
- **안 연 것**: P2R03 `results/` 전부(evaluation_full/visible · full/ · 칸 json · 로그 · visual/) · P2R03 `evaluate*.log` · P0R01 results · 어떤 authoritative_remeasure · 철학 P1 리뷰 본문. 시험 창 · 전기간 성과 수치를 본 것 없음.
- 실행한 것: `Rscript evaluate_fixture.R`(R 임시 폴더에만 씀) → **49/0 · 뮤테이션 27/27 · 3초** · evaluate.R 함수를 격리 환경에 적재한 재현 4건(아래 R1~R4 · 합성 입력 · 쓰기 없음) · 파이썬 대조(사양 혼합 몫 재도출 · 핀 md5 · RX0 사양 diff — 읽기만). 측정 · 등록 · 커밋 · 파일 수정(이 파일 밖) 없음.

## 1. 필수 (등록 전 수정)

### 필수 1 — ⑭ 분해 문턱: 묶일 문장 · 코드 · 원 요구가 셋 다 다르다(단위 근거도 없다)

- 문장: `prereg_draft.json:882`(← `register.R:477-480`) · `DESIGN.md:10` · `:97` — "위기 분해 선택 항 … 깊은 위기 과반에서 RX0 보다 **개선**" (문턱 없음 = 차 > 0)
- 코드: `evaluate.R:461` `J[, better := sv - sr >= tol]` · tol = crisis_improve_min 0.03(`:987` · `:1119`) — **0.03 이상 · 등호 포함**
- 원 요구: 판단 T1 `20261018_1227_T1.md:52` — "변형 selection_sum **>** RX0 selection_sum **+ tol**(crisis_improve_min 0.03)" — 엄격
- 단위: selection_sum = 위기 (고점, 저점] 일간 선택 기여의 산술합 = 수익 단위(`diagnosis_packet.R:184`). crisis_improve_min 의 근거 문장(`prereg_draft.json:919`)은 "낙폭 포착 기준(dd_capture 비율)"이다. 같은 0.03 을 다른 단위에 쓰는 근거가 사전등록에 없다(수치 근거 기록 의무).
- 재현 R1(evaluate.R `p2_selection_decomp` 그대로): 깊은 위기 4 · 변형 − RX0 = +0.015 · +0.020 · +0.060 · −0.010 → 코드 **1/4 미달** · 문장대로(tol 0) **3/4 통과**. 같은 패킷에서 ⑭ 가 뒤집힌다.
- 고칠 방법: 한 문장으로 묶는다. 권장 = T1 원문과 ①~④ 관례(엄격 부등호)에 맞춰 `evaluate.R:461` → `sv - sr > tol` · 사전등록 문장 → "변형 selection_sum − RX0 selection_sum > tol(crisis_improve_min 0.03 을 위기 일간 선택 기여 산술합 · 수익 단위로 차용 · 판단 T1 C-20261018-028)" · DESIGN §0a · §5 ⑭ 같은 문장. 근거는 final_selection_rule 에 `selection_decomp_tol` + `_evidence` 로 따로 두거나 `crisis_improve_min_evidence` 에 "⑭ 분해에도 차용(단위 = 수익)"을 붙인다. 픽스처 27 에 경계 사례(차 = 0.03 · 0.029)와 뮤테이션(`> tol` → `> 0`)을 더한다 — 지금 재료(차 +0.06 · +0.05 · −0.05)는 tol 0 이어도 같은 답이라 문턱을 고정하지 못한다.

### 필수 2 — rules.tested ⑥ 이 ⑭ 를 '유한해야 하는 판정 입력'으로 적었다(코드 · 같은 사전등록의 다른 문장과 반대 의미)

- 문장: `prereg_draft.json:871`(← `register.R:458`) "⑥ 판정 입력(①②⑤⑥⑨⑫⑬**⑭** · 알파 · 엔진 알파)이 모두 유한" — 이대로면 ⑭ 결손 = **미시험**(판정 칸 분모 밖). P2R04 에서 새로 들어간 문구다(P2R03 tested 문장에는 이 목록이 없다).
- 코드: 유한 검사 `inp`(`evaluate.R:1103-1104` · `:1108`)에 ⑭ 가 없다. ⑭ 결손은 `s14$ok = FALSE`(`:465-469` · `:1118-1119`) → tested TRUE · pass FALSE(`:1185-1191`) → 라운드 판정의 **판정 칸**으로 센다(`:566-576`). 같은 사전등록 selection_attribution(`:882`) · failure_semantics(`:889`)도 "결손 = 미측정(통과 불가)".
- 고칠 방법: ⑥ 목록에서 ⑭ 를 빼고 "⑭ 결손은 미시험이 아니다 — '⑭ 미측정'(판정됨 · 통과 불가 · 필수 3 판정어)" 한 줄. 코드 무변경. (⑭ 결손을 미시험으로 바꾸는 길은 failure_semantics · selection_attribution 까지 바뀌므로 권하지 않는다.)

### 필수 3 — ⑭ 미측정이 '크기 · 노출 방어' 판정어 · 결론 이름으로 접힌다 (NA → 기전 결론)

- 위치: `evaluate.R:546` `s14 <- isTRUE(f$selection)` · `:552` `if (isTRUE(r3) && isTRUE(r4) && !s14) "size_or_exposure_defense"` · `:559` `p2_defense_name` 의 `!isTRUE(s14)` · `:446-450` `p2_selection_attr` 가 MC8 라벨 `insufficient`(위기 2 미만 — `matched_controls.R:437`)를 status "ok" 로 둔다.
- 재현 R2(evaluate.R 함수 그대로): 분해 필드 없는 패킷 → `p2_selection_rule` status "unmeasured(선택 항 분해)" · ok FALSE → `p2_cell_verdict`(③ ④ 통과) = **size_or_exposure_defense('크기 · 노출 방어(⑭ 미통과)')** · `p2_defense_name` = **'크기 방어 또는 노출 방어(⑭ 미통과)'** · `p2_selection_attr("insufficient")` = status **ok**. 재현 R3: ③ = NA(β 사본 실패)면 판정어는 beta_unmeasured 로 따로 나오지만 결론 이름은 "방어 이름 없음(③ · ④ β 짝 **미통과**)".
- 왜 필수: failure_semantics(`prereg_draft.json:889`)는 "⑭ 라벨 · 분해 필드 결손 = 미측정(통과 불가)"인데 판정어는 기전 결론을 낸다. 그 이름이 결론 범위 2 · 5("'선택 기울기도 노출 방어'면 다음 = 원천 ①")의 입력이라, 패킷 필드 하나가 비면 다음 라운드의 동기가 결측에서 만들어진다. 같은 파일의 크기 × β 짝은 미측정을 따로 이름 짓는다(`:560` '이름 보류') — ⑭ · ③ · ④ 만 빠졌다. 체크리스트 '실패 의미 고정 — NA = 미측정 꼬리표'.
- 고칠 방법: (a) `P2R04_VERDICTS` · `P2R04_VERDICT_NAMES` 에 `selection_unmeasured`("⑭ 선택 귀속 미측정") (b) `p2_cell_verdict` 에 ⑭ 상태(`s14$status`)를 넘겨 ③ ∧ ④ 통과 ∧ 상태 ≠ ok 면 size_or_exposure_defense 보다 먼저 그 판정어 (c) `p2_defense_name` 에 '방어 이름 보류(⑭ 미측정)' 분기 · r3/r4 = NA 면 '방어 이름 보류(③ · ④ 미측정)' (d) `p2_selection_attr` 에서 `insufficient` = status "unmeasured"(통과 불가는 그대로) (e) `notify.R:23-25` CW · 픽스처 29 · 43 · 사전등록 failure_semantics · conclusion_scope 2 에 판정어 추가. evaluate.R 이 바뀌므로 픽스처 · 리허설 재실행 → 초안 재작성(register.R 이 리허설 evaluate md5 를 대조한다).

### 필수 4 — 진단 칸 지문 불일치의 결과: 문장 = 평가 전체 중단 · 코드 = 그 진단만 미시험

- 문장: `prereg_draft.json:873`(← `register.R:462-464`) "같은 엔진의 칸은 함께 잰다(… **진단 칸 포함**) · … 묶음 안 지문이 모두 같아야 판정 · … 그래도 다르면 evaluate.R 이 **평가 전체를 멈춘다**" · `:887` "같은 엔진 묶음의 지문 대상(rules.vintage_group)". P2R03 문장(진단 칸 없음)을 잇고 '진단 칸 포함'만 덧붙였다.
- 코드: `evaluate.R:1246-1251` 은 판정 칸(장치 4 + RX0)만 묶어 다르면 전체 중단 · 진단 칸은 `:1258-1263` 에서 묶음 지문과 다르거나 없으면 **그 칸만 미시험**(판정 계속). `measure.sh:70-74` same_fp 는 진단 칸까지 묶어 재측정한다(이 부분은 문장과 일치).
- 시나리오: 묶음 재측정 뒤에도 E2_W3 종료 지문만 다르면(측정 중 팩터 DB 월 스냅샷 재빌드) 문장 = 판정 없음 · 코드 = E2 판정 정상 · W3 미시험 · H3 용량 읽기 '미측정(네 칸 중 미시험)'.
- 고칠 방법: 문장을 코드에 맞춘다(칸 하나의 문제는 그 칸만 — failure_semantics 와 같은 원칙): "판정 칸(장치 + RX0) 지문이 다르면 평가 전체 중단 · 진단 칸 지문이 묶음과 다르거나 없으면 그 진단 칸만 미시험(판정 계속)". diagnostics 문장(`:887`)도 같이.

### 필수 5 — 러너의 수수료 · 종목 수 원천(`06_Registry/reinforce_program.json`)이 핀 · 대조 밖이다

- 위치: `rf_cell_worker.R:31-32`(`PROG <- fromJSON(".../reinforce_program.json"); AX <- PROG$fixed_axes`) → `:96-101`(`n_long = AX$n_max, n_max = AX$n_max` · `commission_paper = AX$commission_bps / 10000`). 칸 사양 fixed_axes 의 commission_bps(15) · n_max(25)는 러너에 **가지 않는다**(엔진 선정만 사양 n_max).
- 이 파일은 운영 핀(`prereg_draft.json:942-1096` · `register.R:36-50`) · 데이터 지문(`fingerprint.sh:18-21`) · precheck 어디에도 없다. 9~10월에 8회 바뀐 파일이다(그중 5회 = SessionEnd 자동 커밋 '미서술 변경' · `git log -- 06_Registry/reinforce_program.json`).
- 지금 값 = 15bps · 25 — 23칸 사양과 같다(확인). 바뀌면 고정 축(15bps · ≤ 25종)과 다른 값으로 묶음 일부가 측정되고 precheck · 평가 핀 · 묶음 지문이 모두 못 본다(조용한 처치 변경 · 체크리스트 '판정 경로 전체 핀').
- 고칠 방법: 파일 md5 핀은 다른 작업의 무관한 편집으로 측정을 막을 수 있으니(팩터 레지스트리를 엔트리로 핀한 것과 같은 이유) **읽는 키 내용을 대조**한다 — 최소판 = precheck.R 본 대조에 "reinforce_program.json fixed_axes.{n_max, commission_bps} = 23칸 사양 fixed_axes 값" 단정 + precheck.json 기록. 평가 시점까지 보려면 operational_pins 에 `runner_axes` 종류 + `p2_pin_mismatches` 대조 함수(대조 함수 없는 종류 = 불일치 규칙 `evaluate.R:759-760` 이 있으니 함수부터). register.R OPS 주석에 '워커가 읽는 설정'을 적는다.

### 필수 6 — 설계 정본(DESIGN v3)의 낡은 문장 셋이 구현과 어긋난다 (텍스트 · 1분)

- `DESIGN.md:45`(§2) "E3 은 틸트가 약하다(세기 차이 = 결론 범위 1에 적는다 — 두 엔진 공통 통과가 세기 차이를 넘는 강건성이다)" — v3 은 E3 도 50%(`:9` · `:43`).
- `DESIGN.md:75`(§4) "진단 칸 9(E2 · …)" — v3 = 13(E3 용량 짝 W1~W4 포함 · `:14` · `:116`).
- `DESIGN.md:146`(§10 구현 계약) "장치 칸 = RX0 사양의 factors 끝에 {kind db} **하나** 추가(E2 는 factors 가 비어 있으므로 1개)" — 구현 = E3 6회 나열 · base_weight 0.25(`specs/P2R04_E3_H*.json`) · 진단 칸 사양 규칙(C = w 1 · W = 1 − t(n + 1) · N0 = null_perm)이 §10 에 없다.
- 사전등록 judgments.design = DESIGN.md · rules_source 'DESIGN v3 §5' — §10 으로 재도출하는 사람에게 E3 장치 칸이 계약 위반으로 보인다.
- 고칠 방법: 세 줄을 v3 로(§10 에 mix_plan 식 한 줄 + 진단 칸 사양 한 줄). 라운드 디렉터리는 등록 전 커밋 대상이다(`register.R:337` COMMIT_PATHS).

## 2. 권고

1. **⑩ 문장의 '사양 · base_weight' 조항은 evaluate.R 이 보지 않는다.** 보증은 등록 spec_checks(`register.R:165-170`) + 사양 md5 핀(`evaluate.R:756`)이 한다 — evaluate.R ⑩ 은 꼬리 반복 m ≥ 1 · 바탕 = RX0 · 로그만 대조하고(`:370`), 혼합 가중 대조는 진단 칸만이다(`:1004-1005`). 핀이 막으니 결과는 같지만 재도출 문장과 코드가 다르다. 문장에 "(사양 · 몫 = 등록 시 spec_checks 단정 · 사양 md5 핀)"을 쓰거나, 판정 칸에도 `cs$device_count == cm$device_repeat` · `cs$blend$device_weight == cm$defense_share`(사전등록 cells 에 이미 있다)를 단정한다.
2. **라운드 판정이 '결정 대조 미측정'을 반증과 섞는다.** 재현 R4: 8칸이 모두 β 대조 미측정(통과 불가)이어도 `p2_round_verdict` = `falsified(판정 8/8)`. 라벨에 판정어별 칸 수(β 대조 · 빠른 급락 · ⑭ 미측정)를 덧붙이고(`evaluate.R:568`), 규칙 문장 round_verdict 에 같은 문구를 둔다.
3. **R7 판독이 부분 판정에서도 참/거짓을 낸다**(`evaluate.R:673-687`). 장치 하나만 두 구성 판정돼도 그 S 증분으로 '잡음 이내'가 되고 프로그램 예산 R7(연속 K회 → 종료 검토)에 들어간다. 판독에 '두 구성 판정 장치 수/4'를 싣고 4 미만이면 NA 또는 '부분 판독' 꼬리표 — r7_reading 문장도.
4. **처치 방향 대체 신호일은 꼬리표뿐이다**(`evaluate.R:336-351` · `:1050-1051`). D03 · D04 · D07 은 IC 이력이 모자란 신호일에 레지스트리 표기로 공격 쪽으로 뒤집힌다(사전등록 adaptations). 설계 노트는 2005-01 ~ 2022-12 만 쟀다 — "2003-05-30 확정 < DNN 첫 신호"는 그 창 밖 진술이다. 평가 창에서 대체 신호일 > 0 이면 그 칸을 미시험(처치 방향 불일치)으로 하거나, 최소한 SUMMARY 열 · 콘솔 판정 줄(`:1319-1326`)에 그 수를 싣는다.
5. **등록 → 커밋 → 측정의 '커밋'을 기계가 보지 않는다.** register.R 은 고정 대상 커밋을 확인한 뒤 사전등록 두 사본 · 등록부를 쓰고(`register.R:394-409`), precheck.R 은 git_head 를 기록만 한다(`precheck.R:138-142`). precheck 본 대조에 "`git status --porcelain -- stage_artifacts/programs/P2_DEFENSE/P2R04_defensive_holdings/prereg.json <라운드>/prereg.json 06_Registry/research_programs.json` 비어 있음 ∧ HEAD ≠ git_head_at_register"를 더한다(precheck.R 은 평가 경로 핀 — 등록 전에만 고칠 수 있다).
6. **E3 용량 짝(W)은 방어 몫만이 아니라 엔진 알파 구성도 바꾼다.** 사양 23개 직접 재도출: E3 H = DNN 25 · 기존 25 · 방어 50(1 : 1) · E3 W = DNN 50 · 기존 37.5 · 방어 12.5(4 : 3) · E2 W 는 DNN 만 줄인 순수 용량 대비. 진단 읽기(용량) 문장에 "E3 용량 대비는 기존 팩터 몫 희석이 섞인다(도구 상자 기본 = P0R01 비교용)"를 적는다. 순수 용량판이 필요하면 기존 3팩터 × 7 + 장치 × 6 · base_weight 0.4375(DNN 43.75 · 기존 43.75 · 방어 12.5)가 정수 해다 — 칸 추가 여부는 이 라운드 범위 판단.
7. **보는 창 밖 작업 사본에 표식이 없다.** `results/<code>/original/rx0_beta_scaled/` · `results/<code>/common_*/{artifacts, rx0_artifacts}/` 는 전기간 수익 · 보유와 authoritative_remeasure.json 사본을 담는다(`p2_trim_artifacts` · `p2_beta_scaled_copy` 가 02~05 밖 파일을 통째 복사 — `evaluate.R:82` · `:111`). `results/<code>.json` · `.log`(러너 전기간 출력)도 같다. 그 폴더들에 NO_VISIBLE_REVIEW.txt 를 쓰고 rules.files 에 "보는 창 리뷰어 열람 가능 = evaluation_visible.json · `<code>/visible/` · `<code>/{original,common_*}/visible*/` 뿐"을 적는다.
8. **⑭ 해석 범위가 사전등록에 없다**(T1 자기 점검 2 · `20261018_1227_T1.md:139` · 사전등록 grep 0건). 분해 선택 항은 시장 β · EW−CW · 무신호 틸트 밖 전부(퀄리티 · 가치 · 모멘텀 노출)이고, t−1 적재라 위기 중 조건부 β 하락(H1 · H3 기전)도 선택 항으로 잡힌다. 결론 범위 2 · selection_attribution 에 한 줄.
9. **평가 지문 ≠ 측정 지문은 기록만 한다**(`evaluate.R:1251` · P2R03 점검 권고 2 의 잔여). 패킷 · MC8 · 노출 분해가 RAWDATA 를 다시 읽고, 수정주가 수준 · 위생 표식은 갱신 때 과거가 바뀔 수 있다. 판정 칸 묶음에서 다르면 최소 꼬리표.
10. **C-025 'H1 대 P2R03 D1 대조 읽기'는 changes_after_superfan 에만 있다**(`prereg_draft.json:1696-1698`) — rules.record · evaluate.R 에 없다. record 에 넣거나 '세션 보고 단계'로 명시.
11. **Q08 재무 원값 = restatement_prone ∧ vintage_available false**(`prereg_draft.json:1417-1418`) — 정정 공시가 과거 값을 덮는 PIT 경계다(C4 시차는 맞다 — `parse_fundamental_xlsx.R:205` Q4 = 익년 3/31). data_note · H4 결론 범위에 'PIT 경계 기록'으로. (E3 RX0 의 V10 도 같지만 짝 양쪽 공통이고, H4 는 처치 자체가 그 경계 위에 있다.)

## 3. 선택

1. `fingerprint.sh:18-19` 는 `.cache/factor_db/factor_registry.json` 을 stat 하는데 커넥터는 `02_Infrastructure/factor_db/factor_registry.json` 을 먼저 읽는다(`factor_db_connector.R:66-70`). 지금은 두 파일 md5 동일(d4780eb3)이고 엔트리 핀은 읽는 판을 본다 — 지문에 읽는 판을 넣는다.
2. 방향 기록 파서(`evaluate.R:323-326`)는 'PIT-safe' 줄 없는 방향 줄을 건너뛴다 — 커넥터는 IC 이력이 통째로 빈 신호일엔 그 줄 없이 방향 줄만 찍는다(`factor_db_connector.R:625-631` · `:671`). IC 첫 달뿐이라 평가 창 밖 — 파서 완결성만.
3. vintage_group 문장에 'IC 월간 이력(factor_ic_monthly.parquet)'을 넣는다(C-034 반영이 fingerprint.sh 에만 있다).
4. `evaluate.R:7` 머리 주석 "사양 = RX0 + 장치 팩터 하나" → "꼬리 반복 r 회"(필수 1 · 3 수정과 함께).
5. `eval_visible.json` 의 axis(rk_axis_audit — 전 구간 n_max_realized · w_min · sigma_w_max)는 전기간 집계다 — 성과 아님 · rules.files 에 '축 감사 = 전기간(성과 아님)'.
6. T1 C-028 사후 판독("8칸 모두 MC8 라벨과 분해 판정이 같으면 moot")용으로 라벨 · 분해 일치 칸 수를 VIS 요약에 싣는다.
7. 리허설 재료는 E2 1팩터 칸뿐이고(`rehearse.R:27`) 셀 엔진 스모크 검사에도 같은 팩터 반복 · null_perm · base_weight 1 경로가 없다. 코드 읽기로는 동작하고(태그 `.fv<k>` 따로 내부 병합 · 로그가 중복 포함 문자열 · 측정 경로 중복 제거 없음) 실패해도 미시험으로 접히지만, 첫 E3 장치 칸 직후 로그의 적재 줄(factors 9개) · 방향 블록 9 를 확인한다.

## 4. 확인한 것 (결함 없음)

**규칙 — 문장 = 코드**
- ① · ②: 엄격 `<`(RX0 − tol) · 과반 = 비율 `>` 0.5 · 짝 없는 위기 0 · 짝 ≥ 2 · 깊은 위기 짝 ≥ 2 아니면 미시험(`evaluate.R:146-157` · `:1057-1062`) · 깊은 위기 = 짝 위기 중 |bm_dd| ≥ 중앙값(`:174-181`).
- ③: k = 보는 창 behavior.stats.beta 비 · k < 1 = RX0 기간수익 · NAV · 보유 k 배 사본(`:108-127`) · **k ≥ 1(=1 포함) = 사본 RX0** · k 비유한 · ≤ 0 · RX0 β ≤ 0 · 사본 실패 = 미측정 · 짝 < 2 = NA → beta_unmeasured(`:130-137` · `:1067-1082` · `:549`).
- ④: a … min(저점, a + 21) = **21거래일 창 수익 · ≤ −20%**(+1e-12) · 벤치 = 같은 칸 RX0 산출물 일수익 누적곱 · 깊은 위기 제한 없음 · 비교 = ③ 사본 · 짝 < 2 = 미측정 · 일화 판(위기 안 월말 0 제외 = 2008-11)은 기록(`:185-204` · `:1064-1084`).
- ⑤: 하락/상승 β 비 Δ < 0 · 상승 β ≤ 0 · 비유한 → 미시험 · 수준 = 꼬리표(`:222-234` · `:1088-1092`) · 월 β 각 6개월 이상(`behavior_card.R:364-365`).
- ⑥: m ≥ r − **0.2**·|r| · 비율 > 0.5 · 짝 < 2 → 미시험 · 중앙값 ≥ 0.55(`:208-220` · `:1133-1134`).
- ⑦: t > **−2** 엄격 · 증분 ≥ −**0.2** × max(엔진 α, 0) · 둘 다 연율(`round_kit.R:106-121` · `evaluate.R:278-282` · `:978-984`).
- ⑧: 깊은 위기 top1 < −0.10 엄격 · 표 결손 · 깊은 위기 누락 = 미측정 → 둘 다 제외(`:265-276` · `:1191`).
- ⑨: 같은 짝만 · ≥ RX0 · 비율 > 0.5 · 짝 < 2 → 미시험(`:236-263`). ⑪: 검열 = 무한대 · 둘 다 검열 = 제외(`:284-299`).
- ⑫: S = 등급 v3 식(`round_kit.R:138-139`) · S_rx0 = 0 → Calmar. ⑬: mdd_vs_bench = 전략/벤치 MDD 비 · CDaR = 양수 낙폭 꼬리 평균 → `≤` 방향이 맞다(`behavior_card.R:220-224` · `:325-330`).
- ⑩: 꼬리 반복 m ≥ 1(E3 6회 허용) · 바탕 = RX0 factors · 장치 팩터 바탕 밖 · 변형/RX0 로그 적재 줄 = 사양(셀 엔진은 중복 포함 '+' 문자열 — `rf_cell_engine.R:1199`) · 판정 칸 무처치 = 미시험 · 진단 칸은 계속(`evaluate.R:354-382` · `:423-444` · `:1034-1040`).
- ⑭: AND(`:465-469`) · 라벨 어휘 = `matched_controls.R:437-439` · selection_sum 실재(`diagnosis_packet.R:184`) · 깊은 위기 고점일 대조 · 픽스처 뮤테이션이 AND 제거를 잡는다.
- 통과 = 12조건(`:537-540`) · 장치 검증 = 두 엔진 ∧ 제외 아님 · 판정 칸 수 표기(`:566-576`) · 선택 = S 증분 두 엔진 평균 · 차 < 1e-12 동률 → ③ + ④ 비율 합(`:578-591`) · R7 = 검증 0 ∧ ③ 두 구성 과반 장치 0 ∧ S 증분 최대 < tie_eps · 증분 없음 = NA(`:673-687`).
- 진단 읽기: 용량 표 7행(첫 일치) = 문장(+ E3 단독 통과 대칭 행) · 결측 짝 = Hk β 짝 승리 ∩ Ck 자기 β 짝 승리 · 희석 = ① 승리 겹침(`:44-51` · `:594-642`).
- 혼합 몫 재도출(사양 23개 직접): E2 H 0.5 · E3 H 0.5(DNN 0.25 · 기존 0.25) · E2 W 0.125(DNN 0.875) · E3 W 0.125(DNN 0.5 · 기존 0.375) · C 0(DNN 1) · N0 0.5 = `register.R:92-105` mix_plan = `evaluate.R:386-390` = 사전등록 cells(defense_share · device_repeat · base_weight). RX0 사양 = P2R03 RX0(code · label 밖 동일) · 장치 · 진단 사양 = RX0 + 팩터 · base_weight · 이름 · 회계만 다름. 23칸 측정 축 = all_hyg_px1000_2000_v1.
- final_selection_rule 14키 값 = P2R03 값(register.R 가 단정) · 근거 문장 승계 · mc8_label_required = selection_defense · 기록용 위기 = 설계 노트 줄 그대로(`round_rules.R:17-27`).

**정보 경계 τ_D**
- 패킷 = 적재 단계에서 수익 · 벤치 · 보유 · 시장 패널 · 벤치 이력을 τ_D 로 자름 + 날짜 전수 검사(`diagnosis_packet.R:237-238` · `:300-301`). 판정 입력은 전부 보는 창 패킷 · ym ≤ τ_D 월.
- 보는 창 파일 = `p2_visible_only`(시험 창 알파 · 표 행 · 셀 로그 months/rows · 사본 n_pr 제거 + 문자열 날짜 가림 — `evaluate.R:744-748`) + 쓰기 전 `dp_scan_dates`(`:1311-1312`). 기록 계산(크기 × β · 유동성 · 국면 월 · RX0 동일성 · A 거리 · 엔진 알파 · 집중 visible · 방향 기록)은 모두 ≤ τ 로 적재하거나 자른다(`:805-832` · `:834-879` · `:881-894` · `:1153`).
- 셀 로그에서 보는 창으로 가는 것 = cell · univ · factors · wt 뿐(`:378`). 칸 평가 콘솔 줄 = 보는 창 값(`:946`) · 계약 함수에 콘솔 출력 없음(grep) → **P2R03 노출 경로(샤드 로그 전기간 값)는 닫혔다.** 알림 = evaluation_visible.json 만(`notify.R:14`). A 거리에 시험 창 조건(OOS)이 없다.

**PIT**
- 팩터 = `load_month_factors` 단일 경유(`rf_cell_engine.R:278` · C15) · Z_Score_Aligned 만(`:281` · C13) · 커넥터가 결측 Z 를 지운다(`factor_db_connector.R:366` — `frank` 기본 na.last 로 결측이 최상위 순위를 받는 경로 없음) · 방향 = `Usable_Date ≤ 신호일` · 36행 확장창 IC 부호(`:206-221` · C14) · 방향 캐시 키 = IC 파일 mtime · 크기(`:169-185`) · IC 파일 = 지문 equality(`fingerprint.sh:19`).
- 집행 = close_t1(신호일 d 확정 비중 → 익월 첫 거래일 종가 · `replication_harness.R:141` · `backtest_harness.R:365-373`) → 신호일 종가까지 쓴 팩터 값과 시점 겹침 없음. Q08 Factor_Date = 분기 +45일 · Q4 익년 3/31(`parse_fundamental_xlsx.R:205` · `compute_quality.R` Factor_Date ≤ sig_d).
- 셀 엔진 팩터 결합 = 항목마다 태그 따로 내부 병합(`rf_cell_engine.R:332-338`) · base_weight 1 = 점수 DNN 100% 이고 병합은 그대로(`:360-364`) · null_perm = 그 신호일 패널 · 월별 시드(주 시드 흐름 접두 안정) · 전역 난수 복원 · 결측 필터 없음(`:296-325`). 워커는 사양 파일 그대로 엔진에 넘긴다 · 측정 경로에 팩터 중복 제거 없음(rf_runner_gates 는 측정 뒤 A 관문만 격리 적재).
- DNN 파이썬 코드 = engine.R 안(.PY_SRC → 핀이 덮음) · 예측 캐시 = 입력 내용 주소. MC8 플라시보 = 시드 고정(`matched_controls.R:78-83` · placebo_seed 20261013 · 핀 대상).

**측정 기계**
- 칸 23(변형 8 · RX0 2 · 진단 13) = `measure.sh:24-25 · 33` = 사전등록 cells = register plan = 픽스처 34 · E2 14 / E3 9 묶음.
- 묶음 지문 엔진별(`measure.sh:70-87` · `evaluate.R:1246-1251` — 진단 칸 처리는 필수 4) · 인프라 실패 1회 재측정(`measure.sh:62`) · 재측정 전 칸 평가 캐시 · 지문 삭제(`:55`) · 묶음 재측정은 json 삭제 → 같은 경로 · 캐시 산출물 = 현 측정 산출물 단정(`evaluate.R:1227-1231`) · 측정 연기 = 평가 중단(`:1237-1239`).
- 측정 · 평가 전 배리어(`measure.sh:46-48` · `:92-93`) · 센티널(`:30` · `:90` · `:96`) · 등재 = H 칸만 · RX0 · 진단 = QVEST_RP_REGISTER=0(`:56` → `run_paper_replication.R:891`) · 셀 칸 A 는 구판 judge_request.json(트리거 아님).

**등록 절차**
- R2: 측정 결과 · 사전등록이 있으면 거부(`register.R:241-243`) · 등록 = 고정 대상 커밋 확인 뒤(`:394-395`) · 철학 P1 수령 · 도전 응답 · 보류 요청 기계 확인(`:307-324`) · 판정 구현 정합 = evaluate.R 함수로(`:292-303`) · 교차 점검 보존본 · changes_after_review 없으면 거부(`:367-370`).
- 핀 현재 일치(직접 md5): 운영 38 · 평가 8 · 사양 23 · 검사 4 · 팩터 레지스트리 엔트리 7 · 비중 카탈로그 1 · 행동 카드 사본(= P2R03 사본 6a2a1d21). 리허설 요약 ec347c91 · evaluate md5 76e41a4e 일치 · 11단계 통과 · 실행 중 파일 불변.

**실패 의미**
- 칸 평가 stop → 그 칸 eval_error · 평가 계속(`evaluate.R:902-905`) · 짝 판정 예기치 않은 오류 → 그 칸 미시험(`:1195-1198`) · 기록 계산 실패 = 그 기록만 미측정(`:1177-1183` · `.safe_rec` `:1268`) · 크기 × β 미측정은 결론 이름 보류(`:560`). 미측정 꼬리표가 '통과'로 읽히는 경로는 없다(`isTRUE` · NA = 거짓 — 픽스처 28) — 반대 방향(미측정 → 기전 결론 · 반증)은 필수 3 · 권고 2.
