# P2R03 사전등록 초안 격리 교차 점검 v1

- 점검자: 격리 교차 점검(서브에이전트) · 2026-10-17 저녁 · 대상 = `prereg_draft.json`(draft_version 1 · 19:57) + `evaluate.R`(md5 87064991…) + 측정 기계
- **판정: revise(수정 후 등록)**
- **건수: 필수 4 · 권고 6 · 선택 4**
- 범위 단축: 코디네이터 지시(“지금 측정 착수 — 본 범위에서 마무리 · 필수 우선”)로 중간 종료. 못 본 영역은 §4 `미점검`.

## 0. 정보 경계 선언(열어 본 것)

- 라운드 폴더: `DESIGN.md` · `prereg_draft.json`(rules · final_selection_rule · budget · 구조) · `evaluate.R`(전문) · `measure.sh` · `fingerprint.sh` · `precheck.R` · `round_rules.R` · `rehearse.R`(grep) · `rehearsal/summary.json`(키만) · `specs/P2R03_E2_{RX0,D1,L1}.json`
- 계약 · 엔진: `04_Research/programs/_lib/{round_kit.R, eval_parallel.sh, measure_round_cell.R}` · `02_Infrastructure/contracts/diagnosis_packet.R`(전문) · `behavior_card.R`(150~429행) · `02_Infrastructure/reinforcement/rf_cell_engine.R`(960~1224행) · `git show b234afb11` · `02_Infrastructure/ops/refresh_barrier.sh`(머리 80행)
- 운영 로그: `.cache/scheduler_logs/daily_refresh.log` 꼬리 3KB(단계 로그 · 성과 수치 없음)
- P3R03: 디렉터리 목록만(파일 내용 미열람)
- **시험 창 · 전기간 성과 · results/*/full · eval.json test/full 블록 · evaluation(_full).json · authoritative_remeasure 등급 필드 · 차트 = 열지 않았다.** 실수로 연 것 없음.
- 실행한 것 없음(evaluate_fixture.R 도 시간 관계로 미실행).

## 1. 필수 (등록 전 수정 — evaluate.R 은 등록 때 md5 로 묶여 뒤에 못 고친다)

### 필수 1 — `evaluation_visible.json` 에 시험 창이 섞인 오버레이 노출 요약이 실린다 (τ_D 경계 · C-031 분리 위반)

- 위치: `evaluate.R:435`(`out$overlay <- ol`) · `evaluate.R:548`(`construction = list(overlay = ol, …)`) · `evaluate.R:605`(`p2_visible_only` 는 `alpha_test_window` · `tbl` 만 지운다) · `evaluate.R:683`(`cells = lapply(OUT, p2_visible_only)`) ← 원천 `rf_cell_engine.R:1163-1167`
- 재도출: 셀 로그 집행 줄의 `평균노출 · 최소 · 완전현금 c/N개월 · 현금 집행 k신호일` 은 `.expo` 전 구간(`.N` = 측정 전체 신호월 · 2026 까지)에서 센다. `p2_parse_overlay_log` 가 이 수치(expo_mean · expo_min · full_cash_months · n_months · cash_exec · xs_sd_max)를 그대로 `out$overlay` 와 `out$rules$construction$overlay` 에 담고, 보는 창 파일이 그것을 싣는다.
- 실패 시나리오: D5(추세 현금)의 보는 창 완전현금 달이 40 이고 전 구간이 46 이면, 보는 창 리뷰어(철학 P2 · 판단 Superfan)가 `evaluation_visible.json` 의 `full_cash_months 46/…` 과 보는 창 기록(`record$cash_timing`)의 차이로 “2023~ 에 6개월 현금이었다”(= 2026-06~07 급락 방어 여부)를 읽는다. 사람 쪽 전용(rules.files)이어야 할 시험 창 행동이 보는 창 파일로 샌다.
- 수리: `p2_visible_only` 에서 `x$overlay` · `x$rules$construction$overlay` 의 수치 필드를 지우고 `found · shift1 · kind · axis` 만 남긴다. 수치 필드는 `FULL$cells[[]]` 로 옮긴다. 보는 창 노출 요약은 이미 있는 `record$expo_m` · `record$cash_timing`(04_holdings ≤ τ_D)로 충분하다. 리허설 `visible_only_drops_test` 판정에 “overlay 수치 필드 없음”을 더한다.

### 필수 2 — 칸 평가(`p2_eval_cell`) 오류가 라운드 평가 전체를 멈춘다 (rules.failure_semantics 와 불일치)

- 위치: `evaluate.R:629`(`EVS <- lapply(CELLS, function(cl) p2_eval_cell(...))` — tryCatch 없음) · 멈춤 경로 = `diagnosis_packet.R:139 · 151 · 153 · 239 · 240 · 266 · 301` · `behavior_card.R:268` · `evaluate.R:367`(authoritative_remeasure.json 부재)
- 재도출: `p2_eval_pair_safe` 는 판정 단계만 감싼다. 그 전 단계인 칸 평가(dp_build · mc_card · rk_axis_audit)에서 stop 이 나면 샤드가 rc=1 로 끝나고, 종합 실행이 그 칸을 다시 평가하다 같은 stop 으로 **30칸 판정 전체가 안 나온다**. rules.failure_semantics 는 “그 밖의 예기치 않은 평가 오류 = 그 칸 미시험 · 라운드 평가는 계속”이다.
- 위험이 이번 라운드에서 특히 큰 이유: b234afb11 의 표현 하한 달(Σw ≈ 1e-9)이 dp_build · tilt_attribution · mc_card(MC8 짝 대조)를 지나간 적이 없다. 리허설 입력 P0R01_E2_C2(vol_scale)는 완전현금 0/322 이고, 리허설 산출물은 수리 전 측정이다. D3 · D5 · D6 · D7 은 표현 하한 달이 수십 개 생길 것이다.
- 실패 시나리오: D5 의 1e-9 달에서 `.dp_exposure` 의 노출 결측 가드(`:153`)나 MC8 짝 대조가 멈추면, E2 · E3 의 나머지 28칸까지 판정이 없다. 수리하려면 묶인 evaluate.R 을 고쳐야 해 R2 를 깬다.
- 수리: `p2_eval_cell` 호출을 `tryCatch(…, error = function(e) list(code = cl$code, status = "eval_error", err = conditionMessage(e)))` 로 감싼다. status ≠ "evaluated" 라서 짝 판정은 이미 `evaluate.R:430` 에서 미시험으로 접힌다. 캐시 대조 루프(`:630`)는 artifacts 가 없으니 건너뛴다. rules.failure_semantics 문장에 “칸 평가(진단 패킷 · 카드) 오류 = 그 칸 미시험(eval_error)”을 넣는다.

### 필수 3 — lag-1 판이 미시험이면 최종 선택 보류가 안 걸린다 (pit.md C5 의무 2 우회)

- 위치: `evaluate.R:307`(`p2_lag_hold` 가 `isTRUE(l_out$tested)` 일 때만 TRUE) · `:297`(lag 미시험 = 꼬리표 “lag-1 미시험”뿐) · `:664-667`(보류 = `held` 만 제외 → 검증 장치 · 선택)
- 재도출: rules.pit_construction (b) 의 보류 조건은 “lag-1 판이 못 넘으면”이다. lag-1 칸이 측정 실패 · 집행 줄 불일치 · 판정 입력 NA 로 미시험이 되면 보류도 걸리지 않는다. 장치 칸만 통과하면 그 장치가 그대로 선택된다.
- 실패 시나리오: E2_L5 가 두 번 다 인프라 실패(ok ≠ true)하고 D5 가 두 엔진에서 통과하면, `held` 가 비어 D5 가 선택된다. 오버레이 리서치 전 항목 의무인 lag-1 스트레스(pit.md C5 의무 2)가 없는 후보가 P4 · P3 의견서로 간다. 이것은 결측 입력이 조용히 ‘선택 가능’으로 바뀌는 경로다.
- 수리: `p2_lag_hold` 를 `isTRUE(d_out$tested) && isTRUE(d_out$pass) && !isTRUE(l_out$tested)` 일 때도 TRUE 로 한다(사유 “lag-1 미시험 — 의무 2 미충족 · 재측정 전 선택 보류”). rules.pit_construction (b) · rules.selection 에 “lag-1 판 미시험 = 보류”를 넣는다. 기존 (b) 의 “lag-1 판 짝 < 2 = 보류 아님”은 lag-1 이 판정됨(tested)일 때만 적용된다고 적는다.
- pit.md 정합: lag-1 을 통과 조건에서 진단으로 내린 것 자체는 pit.md C5 구조(lag-1 = 의심 신호 · strict A/B = 판정)와 맞는다. 이 경로의 컷오프는 엔진 `assert_overlay_pit`(실제 넘긴 값의 가용일 · 한계 = 홀딩 시작 전날 · `rf_cell_engine.R:1075-1078`)로 이미 strict 다. 다만 **lag-1 측정 자체가 없으면** 의무 2 가 빈다. 이 구멍은 이 항목으로 막아야 한다.

### 필수 4 — 묶일 규칙 문장의 칸 수가 코드와 다르다 (텍스트만 · 1분)

- `prereg_draft.json` rules.vintage_group “같은 엔진의 **13칸**(RX0 + 장치 **6** + lag-1 **6**)” → 코드 = 15칸(`evaluate.R:650` · `measure.sh:55` 반복 = RX0 + 14). rules.remeasure “RX0 먼저 단독 → **12칸**” → 14칸(`measure.sh:47,51`). rules.round_verdict “전체 장치 칸 **12**” → `p2_round_verdict` 의 분모 = nrow(TB) = 14. budget.note “변형 **12** · lag-1 **12**” → 14 · 14.
- 같이 고칠 것: `DESIGN.md:55`(“변형 6 × 엔진 2 = 12칸”) · `DESIGN.md:80`(제외표에 `dd_recovery` 가 남아 있는데 D7 = dd_recovery) · `measure.sh:53` 주석 “13칸”.
- 왜 필수인가: 사전등록 문장이 정본이고(DESIGN §머리 “둘이 다르면 사전등록이 이긴다”) 등록 뒤엔 바꿀 수 없다. 묶일 규칙이 “판정(n/12)”을 말하는데 기계가 “n/14”를 내면 판정 표기가 규칙 위반으로 읽힌다.

## 2. 권고 (짧게)

- **권고 1 — ⑪ 회복 꼬리표: 미회복 위기가 비교에서 빠진다.** 규칙 “미회복이면 관측 하한” ↔ `behavior_card.R:193`(중도절단 = NA) + `evaluate.R:237`(`is.finite` 로 제외). 바닥 뒤 현금에 머문 장치(D6 류)의 미회복 위기가 바로 이 꼬리표의 대상인데 세지 않는다. 텍스트를 코드에 맞추거나, 관측 하한(마지막 관측일까지의 거래일 · censored = TRUE)으로 채운다.
- **권고 2 — 평가 단계에 배리어가 없고, 평가 지문은 기록만 한다.** `evaluate.R:643,653`(`eval_matches_measure` 비강제) · `measure.sh:74`. 평가도 RAWDATA(mc_load_raw) · benchmark.parquet(bm_hist) · 시장 패널을 다시 읽는다. 평가가 갱신 창(00:03~)과 겹치면 다른 판본이나 쓰는 중인 파일로 패킷을 만든다. eval_parallel 앞에 `refresh_barrier.sh wait` 를 두고, 평가 지문 ≠ 측정 지문이면 멈추거나 꼬리표를 단다. 오늘 즉시 기동이면 평가가 자정 전에 끝나는지 확인한다.
- **권고 3 — 집행 줄의 kind 를 장치와 대조하지 않는다.** `evaluate.R:437`. `identical(ol$kind, P2R03_DEVICES[[dev]]$kind)` 를 더하고, RX0 로그에 overlay 줄이 없음도 단정한다(사양 md5 가 막지만 집행 증거라면 집행된 층이 맞는지까지).
- **권고 4 — ⑤ 변화량에 여유가 없다.** `evaluate.R:151` 은 `rv < rr` 엄격 비교만 한다(①~④ 의 tol 0.03 과 비대칭). 거의 개입하지 않는 장치도 잡음으로 ⑤ 를 넘는다. 설계 선택이면 그대로 두되, delta 와 RX0 비를 보고에 함께 싣는다.
- **권고 5 — 리허설이 새 경로 셋을 밟지 않았다.** ① 표현 하한 달(1e-9 보유)이 `p2_subset_check` · `p2_cash_timing` · dp_build 를 지나는 경로 ② 실제 lag-1 로그(‘overlay_shift=1 적용’ 줄 있음) ③ lag-1 미시험 → 선택 경로. 픽스처에 합성 보유(1e-9 달 포함)를 넣어 ①·③을 고정한다. 필수 2 가 ①의 피해를 칸 하나로 묶는다.
- **권고 6 — 엔진 신호일 소실 가드의 사각.** `rf_cell_engine.R:1135` 의 스칼라 분기는 `merge(PORTFOLIO, .EX, by = "Date")` 내부 결합이라 `.M` 밖 신호일 행이 먼저 지워진다. `.d_pre`(`:1152`)는 결합 뒤에 계산돼 그 소실을 못 본다. 벡터 분기(`:1133`)는 oe = 1 로 남긴다. 보는 창 영향은 확인하지 못했다(벤치 범위 밖 = 주로 마지막 신호일). 최근 갱신이 `benchmark_currency` 실패로 끝나 마지막 달에서 이 경우가 생길 수 있다. `.d_pre` 를 결합 전에 계산하거나 `all.x = TRUE` + `oe := 1` 로 맞춘다. 엔진 수리라 이 라운드 핀 밖이고, 보고에만 적는다.

## 3. 선택

- **선택 1** `p2_select`(`evaluate.R:290-292`): 동률 처리가 정확히 같을 때만 r34 로 간다. 차 < 1e-12 이지만 0 이 아니면 dS 순서가 그대로이고 `tie_break` 표식만 붙는다. 규칙(“차 < 1e-12 이면 ③·④”)대로 하려면 dS 를 1e-12 격자로 반올림한 뒤 정렬한다.
- **선택 2** 빠른 급락 분류 오류(`evaluate.R:482-483`)의 `fk$err` 가 `RL$fast` 에 실리지 않는다. 분류 실패가 ‘짝 < 2’로 보인다. `why = fk$err` 를 더한다.
- **선택 3** 갱신 완료 줄은 단계가 실패해도 찍힌다(최근 줄 “실패 2스텝: benchmark_currency … @ Sat Oct 17 02:55:46”). 즉시 기동이면 이 배치(10-17 02:55 · 벤치 갱신 실패)를 precheck.json 에 갱신 상태 줄로 기록한다.
- **선택 4** 빠른 급락 창은 `lvl[a..a+21]`(수익 21개)이다(`evaluate.R:114`). 규칙 문장에 ‘21거래일 수익’으로 명시해 20/21 해석 여지를 없앤다(2002-04 −21.2% 처럼 경계 근처 위기가 있다).

## 4. 미점검 (시간 종료)

- `register.R` 의 operational_pins 42파일 · evaluation.files 6 · 카탈로그 핀 목록의 완전성(점검 항목 4)은 열지 않았다. 판정 경로가 실제로 source 하는 파일(round_kit.R · diagnosis_packet.R · behavior_card.R · matched_controls.R · grade_v3.R · tilt_attribution.R · beta_controlled_alpha.R · program_registry.R · backtest_harness.R(get_execution_date) · 행동 카드 설정 사본)이 모두 핀에 있는지 대조가 필요하다.
- 하네스(`replication_harness.R::run_replication_simulation`) 비용 기장 · 04_holdings 의 1e-9 기록 여부 · `test_rf_overlay_full_cash.R` 실행 확인. 커밋 메시지 · 엔진 주석의 진술만 봤다.
- E3 사양(lean:entropy · rank_buffer)과 rank_buffer 내부. 엔진상 rank_buffer 는 선정 단계 규칙이고(`rf_cell_engine.R:1189-1192`), 오버레이는 그 뒤 비중에 곱한다. 순위 버퍼가 직전 *비중*을 읽는지는 확인하지 않았다.
- 벡터 arm(dbeta_tilt · gen_20260903_133452) · ml_tail_gate 의 `.USED_CUT` 산출 · `assert_overlay_pit` 본문 · `test_rf_overlay_pit_mask.R`.
- matched_controls(mc_controls · mc_attribution)가 1e-9 노출 달을 어떻게 다루는지.
- `evaluate_fixture.R` 실행 · 뮤테이션 테스트 내용 · P3R03 reviewed v1~v3 대비.
- conclusion_scope · fast_crash_prior 표 재계산 · 30사양 전수 대조(E2 RX0 · D1 · L1 만 봄 — L1 = overlay_shift 1 · 같은 arm · 같은 축 확인).

## 5. 점검했고 결함 없음

- ① · ②: 엄격 `<`(RX0 − tol) · 과반 = `>` majority_share · 짝 ≥ 2 · 깊은 위기 = 짝 위기 중 |bm_dd| ≥ 중앙값 · 짝 없는 위기 ≠ 0 → 미시험. 규칙 = 코드.
- ③ · ④: k = 보는 창 β 비 · k ≥ 1 → 사본 = RX0 · k 비유한 · 음수 · 사본 실패 · 짝 < 2 → ‘미측정’(통과 불가 · `isTRUE`) · ④ 비교 대상 = ③ 사본 · 빠른 집합 = RX0 산출물 벤치 일수익. 규칙 = 코드.
- ⑤: 비 · 상승 β ≤ 0 · 비유한 → 판정 입력 NA → 미시험. 수준은 꼬리표만.
- ⑥: `m ≥ r − (1 − 0.8)|r|` · 비율 > 0.5 · 짝 < 2 → NA → 미시험 · 중앙값 ≥ uc_floor.
- ⑦: d_alpha · 엔진 α 둘 다 `alpha_ann`(연율 · `round_kit.R:117` · `evaluate.R:423`) 단위 일치 · t > −2 엄격 · 여유 = 0.2 × max(엔진 α, 0).
- ⑨: 같은 짝만 · ≥ RX0 · 비율 > 0.5 · 짝 < 2 → NA → 미시험.
- ⑫ · ⑬: S 식 = 등급 v3 · S_rx0 = 0 → Calmar. mdd_vs_bench = 전략 MDD / 벤치 MDD · CDaR = 양수 낙폭 평균(`behavior_card.R:220-224 · 325-329`) → `≤` 방향이 맞다.
- ⑧: 깊은 위기 한 종목 최악 기여 `< −0.10` 엄격 · 표 결손 · 깊은 위기 누락 → 미측정 → 제외(`excluded = !identical(cst, "clear")`).
- 묶음 지문: evaluate.R(15코드/엔진) = measure.sh same_fp(RX0 + 14) · MISSING → 불일치 판정 · 실패 칸도 fp 파일을 쓴다(`measure.sh:40,42` → NA 로 전체 중단 없음).
- 재측정: `m()` 이 옛 칸 평가 캐시 · json · 지문을 지운 뒤 잰다 · 셀 로그는 system2 가 덮어쓴다(옛 집행 줄 잔존 없음) · 묶음 재측정도 json 삭제 → `m()` 경로.
- 보는 창 패킷: 적재 단계에서 τ_D 로 자르고 날짜 전수 검사를 한다(`diagnosis_packet.R:237-238 · 300-301`). 판정 입력은 전부 보는 창 패킷 · 보는 창 월(ym ≤ τ_D) 필드다(필수 1 의 기록 필드 제외).
- 엔진 수리 b234afb11: 하한은 ‘수리 후 Σ ≤ 0 ∧ 수리 전 Σ > 0’인 신호일에만 건다. 일부 종목 0(벡터)은 행만 빠지고 신호일은 남는다. Σw ≤ 1 이 유지된다. lag-1 지연은 하한 전에 적용돼 지연된 0 달도 하한을 받는다. `rk_axis_audit`(w ≠ 0) · `p2_subset_check`(w > 0) · `p2_cash_timing`(e ≤ 0.5) 모두 1e-9 를 보유 · 현금 달로 바르게 읽는다.
- 집행 줄 정규식: 엔진 출력 `[rf_cell_engine] overlay <kind> | 축 …` · `overlay_shift=1 적용` 과 맞는다. 셀 로그 = `results/<code>.log`(rk_measure_cell system2 stdout · 리허설 R1 이 같은 경로에서 찾았다).
- measure.sh 대기: `[ "$hh" -ge 6 ]` 은 "08" · "09" 를 10진으로 읽는다(test 내장). 매일 00:03(일요일 포함) 트리거와 맞다. 즉시 기동 옵션을 넣어도 배리어 · precheck · 지문은 그대로라 판본 일관성은 지문이 지킨다.
