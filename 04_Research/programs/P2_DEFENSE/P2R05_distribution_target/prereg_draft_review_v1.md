# P2R05 사전등록 초안 격리 교차 점검 v1

- 점검자: 격리 교차 점검(서브에이전트 · 이 라운드 설계 · 구현 비참여 · 측정 결과 없음) · 2026-10-18
- 대상(md5 앞 8자리): `prereg_draft.json`(draft_version 1 · c0762574) · `evaluate.R`(d4b79ea4) · `round_rules.R`(0757baa0) · `evaluate_fixture.R`(ce9da970) · `rehearse.R`(4b7e869c) · `rehearsal/summary.json`(9a595de4) · `register.R`(10b6cc60) · `precheck.R`(4bfad0ed) · `engine_checks.R`(8f5a7944) · `measure.sh`(3d74ce68) · `measure_now.sh`(43de9b61) · `measure_now_vram.sh`(2305f1fd) · `warm_cache.sh`(ace36eb9) · `warm_engine.R`(0397072c) · `fingerprint.sh`(61ef8750) · `notify.R`(5b60ef03) · `notify_done.sh`(8cda1b2f) · `make_specs.py`(e6d82d54) · `exposures_agents.json`(37ffc4e4) · `specs/` 16 · `DESIGN_draft.md`(1a1a59e8) · DT 엔진 `engine_template.R`(e998c0af) · `make_engines.R`(930f4277) · `template_diff_check.R`(85cb0070) · `engines_manifest.json`(b88e0d12) · 생성 엔진 7 · `rx0s/engine_RX0S.R`(376a45e2) · `positive_control_rehearsal.json`(552a38d7) · `README.md`(ba42cb68) · 원본 `RP_AUTO_2002_06975/engine.R`(6b6a8e1a)
- **판정: revise(수정 후 등록)** — ①~⑭ 승계 판정 경로(함수 62/72 가 P2R04 와 본문 동일) · ⑩ 개정 · ⑮ 꼬리 계기 · PIT 골격 · 핀 130개 · 측정 순서 · 시행 회계는 문장과 코드가 맞는다. 다만 **판정어 이름 하나 · 결론 이름 하나가 사전등록 문장과 다르게 붙고**, **규칙 문장(rules.conclusion_scope)에 대체된 옛 문장 둘이 다른 규칙과 정반대로 남았고**, **⑮ 의 입력 예측표가 측정에 묶여 있지 않다**. evaluate.R · round_rules.R · measure.sh 는 평가 경로 핀이라 **전부 등록 전에만 고칠 수 있다.**
- **건수: 필수 4 · 권고 9 · 선택 6**

## 0. 정보 경계 선언

- 연 것(P2R05): `prereg_draft.json`(전 절 — 파이썬으로 구조 · 문장 · 핀 판독) · `evaluate.R` 전문 · `round_rules.R` 전문 · `evaluate_fixture.R`(머리 · N25 · grep) · `rehearse.R`(머리) · `rehearsal/summary.json`(단계 통과 · 판정어 · 사유 코드) · `register.R`(420-450 · 580-660 · 700-735 · grep) · `precheck.R` 전문 · `engine_checks.R`(머리 · grep) · `measure.sh` · `measure_now*.sh` · `warm_cache.sh` · `warm_engine.R` · `fingerprint.sh` · `notify_done.sh` · `notify.R`(grep) · `exposures_agents.json`(누가 · 언제 · 길이) · `specs/` 16(파이썬 diff — RX0 대비) · `lane_hold.py`(머리) · `lane_hold_wait.sh` · `lane_hold.log` · `DESIGN_draft.md`(§0b · §0 · §2 ~ §10)
- 연 것(DT 엔진): `engine_template.R` 전문 · `template_diff_check.R` 전문 · `make_engines.R`(머리) · `README.md`(§7 ~ §10) · `tests/`(run_all_tests.R · rule_smoke_test.R 머리 · diff_check_mutation_test.R 머리) · `tests/_out` 결과 JSON · 로그(pc_mutation · rng_stream_facts · py_e2e · engine_dryrun · static_pit · rule_smoke — 전부 합성 · CPU) · 원본 engine.R(대체 구역의 원본 행)
- 연 것(그 밖): `_design_notes/{onset_state_classify.{md,json}, state_turn_classify.md, crisis_type_asof.md(+ .R grep)}`(벤치 · 위생 유니버스 일수익 · ≤ τ_D · 전략 성과 무관) · P2R04 `prereg.json`(exposures · rules · final_selection_rule · design_inputs · budget — 결과 블록 없음) · P2R04 `evaluate.R`(함수 본문 대조만) · P2R04 `prereg_draft_review_v1.md`(형식) · `rf_cell_engine.R`(80-190 · 1197) · `rf_base_cache.R`(150-165) · `measurement_axis.R`(120-200) · `backtest_harness.R::load_rawdata` · `backtest_result_contract.R::.nw_t_mean` · `.cache/RAWDATA.parquet` **스키마(열 이름 · 형만)**
- **안 연 것**: P2R03 · P2R04 `results/` 전부(evaluation_*.json · 칸 json · 로그 · 디렉터리) · `stage_artifacts/replication/` · 어떤 authoritative_remeasure.json · behavior_card(칸 산출) · ROUND_REPORT · failure_map · visual/ · `rehearsal_run.log` · `register_draft.log` · Superfan 리뷰 · 판단 원장 본문 · 예측 · 진단 parquet. 시험 창 · 전기간 **전략 성과** 수치를 연 것 없음.
- 노출 고지: 하네스가 자동 주입한 MEMORY 색인 문장(예: 2026-06~07 KOSPI200 −40.9% · DNN 계열 MDD 요약 등 시험 창 · 전기간 요약 문장 포함)이 컨텍스트에 있었다 — 점검 판정 · 권고에 쓰지 않았다. 사전등록 · DESIGN 이 싣는 보는 창 수치(§0b · §6 · expectations.note)는 읽었다.
- 실행한 것:
  - `Rscript evaluate_fixture.R`(R 임시 폴더에만 씀) → **94/0 · 뮤테이션 63/63 · 8초**
  - `Rscript tests/run_all_tests.R --fast`(CPU) → **4/4 rc 0**(template_diff_check rc 0 · 차분 검사기 양방향 17/17 · rule_smoke 139/139 · static_pit clean 9 + 검사기 양성 대조 2/2) · 20초. ★이 묶음은 `tests/_out/` 의 시각 기록 JSON 4개를 덮어쓴다 — 실행 전 `tests/_out/` 44개 파일을 스크래치패드에 백업하고 실행 뒤 원본으로 복원했다(md5 44/44 원상 · DT 루트 파일 불변 확인).
  - evaluate.R 함수를 격리 환경에 적재한 재현(합성 입력 · 쓰기 = 스크래치패드 임시 폴더만 · 끝나고 삭제): R1a ~ R1c · R2 · R2b · R3 · R4a ~ c · R5 · R6 · R6b(아래 각 항목) · P2R04/P2R05 evaluate.R 함수 본문 대조(deparse).
  - 파이썬(읽기만 · `-I`): 핀 130개 md5 대조 · 사양 16 diff · 앞선 사전등록 n_family 최댓값 재도출 · 승계 문장 동일성 · P2R04 exposures 대조 · 시험 결과 JSON 요약 · RAWDATA 스키마.
  - 측정 · 워밍 · GPU · 등록 · 커밋 · 대상 파일 수정 없음(쓰기 = 이 파일 하나 · tests/_out 은 위처럼 원상 복원).

## 1. 필수 (등록 전 수정)

### 필수 1 — 판정어 `defense_but_strength_or_path` 에 '꼬리 회피 기계(방어만 · 복리 없음)' 이름을 붙였는데, 그 조건이 규칙 문장의 '꼬리 회피 기계' 정의와 다르다

- 문장: `prereg_draft.json:834`(rules.conclusion_names ← `round_rules.R:166`) · `:129` 결론 범위 3 — "③ · ④ · ⑭ 를 넘었으나 **⑥ · ⑦ · ⑨ · ⑫ · ⑬** 중 하나라도 못 넘으면 '꼬리 회피 기계(방어만 · 복리 없음)'".
- 코드: 판정어 = `evaluate.R:528-538` `p2_cell_verdict`(P2R04 그대로 — ①∧②∧③∧④ ∧ ⑭ ∧ ¬통과 → `defense_but_strength_or_path`) · 이름 = `:89` `P2R05_VERDICT_NAMES` 가 이 판정어를 '꼬리 회피 기계(방어만 · 복리 없음)'로 개명(P2R04 = '저변동 기계' · 정의 문장 없었음) · `:93` SHORT '꼬리 회피 기계' · `notify.R:26` 은 또 다른 문구 '꼬리 회피 기계(방어만 · 복리 미달)'. 결론 꼬리표는 따로 `p5_conclusion` `:1868`(③ ∧ ④ ∧ ⑭ ∧ ¬(⑥⑦⑨⑫⑬ 전부) — 문장 그대로)이 만든다. 판정어 쪽은 ⑤ 와 ⑮ 를 보지 않는다.
- 재현(evaluate.R 함수 그대로):
  - R1a — ①②③④⑭ · ⑥⑦⑨⑫⑬ 통과 · **⑤(β 비 Δ)만 실패** → 판정어 = '꼬리 회피 기계(방어만 · 복리 없음)' · 같은 칸 결론 `machine = FALSE`(꼬리표 없음).
  - R1b — ① 실패 · ③④⑭ 통과 · ⑥ 실패 → 판정어 = '결정 미달' · 결론 꼬리표 = '꼬리 회피 기계'. 한 칸에 두 이름이 엇갈린다.
  - R1c — 진단 W2(13조건에 ⑮ 포함 · `:2301`)가 **⑮ 만 실패** → '꼬리 회피 기계'. 진단 칸은 `p5_apply_tail_gate` 를 거치지 않는다(`:2452` 는 판정 칸만 · `:2458-2464`).
- 왜 필수: 판정어별 칸 수는 라운드 판정 문장(rules.round_verdict '판정어별 칸 수' · `:561` · `:2563`)과 실패 지도 · 교훈 카드의 입력이다. β 비대칭 실패(⑤)나 계기 실패(⑮)를 '복리 없음'으로 적으면 실패 기전이 바뀐다. P2R04 는 이름에 정의가 없어 모순이 없었지만 P2R05 는 같은 이름에 정의를 새로 박았다.
- 고칠 방법(둘 중 하나): (a) 판정어 이름을 중립으로 되돌린다 — '방어 · 강도 또는 경로 미달(①~④ · ⑭ 통과 · ⑤ ⑥ ⑦ ⑨ ⑫ ⑬ 중 미달)' — '꼬리 회피 기계'는 결론 꼬리표(`p5_conclusion`)만 쓴다. (b) `p2_cell_verdict` 에 ⑤ 실패(→ 'β 비대칭 미달') · ⑮ 실패(W2 → '꼬리 계기 미달')를 먼저 가르고 남은 경우만 '꼬리 회피 기계'. 어느 쪽이든 `P2R05_VERDICTS` · `VERDICT_NAMES` · `VERDICT_SHORT` · `notify.R:26` · 픽스처(판정어 뮤테이션 포함) · rules.round_verdict/conclusion_names 문장을 같이 고치고 리허설을 다시 돌린다(register.R 이 리허설 evaluate md5 를 대조한다).

### 필수 2 — LV 대비 이름 '원천 ① 증분 없음(저용량 변동성 스크린과 같음)': 사전등록 안에 정의가 둘이고, 코드 · 픽스처는 좁은 쪽을 고정했다

- 정의 A — `prereg_draft.json:345` comparison.reading(← `register.R:724`) · DESIGN §0b 8(`DESIGN_draft.md:26`): "**Vk 의 β 짝 승리 위기가 모두 LV 의 β 짝 승리 위기이고** 그 어느 위기에서도 Vk 가 LV 를 tol 이상 이기지 못하면 '원천 ① 증분 없음' · LV 대비 판독은 LV 가 β 짝을 이긴 깊은 위기에서만".
- 정의 B — `:833` rules.diagnostics_reading · `:834` conclusion_names(← `round_rules.R:157-159` · `:167-168`): LV 승리 깊은 위기에서만 비교하고 그 위기들에서 Vk 가 LV 를 tol 넘게 못 이기면 '증분 없음' — **⊆ 조건이 없다**.
- 코드 = B: `evaluate.R:1767-1786` `p5_read_lowvol` — Vk 의 β 짝 승리 위기(`variant_wins` · `:1773`)는 기록만 하고 이름에 쓰지 않는다. 픽스처 N25(`evaluate_fixture.R:598` lw_c · `:601` lw_0 · `:603`)가 B 를 고정한다.
- 재현: R2 — Vk 가 2008-05 · 2011-05 두 깊은 위기 모두 β 짝 승 · LV 는 2008-05 만 승 · 2008-05 포착 같음 → '원천 ① 증분 없음(저용량 변동성 스크린과 같음)'(LV 가 못 이긴 2011-05 를 Vk 가 이겼는데도). R2b — Vk β 짝 승리 0 · Vk 포착 0.70 대 LV 0.51 · 0.42(**LV 보다 나쁨**) → 같은 이름.
- 왜 필수: 같은 결론 이름이 등록 문서 안에서 두 정의를 갖는다. B 는 'LV 밖 증분'(LV 가 못 이긴 위기를 Vk 가 이김)과 'LV 보다 나쁨'을 모두 'LV 와 같음'으로 접는다 — 결론 범위 2 · 12 · 다음 행동 B('꼬리 = 변동성 대리 · LV 대비 기록')의 입력이다.
- 고칠 방법: 한 정의로 묶는다. 권장 = '원천 ① 증분 없음(저용량 변동성 스크린과 같음)' ⇔ LV β 짝 승리 깊은 위기 ≥ 1 ∧ 그 위기들에서 Vk 가 LV 를 tol 넘게 못 이김 ∧ **Vk 의 β 짝 승리 깊은 위기 ≥ 1 ∧ ⊆ LV 의 β 짝 승리 깊은 위기**. Vk 승리가 LV 밖에 있으면 'LV 밖 증분 있음(n 위기)' · Vk 승리 0 = 'LV 대비 판독 해당 없음(Vk β 짝 승리 0)'. C-058 의 '비교 범위 = LV 승리 위기'는 포착 비교 범위로 그대로 둔다. `p5_read_lowvol` · round_rules.R 두 문장 · register.R comparison.reading · 픽스처 N25(lw_c · lw_0 기대값) · 뮤테이션 1건 추가.

### 필수 3 — 규칙 문장 rules.conclusion_scope 에 대체된 옛 문장 둘이 남아, 같은 사전등록의 다른 규칙과 정반대다

- 위치: `prereg_draft.json:838`(← `round_rules.R:191-196`).
  - (a) `round_rules.R:196` "**단일 시드라 시드 잡음 띠가 없다** — 결론에 '단일 시드 · 잡음 띠 미측정' 꼬리표(DESIGN §0b 결정 2)". 반대 문장: §0b 14(열린 질문 2 뒤집음 · `DESIGN_draft.md:35` · 표 2행 `:58`) · 결론 범위 8(`:129`) · rules.conclusion_names(`round_rules.R:170` "재시드 칸이 없거나 실패 = '시드 띠 미측정'") · 재시드 칸 2 · 코드(`evaluate.R:1871-1872` — 띠가 있으면 '단일 시드' 꼬리표를 붙이지 않는다). 출처 = DESIGN §10.8(`:655`)의 조건문('열린 질문 2 를 넣지 않으면')이 무조건문으로 옮겨졌다.
  - (b) `round_rules.R:194` "결합은 **사전 분류된 위기 유형 기전** · 새 사전등록 · …". 반대 문장: §0b 9(`:27` "위기 유형 분류는 시작 시점에 보이지 않으므로 결합 기전은 위기 진행 중 as-of 상태 · …") · §0b 26(`:52` 진행 중 as-of 상관 상태도 반증) · 결론 범위 6. '사전 분류된 유형'은 바로 쓸 수 없다고 판명된 기전이다.
  - 같은 문장의 참조 '(DESIGN §0b 1 · 5)'(§0b 1 = 대체 표시) · '(변형 대 RX0)'(C-069 · 결론 범위 11 = 'V · S · Q50 · RX0 나란히')도 옛 판이다.
- 왜 필수: rules 는 판정 · 이름의 정본이고 round_rules.R 은 평가 경로 핀이다 — 등록 뒤 고칠 수 없다. 픽스처(`evaluate_fixture.R:706`)는 '결합 금지: … 짜지 않는다' 앞부분만 단정해 이 모순을 못 잡는다.
- 고칠 방법: (a) → "시드 띠 = 같은 구성 재시드 칸(RX0S) 대 RX0(결론 범위 8 · 꼬리표 = rules.conclusion_names) · 분위 모형 자체는 단일 시드(V 칸)" (b) → "결합은 위기 진행 중 as-of 상태(진행 중 상관 상태는 반증 — §0b 26) · 별도 사전등록 · 결합 칸 자체 판정 · 시행 수로만" · 참조 §0b 6 · 21. 픽스처에 두 문장의 새 문구 단정을 더한다.

### 필수 4 — ⑮ 의 입력 예측표가 측정에 묶여 있지 않다: `_work/qpred` 의 모든 파일을 읽어, 재워밍이 남긴 옛 판본이 있으면 평가가 멈추거나(보는 창이 다를 때) 사람 쪽 꼬리 기록이 사라진다(시험 창만 다를 때)

- 위치: `evaluate.R:2401` `p5_qpred_load(file.path(ROOT, P2R05_QPRED_DIR), TAU)` — `files` 인자 기본 = 폴더 전체(`:1125-1127`) · `:1144-1145` 보는 창 불일치 = `p5_halt` · `:1146-1148` 시험 창 불일치 = `Qall = NULL` → `:2424` 사람 쪽 판(TAILF) 미산출. 엔진은 데이터 지문마다 새 이름으로 쓴다(`engine_template.R:1105-1108`) · 옛 파일을 정리하거나 격리하는 곳이 없다(measure.sh · warm_cache.sh · warm_engine.R · precheck.R grep 0). DT `README.md` §9 항목 11 은 "평가는 같은 이름(CODE_VERSION md5 + 지문)의 파일 또는 첫 실행 로그를 쓴다"고 적었다 — 구현(폴더 전체)과 다르다.
- 생기는 경로: 워밍(계획 ≈ 8시간) 중 일일 갱신 → finalize `status=failed`('워밍 중 데이터 판본이 바뀌었다' · `warm_engine.R:174`) → 재워밍 · 또는 `measure.sh --rewarm`(지문 낡음 · `:89-91`) → `engine_Q50.R` 가 새 지문 이름으로 다시 씀 → 폴더에 두 판. 달 경계를 넘으면 시험 창 달 수가 달라지고(R6b), 수정주가 소급 조정(동전주 바닥 멤버십 · 거래대금 특징)이 과거 달의 X 를 바꾸면 보는 창 q 열도 달라진다(R6).
- 재현: R6 — 합성 두 판(보는 창 q10 1e-6 차) → `[P2R05 평가 중단] 예측표 판본 불일치` · R6b — 보는 창 같고 시험 창 달 수만 다름 → status ok · `full_status = test_window_mismatch` · `Qall = NULL`.
- 왜 필수: ⑮ 는 V 칸 4개 전부의 시험 조건이다. 평가가 멈춘 뒤 어떤 파일을 버릴지는 사전등록에 없다 — 결과 경로에서 수작업 개입이 된다. evaluate.R · measure.sh 는 평가 경로 핀이라 등록 전에만 고칠 수 있다.
- 고칠 방법: evaluate.R 이 측정에 묶인 워밍 센티널 사본 `results/warm_sentinel.json` 의 `qpred = {path, md5}`(`warm_engine.R:86-95` · `:189` 가 이미 기록)의 파일 1개만 읽는다(`p5_qpred_load(files = …)` — 인자가 이미 있다) · md5 대조 · 분위 칸 셀 로그의 `[DT qpred] path=` 줄(`engine_template.R:1126`)이 있으면 모두 같은 경로여야 한다(다르면 평가 중단) · 폴더의 다른 파일은 '판본 다른 예측표 n개(기록만)'. rules.tail_instrument · failure_semantics 문장 · 픽스처(여러 판 중 묶인 판 선택 · 묶인 판 md5 불일치 = 중단) · 리허설 재실행. (대안: `measure.sh` 가 워밍 단정 뒤 묶이지 않은 판을 `_work/qpred_superseded/` 로 옮기고 측정 로그에 남긴다.)

## 2. 권고

1. **옛 문장 · 옛 이름(필수 3 밖 · 규칙 밖 절)**
   - (a) purpose(`:128`) · 결론 범위 13(`:129`) · budget.stop_report(`:2008`)(← `register.R:593-594` STOP4_TXT) — "위기 진행 중 as-of 결합 = **상태 정의 미측정**". §0b 26 · rules.pause_report(`:837`) · `evaluate.R:1513` 은 "상관 상태로는 반증". 정지 보고 (2) 문구가 한 사전등록 안에 두 판이다.
   - (b) rules.record(`:842` ← `round_rules.R:221`) "**꼭대기 시작 위기**(_design_notes/onset_state_classify.json table from_top) 대 그 밖 위기" — 결론 범위 10 · §0b 10 이 허용한 이름('상태 미전환 최대 하락 위기' · 'systemic / dispersed') 밖이다. 그리고 결론 범위 10 의 "'상태 미전환 최대 하락 위기'(**onset_state_classify**)"는 파일이 틀렸다 — 그 2위기(2007-10 · 2011-05) 집합은 `state_turn_classify.md`(final_selection_rule.state_unturned_max_drop_crises_evidence 와 같다)이고 `onset_state_classify.json` from_top 은 판정 창 6위기다. DESIGN §0b 4(`:17`)의 같은 오기가 옮겨 왔다. 같은 record 문장의 'DESIGN §0b 4' 참조(`round_rules.R:217`)도 §0b 10 으로.
   - (c) changes_after_superfan(`:2028`) "V1 = **엔진 보존형**" — vocabulary · 결론 범위 14 는 'Q50(같은 추첨 중앙값) 순위 보존형'으로 정정됐다.
   - (d) expectations.V2(`:896` ← DESIGN §6 `:493`) "'**저변동 기계**(방어만 · 복리 없음)'" — P2R05 어휘는 '꼬리 회피 기계'(필수 1 과 함께 정리). 채점 대상 문장이다.
   - (e) reseed.note(`:370` ← `register.R:733`) "DESIGN §3.1 '공통 난수 아님' … 구현 에이전트가 코드로 확인해 **고친다**" — 사실은 이미 확인됐다(DT README §7 · `tests/_out/rng_stream_facts.json`: 은닉층 초기값 · 미니배치 순서 같음 · CPU dropout 다름 · CUDA 는 코드 구조상 dropout 흐름까지 공유 — 미실측) · DESIGN §3.1(`:259-260`)은 그대로다. 같은 사실이 reference.same_draw(`:227`) · 결론 범위 15 의 "변형(분위 모형)과 RX0(평균 모형)는 **다른 학습 추첨**"의 강도를 바꾼다 — CUDA 에서는 출력층 초기화 · 손실만 다른 '공통 난수에 가까운 짝'이라 RX0S 띠(시드 전체 교체)는 V − RX0 결정의 시드 잡음을 넓게(보수적으로) 잡는다. 문장을 사실대로 바꾸고 DESIGN §3.1 도 고친다(설계 입력 핀 갱신).
2. **설계 입력 핀 빈칸**: `evaluate.R:39` · `:1476-1489` 가 `onset_state_classify.json` 을 읽는데 design_inputs.files(`:1928-`)에 없다 → `p5_load_onset` 이 언제나 '분류 핀 없음' 꼬리표를 단다(판본이 바뀌어도 구별 못 함). `state_turn_classify.md` 는 final_selection_rule 근거 문장 속 md5 만 있고 design_inputs 에 없다 · `crisis_type_asof.{R,md,json}`(rules.pause_report · §0b 26 의 근거)은 git 미추적(`??`)이고 핀 · 커밋 대상(`register.R:445` `.commit_paths`) 밖이다. → 세 파일을 design_inputs.files 와 커밋 대상에 넣는다.
3. **같은 추첨 선택 꼬리표의 E3**: `evaluate.R:1439-1448` 은 E3(Q50 없음 = not_applicable)를 빼고 E2 만으로 꼬리표를 정한다(재현 R3 — E2 과반이면 꼬리표 없음). 규칙 문장 "과반 미만 **또는 미측정**"(`:829` · `:834`)은 E3 를 '미측정'으로 읽을 여지가 있다. rules.selection · conclusion_names 에 "같은 추첨 판독 = Q50 이 있는 구성(E2)만 · E3 = 해당 없음(꼬리표 판정에서 뺀다)"를 적는다.
4. **측정 중 GPU**: `lane_hold_wait.sh:2-6` 은 워밍 센티널이 쓰이는 순간(성공 · 실패 무관) 레인을 켠다 → 측정 때 레인 GPU 작업이 돌 수 있다. `measure.sh` 는 GPU 게이트 없이 폴백 분기(`:120-127` — RX0 · RX0S 가 '(trained 0, …)'를 못 보이면 V1 단독 = 분위 재학습)로 간다 — P2R03 10-18 VRAM 폴백의 재발 경로(수치는 같고 시간만 — 그래서 권고). 폴백 앞에 `precheck.R --gpu-gate`(끄지 않고 대기)를 두거나 폴백 대신 측정 중단 → `--rewarm`.
5. **결론 범위 ↔ 결론 문장(`evaluate.R:1879-1884`)**: 결론 범위 5 "월 수평 전이 기록이 **약하면** 결론에 '수평 불일치'" — 기준이 없고 판정 경로도 없다(grep 0) → 사후 재량이다. 기존 기록으로 기준을 박는다(예: 거부 집합의 다음 보유월 하위 5분위 적중 `transfer.veto.bottom` ≤ 기저 `base_rate`(1/분위 수) = '수평 불일치' — 새 숫자 없음) 또는 'Q 판독(사람)'으로 명시한다. 결론 범위 11('V · S · Q50 · RX0 … 나란히 **결론 문장에**') · 14('RX0 대비 · Q50 대비 보유 겹침을 **결론 문장에**')도 실제로는 정지 보고 재료(`:1538-1544`)에만 있고 결론 문장은 변형 대 RX0 십분위뿐이다 — 문구를 '결론 기록(정지 보고 재료)'로 고치거나 E2 결론 문장에 붙인다.
6. **rules.diagnostics(`:832` ← `round_rules.R:148`) "… 크기 × β · 유동성 · 국면 월 기록 생략"** ↔ rules.record · 코드(`evaluate.R:2256` — Q50 · S1 · S2 는 유동성 십분위를 잰다 · C-069): "유동성 기록 = Q50 · S1 · S2 만"으로 맞춘다.
7. **다음 행동 A 문구**: rules.instrument_action(`:835` ← `round_rules.R:179`) · `evaluate.R:1830` "'원천 ① 이 학습 설정 반증' 기록" ↔ 결론 범위 4 "원천 ① 의 반증이 아니라" — hypothesis_index · 교훈 카드에서 '원천 ① 반증'으로 읽힐 문구다. "'이 학습 설정은 종목 왼꼬리를 배우지 못함(계기 실패 · 원천 ① 반증 아님)' 기록"으로.
8. **exposures**: (i) 구현 에이전트 C 가 두 번 실린다(`:116-117` = exposures_agents.json 짧은 판 · `:119-122` = `register.R:627` 긴 판) — 하나로. (ii) Q 가 계산한 `crisis_type_asof` 탐침(§0b 26 · 벤치 · 위생 유니버스 일수익 ≤ τ_D)이 Q 목록에 없다(crisis_type_classify 만 있다). (iii) expectations.note 가 인용한 판단 T1 R-20261018-004 · 철학 P2 R-20261018-002(P2R03 RX0 보는 창 수치)가 Q 목록에 없다. (iv) 하네스 자동 주입 MEMORY 색인(시험 창 · 전기간 요약 문장 포함) 노출이 구현 에이전트 A 에만 적혀 있다 — B · C · 설계 초안 에이전트 · 이 점검(§0)도 같다.
9. **DT 시험 증거 핀**: 사전등록 tests 는 08_Tests 3종 + 픽스처뿐이고, DT 엔진 시험(rule_smoke 139/139 · diff_check_mutation 17/17 · static_pit clean 9 — 내장 파이썬 추출본 포함 · py_e2e 29/29 · engine_dryrun 16/16 · rng_stream_facts)의 결과 JSON md5 는 없다(positive_control_rehearsal.json 만 핀). 사전 점검 `engine_checks.R:188-200` 의 정적 PIT 는 .R 파일만 보므로 내장 파이썬 검사의 증거는 시험 결과뿐이다(README §9 항목 13). `tests/_out/test_summary.json` 은 마지막 --fast 판이라 느린 시험의 기록이 아니다. → 결과 JSON 6종의 md5 · 통과 수를 tests(또는 engines)에 싣는다.

## 3. 선택

1. `precheck.R:1` · `measure.sh:5` 머리 주석 '사양 14' → 16.
2. LV 사양 2개(`specs/P2R05_E?_LV.json`)의 selection_accounting 은 P2R04 W2 원본 그대로다(control capacity_pair · diagnostic_of P2R04_E?_H2 · idea '용량 짝') — 사전등록 칸 control = lowvol_screen 과 다르다. 평가는 사양 회계를 읽지 않아 판정 무관이고 comparison.accounting '시행 회계 원본 그대로'와 맞지만, 칸 산출물 회계 기록이 오해를 부를 수 있어 결론 기록에 한 줄.
3. `evaluate.R:1130` `arrow::read_parquet(f)` 는 mmap 기본(Windows 오류 1224 — 이 점검의 재현에서도 걸렸다) · 엔진 `.dt_qread` 는 `mmap = FALSE`. 평가는 측정 뒤라 무해 — 대칭으로.
4. DESIGN 본문의 옛 문장(§5 ⑭ 'RX0 + tol 이상(C-028)' — 승계 규칙은 엄격 > 0 · 문턱 없음 · §4 '12칸' · §6 확률 · §5.1 'D^σ t > 2' · §10.8)이 설계 입력 핀으로 함께 얼린다 — 머리말에 "§0b · 사전등록과 다르면 §0b · 사전등록이 이긴다" 한 줄.
5. purpose · 결론 범위 13 에 "다음 행동 A · B 의 'P2 정지 판독'은 R7 판독 불가(⑮ 미달 등)여도 따로 서는 정지 경로" 한 줄 — 지금은 방어 성분 잡음만 정지 조건으로 읽힌다.
6. V1 ≠ Q50 대조가 Q50 칸 측정에 묶여 Q50 실패 = E2_V1 미시험 → R7 판정된 규칙 < 2 로 판독 불가가 된다(규칙대로 · 사전 고정). 예측표 재현(`p5_reproduce` Q50 상위 25)으로 같은 질문을 기록용으로 함께 남겨 두면 원인 판독이 빨라진다.

## 4. 확인한 것 (결함 없음)

**규칙 — 문장 = 코드**
- 승계 11키(remeasure · common_window · pins_at_evaluation · decisive · strength · non_inferiority · concentration · recovery · selection_attribution · test_window · state_unturned) = P2R04 사전등록 문장과 바이트 동일 · record · failure_semantics = P2R04 문장 + 덧붙임(접두 동일) · final_selection_rule 14 숫자 키 = P2R04 값 · 새 키 = tail_instrument 하나(파이썬 대조).
- 승계 판정 함수 62/72 = P2R04 evaluate.R 와 본문 동일(상수 이름만 정규화 · deparse 대조 — p2_crisis_majority · deep · fast · beta_plan · beta_scaled_copy · bull · beta_ratio · cycle · alpha · top_loss · recovery · selection_attr/decomp/rule · round_verdict · select · cell_verdict · defense_name · pin_mismatches · redact · visible_only · holdings_overlap). 다른 10 = ⑮ 13번째 조건(`p2_cell_pass`) · R7 두 성분(`p2_noise_reading`) · 칸 표 · 상수 이름 · 보는 창 유동성 패널 사전 계산 — 의도와 같다.
- ①~④ · ⑤⑥⑦⑨ · ⑫⑬ · ⑧ · ⑪ · ⑭ = P2R04 v3 그대로(엄격 부등호 · 과반 > 0.5 · 짝 ≥ 2 · k ≥ 1 = RX0 · 빠른 급락 21거래일 −20% + 1e-12 · 벤치 = RX0 산출물 일수익 · ⑭ 분해 엄격 > 0 · insufficient = 미측정 · ⑭ 미측정 = selection_unmeasured).
- tested ①~⑦ · pass 13조건(`:523-526`) · 판정 입력 유한(`:2180-2187` — ⑭ 는 목록 밖) · 라운드 판정 '판정 칸/변형 칸 4 · 판정어별 칸 수' · 진단 10칸 분모 밖 · 선택 = 검증 규칙 · S 증분 두 구성 평균 · 차 < 1e-12 → ③ + ④ 비율.
- ⑩: (a) 엔진 종류 · 경로 · 핀(operational_pins 같은 상대 경로) · 사양 구성 키(base_signal 밖 · `_note` 제외) · 셀 로그 팩터 적재 · 기저 적재 줄(md5 앞 12자 — `rf_base_cache.R:163` 파일 이름 형식과 같다) · W2 결합 줄(`rf_cell_engine.R:175` 형식) · 워밍 센티널(분위 칸만 · 측정에 묶인 사본 우선) (b) 템플릿 차분 rc 0(평가 때 다시 실행 · 분위 칸만) · months= 같음 (c) 판정 칸 무처치 = 미시험 · 진단 칸 = 계속 · V1 ≠ Q50(E2 · Q50 지문 일치 때만 · E3 해당 없음) (d) 교차율 · 횡단면 표준편차 기록. RX0S = RX0 엔진과 다른 파일 · 다른 md5 의 핀 된 평균 엔진 1개 · 워밍 · 템플릿 해당 없음. LV = P2R04 ⑩ 형식 + 혼합 몫 0.125 재도출(E2 base_weight 0.875 · 1팩터 / E3 0.5 · 4팩터 — 사양 파이썬 대조).
- ⑮: τ 0.1 · ref constant_tau · NW lag 3 · **t > 2 엄격**(재현 R4a) · 보는 창 신호일 < 2022-12-01(215개월) · RAW = Date ≤ τ_D 사본 · 라벨 = 엔진 표적 블록(`engine_template.R:408-413`)을 합성 격자에 돌린 값 = `p5_labels`(시가 있음 · 없음) · `.rank01` 은 엔진 파일에서 파싱 · 순위 = 그날 예측 종목 ∩ 유한 라벨(엔진 학습 표적의 순위 집합 = 그날 적격 MEM 행 — 예측 행 Xp 와 같은 집합) · RAWDATA Date = date32(시간대 문제 없음) · `load_rawdata` = parquet 그대로(`backtest_harness.R:166-176`) · NW = 정본 `.nw_t_mean`(`backtest_result_contract.R:545-557` · Bartlett · 정의만 파싱) · 미달 · 미측정 = 변형 4칸 untested_tail_instrument(판정 계산 기록 유지) · W2 = ⑮ 포함 13조건.
- V1 거부 = 그날 적격 집합 U_d 안 순위(동률 평균)/N ≤ 0.2(엔진 `.dt_veto` = 평가 `p5_veto` · 재현 R4b · 비유한 = N 밖).
- 진단 읽기: 중심 · 희석(① 등록 + 깊은 위기 기록) · 변동성 · 꼬리 고유(S · N · Q50 모두 no_win ∧ D^σ ∧ D^w ∧ D^H 모두 t > t_min · 하나라도 미측정 = NA — R4c) · 용량 4행 첫 일치 · 표 밖 · 진단 칸 없는 E3 = 해당 없음.
- 시드 띠: 위기별 |RX0S − RX0| · S 띠 · |변형 − 사본| < 띠 = 시드 미결 · 띠 없음 = 미측정 · R7 두 성분에 꼬리표 수(`:2513-2516`).
- 같은 추첨: k' = β_V/β_Q50(같은 `p2_beta_plan`) · Q50 × k' 현금 사본 · 깊은 위기 · 빠른 급락 · ⑤ Δ · ⑥ · ⑦(V − Q50 쌍 알파) · V–Q50 겹침 · 선택 꼬리표(E3 해석은 권고 3).
- 다음 행동 A ~ D: 첫 일치 · 맞는 줄 전부 기록 · ⑮ 미측정 = 해당 없음 · D^· 미측정 = B · C 판독 불가(재현 R5 — ⑮ 미달 ∧ ③ 통과 = A · 맞는 줄 A, D).
- R7: 등록 판독(tested ∧ ③ 측정 ∧ S 증분 유한) · 방어 성분(S 무관) · 판정된 규칙 < 2 = NA(⑮ 미달이면 둘 다 NA) · 빠진 규칙 · 이유.
- 정지 보고 재료 4요소 · 유동성 3분위 귀속(고점일 adv20_l1 = t−1 · 위생 멤버 HYG ∧ adv > 0 · 03 ret_gross 구간 합 대조 1e-10 · 개선 > 0 위기만 · 몫 > 과반 = '저유동 귀속' · 계산 불가 = '유동성 귀속 미측정' 의무 · 미시험 칸에도 의무 꼬리표).
- 결론 이름 `p5_conclusion`: '방어' = ③ ∧ ④ ∧ ⑤ 수준 ∧ ⑭ · '선택(특성)' = 크기 × β · '꼬리 학습 방어' = 방어 성립 ∧ 꼬리 고유 위기 ≥ 1 · '꼬리 회피 기계' 꼬리표 = 문장 그대로(⑥⑦⑨⑫⑬) · 미측정 = 보류 · ③ 미통과 Sharpe 상승 = 평시 변동성 축소 · 희석 몫 · 기준점 둘.
- 부록 A 기대 = V2 상승 β > S2 상승 β ∧ ⑥ 비율 V2 ≥ S2(`:1687-1695`).

**PIT**
- 엔진 표적: lab_i = 실현 인덱스(s+5) · 학습 집합 di ∈ [u−1004, u−5] ∧ y 유한(파이썬 `select` `:785-798`) · `max_lab > u_i` 면 예외(`:854-855`) · R 재단언(`:1052-1055` · 창 1,000 · u ≤ pred_i) — 원본과 바이트 동일(보호 범위).
- σ(`:304-313` · `:492-503`): 로그수익 창 [p−252, p−1] = 종가 t−1 까지 · 유효 ≥ 126 · 수정 종가 비율(소급 조정 상수배 불변) · `.G` 읽기만.
- s_hist(`:290-300` · `:618-631`): 자기 행 di ∈ [p−252, p−1] ∧ lab_i ≤ u ∧ y 유한 · 중앙값 − 10% 분위(type 7) · 엔진 검산(u 뒤 라벨을 세지 않는다).
- 순열: 신호일 안 · 종목코드 radix 순 · 달 순번 하위 시드(접두 안정) · 전역 난수 복원 · rule_smoke 단언(같은 시드 = 같은 순열 · 접두 안정 · 다른 주 시드 = 다름 · 지문이 이름을 가른다).
- 점수 = 그 신호일 예측 · σ · h 만 · 예측표에 실현 라벨 없음(engine_dryrun 단언) · R lead · 음수 shift · 파이썬 shift(−k) grep 0 · 정적 PIT clean 9(엔진 7 + RX0S + 추출 파이썬) · 검사기 양성 대조 2/2.
- 평가: RAWDATA · 예측표를 τ_D 에서 먼저 자름 · 유동성 t−1 · 보는 창 파일 쓰기 전 날짜 전수 검사(`:2569-2570`) · 사람 쪽 판 분리 · notify.R 은 evaluation_visible.json 만.
- 측정 축 위생 멤버십은 RAWDATA 자체 열(AdminStock · TradingHalt · UnfaithfulDisc · Close · Vol)로 계산된다(`measurement_axis.R:144-183`) → dnn_input 지문(RAWDATA stat)이 덮는다.

**R2 · 고정**
- 핀 130개(고유 파일 90) = 현재 파일 md5 전부 일치: 사양 16 · 운영 경로 50(DT 엔진 7 · RX0S · 템플릿 · 생성기 · 검사기 · 매니페스트 포함) · 평가 경로 11 · 리허설 스크립트 · 요약 · 설계 입력 5 · tests 4 · 행동 카드 사본 · 정적 PIT 검사기(044f3ff1) · 파이썬 판(3.12.10 · torch 2.12.1+cu126 · numpy 2.4.6 · pandas 2.3.3 · pyarrow 24.0.0) · R 4.5.2 · 패키지 4.
- rules_source md5 = round_rules.R · 리허설 evaluate · round_rules · rehearse md5 = 현 파일 · 실행 중 파일 불변 · 10단계 통과 · evaluate_consistency ok.
- evaluate.R 시작부(샤드 포함): 등록부 md5 · round_id · 행동 카드 사본 · `p2_pin_mismatches` · precheck ok · FS 키 · 칸 목록 · 칸 평가 캐시 산출물 = 현 측정 산출물 · 측정 연기 = 중단 · 묶음 판정 칸 시작 · 끝 지문 모두 같음 · 진단 칸 · Q50 지문.
- precheck: 사전등록 두 사본 git 추적 · 작업 트리 변경 없음 · 두 md5 같음 · 워밍 센티널(상태 ok · 사전등록 md5 · 엔진 7 + RX0S md5 = 핀 = 현재 · CODE_VERSION · 분위 · 재시드 캐시 전 달 · cuda · 양성 대조 · RX0 · 워밍 중 지문 불변 · 끝 지문 = 현재) · 러너 축 n_max · commission_bps.
- measure.sh: 칸 목록 = 사전등록 cells 집합 대조(16) · 묶음 E2 11 → E3 5 · 센티널 사본 results/warm_sentinel.json · 칸별 시작 · 끝 지문(equality · record).

**측정 기계 안전**
- 워밍 순서 = precheck --warm → 레인 스위치(켜짐 = --allow-lane-on 없으면 중단) → GPU 게이트(Type C 0 · 대기 · 끄지 않음) → CUDA → Q50 단독 → RX0S 단독 → RX0 단독 → finalize · GPU 잠금(mkdir 원자 · 죽은 주인 회수 · --rewarm = 잠금 유지) · 감시 = 경고 줄만.
- 워밍 데이터 = 셀 경로와 같은 함수 · 순서(load_rawdata → ma_inject_universe → setorder) · .RP_START_DATE 미전달(셀 엔진과 같음) · 셀 엔진이 기저 엔진에 넘기는 DT 의 추가 열(.TV 등 — `rf_cell_engine.R:90-92` · `:137`)은 엔진이 .REQ ∪ Open 만 골라 무관.
- 측정 순서 = 묶음마다 RX0 → RX0S 단독 → '(trained 0, …)' 증거 없으면 V1 단독 → 나머지 PAR 2 · 인프라 실패 1회 재측정 · 묶음 지문 불일치 = 배리어 → 워밍 재단정 → 묶음 1회 재측정.
- 실패 의미: 진단 칸 실패 = 그 읽기만 미측정 · Q50 실패 = E2_V1 미시험(규칙대로) · RX0S 실패 = 시드 띠 미측정 꼬리표 · 예측표 판본 불일치 = 평가 중단 + evaluation_halt.json + 센티널 eval_halted.

**엔진 처치 범위**
- template_diff_check rc 0(이 점검에서 다시 실행): 구역 26개 밖 원본과 바이트 동일 · 보호 범위 대체 0 · 생성 7 = 템플릿 + 규칙 줄 1줄(67행) · RX0S = 원본 + 3줄(48 · 72 · 101) · 매니페스트 md5 일치 · 차분 검사기 양방향 17/17.
- 보호 범위 안 삽입 2곳 = 읽기 전용: sigma252(`engine_template.R:492-503` — `.G` 를 j 식으로 읽어 새 표 `.DT_SIG` 만 만든다 · `:=` 없음) · py_cache_key(`:806-808` — 키 명세 문자열 접미만 · 평균 표적 키와 충돌 불가 · 데이터 무접촉).
- 대체 구역의 원본 행(470 · 482 · 492 · 509 · 570-589 · 605-617 · 620-632 · 651-655 · 695 · 721 · 731-732 · 776-777 · 783-785)에 PIT 단언 없음 — 원본 600-601 · 726-729 의 단언은 보호 범위 · 템플릿에 그대로.
- 양성 대조: 정답 3시드 통과 · 뮤턴트 4종 × 3시드 전부 실패 — 부호 반전 · 머리 뒤바뀜은 **날 머리**(spearman −0.3 대 · 적중 0.9/0.1)로만 잡히고 정렬 머리는 통과한다(날 머리 ∧ 정렬 머리 판정의 필요성 실증) · MSE 회귀 = 적중 0.5 대 · 폭 무학습 = q10 spearman ≤ 0.62 · positive_control_rehearsal.json 원천 md5 = pc_mutation_results.json(6ee63345) · template_md5 = 현 템플릿. RX0S rev3 양성 대조(새 시드 20261026) CPU 통과.

**시행 회계 · 선택**
- 변형 4칸만 n_family 264 = 앞선 사전등록 최댓값 260(P2R04) + 4 — 재도출(P0R01 216 · P3R01 226 · P3R02 228 · P3R03 238 · P2R03 252 · P2R04 260) · 사양 회계 일치 · RX0 · 재시드 · 진단 · 비교 기준 = NA · lineage 에 RX_P2R05 추가.
- 최종 선택 = 보는 창 S · 진단 · 비교 기준 칸 선택 밖 · 같은 추첨 꼬리표 = 선택 불변.

**문장 최신성(맞은 곳)**
- V1 = Q50(같은 추첨 중앙값) 순위 보존형(vocabulary · purpose · 결론 범위 14) · 시드 띠(결론 범위 8) · 희석 정정(결론 범위 9) · 합집합 결합 금지(결론 범위 6) · 위기 유형 이름 systemic / dispersed(기대 by_crisis_type — '전면 급락' 0건) · 확률(J-006) · 꼬리 증분 D^σ ∧ D^w ∧ D^H(진단 읽기 · 다음 행동) · CHARTER-GAPS-4 · 5 · 6 기본값 · 보류 C-046(LV).
- exposures: Q · 구현 에이전트 A · B · C · 설계 초안 에이전트 · Superfan T2 R-005 · P2 R-006 · T1 R-007 · P1 R-008 · P4 R-009 수록 · A · B · C '시험 창(2023~) 성과 수치 열람: 아니오' 진술(빈칸은 권고 8).
