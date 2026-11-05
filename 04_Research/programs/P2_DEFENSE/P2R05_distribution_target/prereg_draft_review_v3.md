# P2R05 사전등록 초안 격리 교차 점검 v3

- 점검자: 격리 교차 점검(서브에이전트 · 이 라운드 설계 · 구현 비참여 · 측정 결과 없음 · v1 · v2 점검과 같은 정보 경계) · 2026-11-06
- 대상(md5 앞 8자리): `prereg_draft.json`(draft_version 3 · dac42e4a) · `prereg_draft_reviewed_v2.json`(da4a828e — v2 점검 대상과 같음) · `evaluate.R`(0f7402d9) · `round_rules.R`(976192ac) · `evaluate_fixture.R`(e91941d6) · `register.R`(01a48689 · DRAFT_VERSION 3) · `measure.sh`(c73e0310) · `rehearse.R`(94fa1cbc) · `rehearsal/summary.json`(5c49e27f) · `notify.R`(527789a9) · `notify_done.sh`(462aa934) · `DESIGN_draft.md`(280a9c9d) · 대조용(v2 뒤 안 바뀜): `precheck.R`(9d274c2d) · `engine_checks.R`(de609a7a) · `warm_engine.R`(0397072c) · `warm_cache.sh`(ace36eb9) · `measure_now.sh`(43de9b61) · `measure_now_vram.sh`(2305f1fd) · `fingerprint.sh`(61ef8750) · `exposures_agents.json`(e032a9b4) · DT `engine_template.R`(e998c0af) · `template_diff_check.R`(85cb0070) · DT 시험 증거 tests_dt 9
- **판정: ok(등록 가능)** — v2 필수 두 건은 코드 줄 · 합성 재현으로 해소됐다. **(1)** 셀 로그 `[DT qpred] path=` 대조(`p5_qpred_log_check`)가 들어갔다. v2 가 든 세 경로(폴백 · 묶음 사이 다시 워밍 · 묶음 사이 데이터 갱신)는 예측표 이름이 바뀌면 모두 평가 중단이 되고(재현 Ba · Bb · Bc · Cb), 이름이 같으면(예측 동일) 통과한다(Bc'). 규칙 문장 · 실패 의미 · measure.sh:142 · 픽스처 N47 · 리허설 R10 이 한 정의다. **(2)** '꼬리 회피 기계' · 'β 비대칭 미달' 문장 넷(결론 범위 3 · rules.conclusion_names · DESIGN §10.3 · 변경 기록)이 코드와 한 정의다(재현 D1~D10). register.R:991-994 점검은 옛 문구를 넣은 사본에서 초안을 막고, 현 초안은 통과시킨다(pA0~pA2). v3 수정은 판정 경로를 건드리지 않았다(승계 함수 61/72 동일 · 다른 11 = v1 의 10 + v2 의 `p2_cell_verdict`). 판정 칸 수 · 판정어 첫 일치 · notify 어휘 · R7 두 성분 · 선택과의 맞물림에 회귀가 없다. 핀 124쌍 + md5 참조 42 = 현재 파일. 남은 것은 등록을 막지 않는 셋이다 — 새 평가 중단이 연 '다시 워밍 · 재개' 경로에 사전 고정된 복구가 없고(권고 1 · E3 는 코드상 늘 폴백 GPU 게이트를 지나 그 경로가 쉽게 열린다), v2 노출 고지가 빈 문장으로 실렸고(권고 2), v2 권고 4 가 기록 없이 남았다(권고 3). 셋 다 등록 전에만 고칠 수 있으나 판정 · 이름 · 판정 규칙 문장을 바꾸지 않는다.
- **건수: 필수 0 · 권고 3 · 선택 4**

## 0. 정보 경계 선언

- 연 것(v3 에서 새로 · 다시):
  - `prereg_draft.json` — 파이썬 판독: 최상위 46키 · conclusion_scope 16 · changes_after_review 28 · rules 31키 전문 · exposures 21 · comparison.reading · expectations.LV · purpose · reseed.note · philosophy_p1 · 핀 전부.
  - `prereg_draft_reviewed_v2.json` — v3 와 구조 차분만(바뀐 경로 39).
  - `prereg_draft_review_v2.md` · `prereg_draft_review_v1.md` 전문.
  - `evaluate.R`: 1-140 · 515-650 · 770-1000 · 1100-1260 · 1855-2045 · 2159-2218 · 2440-2774 · grep.
  - `round_rules.R`(grep) · `evaluate_fixture.R`(1-60 · 700-760 · 975-1048 · 1160-1242 · 실행).
  - `register.R`(239 · 458-468 · 500-702 · 960-1002 · grep).
  - `measure.sh` · `notify.R` · `notify_done.sh` 전문 · `rehearse.R`(205-356) · `rehearsal/summary.json`(단계 · 점검 · 상태).
  - `DESIGN_draft.md`(머리 · `git diff` 단어 차분 · §7.2 · §10) · `warm_engine.R`(40-200).
  - DT: `engine_template.R`(125-150 · 1090-1130) · `README.md`(grep · §9 항목 11 · §10).
  - 하네스(읽기만):
    - `round_kit.R` 1-60 · `measure_round_cell.R` · `rf_cell_worker.R` · `detached_env.sh`(grep)
    - `rf_cell_engine.R` 85-192 · grep · `rf_base_cache.R` 119-165
    - `run_paper_replication.R` 255-290 · 552-575 · `eval_parallel.sh` 머리 · `diagnosis_packet.R::dp_scan_dates`(57-76)
  - `specs/` 16 의 base_signal · E2/E3 RX0 사양 키 차분.
  - P2R04 `evaluate.R` — 함수 본문 대조만(deparse · 본문을 화면에 띄우지 않음).
  - 목록 · 머리만 본 것:
    - DT `_work/` — 없음(워밍 전)
    - `gpu_handover.py` 머리 3줄 — 아래 실행 전후 대조에서 md5 가 바뀌어 확인
- **안 연 것**:
  - P2R03 · P2R04 · P2R05 `results/` 전부와 `stage_artifacts/replication/`
  - authoritative_remeasure.json · behavior_card(칸 산출) · ROUND_REPORT · failure_map · visual/
  - `rehearsal_run.log` · `register_draft*.log` · `rehearsal/out/`(최상위 로그는 전후 대조용 md5 만 계산 · 내용 미열람)
  - Superfan 리뷰 · 판단 원장 본문 · 예측 · 진단 parquet · 스크래치패드의 조정자 파일
  - 시험 창 · 전기간 **전략 성과** 수치를 연 것 없음.
- 노출 고지: 하네스가 자동 주입한 MEMORY 색인 문장(지수 급락 · DNN 계열 낙폭 · 앞 라운드 반증 요약처럼 시험 창 · 전기간 요약 문장 포함)이 컨텍스트에 있었다 — 점검 판정 · 권고에 쓰지 않았다. 사전등록 · DESIGN 이 싣는 보는 창 수치(§0b · §6 · expectations.note)는 읽었다.
- 실행한 것:
  - `Rscript evaluate_fixture.R`(R 임시 폴더에만 씀) → **99/0 · 뮤테이션 79/79 · 14초**.
  - `Rscript template_diff_check.R --json <스크래치 파일>` → **rc 0**.
  - evaluate.R 함수를 격리 환경에 적재한 재현(합성 입력 · 쓰기 = 스크래치패드만 · 끝나고 삭제):
    - A(register.R 점검 줄 그대로) · B(실제 칸 16 · 실제 사양 · 합성 셀 로그) · C(센티널 → 묶음 → 대조)
    - D(판정어 · 결론 이름) · E(notify 사전 — notify.R 는 실행하지 않고 `CW` 식만 떼어 평가) · F(사유 문자열)
  - P2R04 ↔ P2R05 함수 본문 대조(deparse).
  - 파이썬(읽기만 · `-I`) — 핀 · md5 참조 · 초안 구조 차분.
  - 환경 판 대조 — R · 패키지 4 · venv 파이썬(torch 는 import 만 · GPU 연산 없음).
- 실행 전후 대조:
  - 라운드 · DT 폴더 `git status --porcelain` 27줄이 같다.
  - `rehearsal/summary.json`(5c49e27f) · `prereg_draft.json`(dac42e4a) · DT `tests/_out/*.json` 9 의 md5 가 같다.
  - 라운드 폴더 최상위 파일 전체 md5 에서 **`gpu_handover.py` 하나만** 08:22:10 에 바뀌었다(1543… → df4b…).
    - 머리에 '★폐기(쓰지 말 것 · 2026-11-06 표기)' 줄이 더해졌다.
    - 이 점검의 쓰기가 아니다 — 내 실행은 스크래치에만 썼다. 동시 세션의 수정으로 보인다.
    - 핀 밖 · 측정 · 평가 경로 밖이다.
  - **DT `run_all_tests.R` · `rehearse.R` · `register.R` 는 돌리지 않았다.**
  - 측정 · 워밍 · GPU · 등록 · 커밋 · 대상 파일 수정 없음 — 쓰기 = 이 파일 하나.

## 1. 필수 (등록 전 수정)

없음. v2 필수 1 · 2 는 해소됐다(§4).

## 2. 권고

1. **새 평가 중단 뒤 복구가 사전 고정돼 있지 않다 — '다시 워밍 · 재개' 경로가 막다른 길이 된다**(measure.sh · rules.remeasure · failure_semantics)
   - 사실(재현 Bb · Cb):
     - 묶음 사이 다시 워밍(`measure.sh:157-167` — E3 지문 불일치 → `--rewarm` → `results/warm_sentinel.json` 새 판 → E3 만 다시)을 거치면 E2 분위 칸의 예측표 줄은 옛 이름으로 남는다.
     - 그래서 `evaluate.R:1225` 에서 평가가 멈춘다. 의도대로다(v2 권장 = 중단).
     - 그런데 measure.sh 는 ok 칸을 건너뛴다(`:108`). 같은 명령을 다시 돌려도 E2 는 다시 재지 않고, 평가는 또 멈춘다.
   - 재개 안내도 같은 길로 보낸다.
     - `measure.sh:137` · `notify.R:89-90` "같은 명령으로 다시(ok 칸은 건너뛴다 · 워밍이 낡았으면 --rewarm)"
     - `measure.sh:142` "(멈추면 원인 확인 뒤 다시 워밍)" — 다시 워밍만으로는 ok 칸을 다시 재지 않는다.
     - 일일 갱신을 넘겨 재개하면 달 키 · 신호일 목록 · σ 표 중 하나만 바뀌어도 예측표 이름이 바뀐다(`engine_template.R:1102-1108`). 그러면 E2 = 옛 판 · E3 = 새 판이 되어 평가가 반드시 멈춘다.
   - 그 상태를 만드는 흔한 계기(코드 판독 추론 · 실측 아님):
     - E3 의 RX0 · RX0S 는 E2 와 같은 기저 캐시 키를 쓴다.
       - 키 = 엔진 md5 · 데이터 도장 · 메모리 지문 · 행 수 · 시작일(`rf_base_cache.R:145-164`) — 구성 키가 없다.
       - 지문은 '.' 열을 빼고(`:121`), 기저 적재가 팩터 적재보다 먼저다(`rf_cell_engine.R:113-192` 대 `:265-`).
       - 두 사양의 universe · start_date · measurement_axis 가 같다.
     - 그래서 E3 RX0 · RX0S 는 적중하고 DNN 완료 줄이 없다(`measure.sh:117`) → ev = 0 → E3 는 늘 폴백 분기의 GPU 게이트(`:134-139`)를 지난다.
     - 레인이 GPU 를 2시간 넘게 쓰면 gpu_busy(rc 9)로 E2 만 끝난 채 멈춘다. E3 V1 도 기저 캐시 적중이라 학습할 일이 없는데도 기다린다.
   - 왜 권고(필수 아님):
     - 판정은 안전하다 — 어긋난 판은 평가 중단으로만 끝나고 거짓 판정이 나오지 않는다.
     - 복구(그 묶음 결과 삭제 → 현 워밍으로 재측정)는 기계적으로 하나로 정해진다.
     - 다만 rules.remeasure 는 'ok ≠ true' 칸 재측정만 사전 고정했다. ok 칸 삭제 · 재측정은 사전등록 밖 수작업이다.
     - 칸 평가 샤드는 종합 판정 전에 칸별 보는 창 산출물을 이미 쓴다(`eval_parallel.sh:22` → `evaluate.R:2492`). 복구를 고정하지 않으면 '다시 잴지 말지'가 그 산출물 뒤의 판단이 된다.
     - measure.sh 는 평가 경로 핀이라 등록 전에만 고칠 수 있다.
   - 고칠 방법((a) 또는 (b) 하나면 막다른 길은 닫힌다):
     - (a) 측정 사전 점검(측정 시작 · 묶음 재측정 직전 · 결정론 · GPU 0):
       - 이미 ok 인 분위 칸의 셀 로그 예측표 줄(적중이면 연쇄)을 이번에 묶을 센티널 qpred.path 와 대조한다.
       - 같은 함수(`p5_qpred_log_check`)를 부르면 규칙이 한 출처로 남는다.
       - 다르면 측정하지 않고 멈춘다(센티널 예: `qpred_stale_ok_cells` · 묶음 목록).
     - (b) 복구를 사전 고정 문장으로 — rules.failure_semantics · remeasure 에:
       - "셀 로그 예측표 ≠ 묶인 판(평가 중단 · 사전 점검 중단) → (필요하면) 다시 워밍 → 그 판으로 재지 않은 분위 칸이 있는 묶음의 전 칸 결과 삭제 → 같은 사양 재측정(라운드 포기 아님)".
     - (c) regroup 에서 다시 워밍해 센티널 qpred 가 바뀌면 앞 묶음도 같은 사유로 다시 잰다(`:166` 의 삭제 범위).
     - (d) E3 증거 승계: E3 RX0 · RX0S 가 적중한 캐시를 같은 측정의 E2 RX0 · RX0S 가 '(trained 0, …)'로 실행했으면 ev = 1 로 둔다.
       - evaluate.R 연쇄 대조와 같은 논리다.
       - 쓸데없는 게이트 대기 · gpu_busy 를 없앤다.
     - (e) (v2 필수 1 고칠 방법의 선택 절 · 미반영) 폴백 V1 단독이 '(trained ≥ 1)'이면 V1 로그 예측표 경로를 센티널과 바로 대조해, 다르면 그 자리에서 멈춘다.
     - 핀이 바뀌므로 픽스처 · 리허설 · 초안을 다시 돈다.
2. **v2 노출 고지가 빈 문장으로 실렸다 — 추출기가 침묵 실패한다**(`register.R::.review_exposures`)
   - `exposures[19].what` = "격리 교차 점검 v2 노출 고지(…/prereg_draft_review_v2.md §0 원문): " — 콜론 뒤가 비었다(`prereg_draft.json:139`).
   - 원인:
     - `register.R:464-466` 은 '- 노출 고지' 줄 하나에서 첫 콜론 뒤만 옮긴다.
     - v2 리뷰 §0 은 "- 노출 고지(v1 과 같음):" 아래 하위 줄 셋에 본문을 둔다(v2 문서 36-39행) → 빈 문자열이 된다.
     - 대체 표식은 '줄 없음'만 다룬다(`:467`). '줄은 있으나 빈 본문'은 그대로 통과한다.
     - 그래서 변경 기록에는 v2 선택 5 를 반영한 것처럼 보이지만, 실린 내용이 없다.
   - 덧붙여 마지막 점검(이 v3)의 노출 고지는 구조상 등록본 exposures 에 실리지 않는다 — 초안이 점검 전에 쓰인다.
     - `--register` 는 reviewed_drafts 에 리뷰 경로만 싣고 md5 는 싣지 않는다(`:553-554`).
   - 왜 권고:
     - 등록 문장이지만 판정 · 이름과 무관하다.
     - v2 본문은 v1 과 같은 취지이고, 파일은 file_md5 로 묶였다.
     - 등록 뒤에는 고칠 수 없다.
   - 고칠 방법:
     - 본문 = 그 줄 + 다음 최상위 '- ' 전까지의 하위 줄로 읽는다.
     - 빈 본문은 '줄 없음'과 같은 표식으로 둔다(또는 초안 거부).
     - `--register` 때 reviewed_drafts 에 리뷰 md5 를 싣고, 마지막 리뷰의 노출 고지도 덧붙인다.
     - 이 문서 §0 노출 고지는 현 추출기로도 읽히도록 한 줄로 썼다.
3. **(v2 권고 4 의 나머지) DT 시험 증거 핀 = 시각이 찍힌 시험 출력 — 미반영 · 변경 기록에 사유 없음**
   - tests_dt 9 핀은 v2 때와 같은 파일 · md5 다(이 점검은 다시 돌리지 않았고, 전후 md5 가 같다).
   - 그러나 v2 가 든 고칠 길 셋 중 어느 것도 들어가지 않았다. REVIEW_CHANGES_Q2 에 미반영 사유도 없다.
   - DT `README.md` §10(`:168-169`)은 오히려 `run_all_tests.R`(--fast 포함)를 실행법으로 적는다.
     - 따르면 rule_smoke · diff_check_mutation · static_pit 핀이 바뀐다.
     - 그러면 `--register` 와 precheck(워밍 · 측정)가 닫힌다.
     - 등록 전에는 DT 폴더가 git 미추적이라 복원할 원본이 없다.
   - 고칠 방법(v2 와 같음): 라운드 폴더 사본 핀 · 통과 필드만 대조 · 최소한 README §10 · 사전등록 operational_memo 에 '등록 · 측정 전 DT 시험 재실행 금지'.

## 3. 선택

1. `p5_qpred_log_check` 가장자리 이름 둘:
   - (i) 실행 줄은 있는데 예측표 줄이 없는 칸은 '대조 불가' 꼬리표뿐이다.
     - 재현 Bf: 예측표 줄 형식이 어긋나면(앞 공백) 분위 칸 10/10 이 대조 불가가 되고 평가는 계속된다. 계기 사망이 꼬리표로만 보인다.
     - 정상 경로에서는 닿지 않는다고 판단한다. 엔진의 cat 과 기저 적재 줄이 같은 stdout 으로 셀 로그에 가기 때문이다(`rf_cell_engine.R:130-138` · `run_paper_replication.R:563` · `round_kit.R:29`). 기저 적재 줄이 없으면 ⑩(a)로 미시험이 된다.
     - 엔진은 그 줄을 무조건 찍는다(`engine_template.R:1126`). 그래서 '실행 ∧ 줄 없음 = 평가 중단'으로 닫아도 비용이 없다.
   - (ii) 빈 로그(측정 실패 잔재)는 'unverifiable' + 사유 '기저 캐시 적중'으로 센다(재현 Be).
     - 적재 줄도 없는 칸은 'no_log'처럼 미측정으로 분리해야 '대조 불가 n칸' 수가 실제를 센다.
2. register.R:991-994 옛 문구 점검은 문구 하나 · 두 곳의 정확 일치다.
   - 공백 하나 다른 변형(pA3)은 통과한다.
   - 옛 괄호 "'방어' 이름 조건"(pA4)도 통과한다 — 다만 round_rules.R 쪽은 픽스처 N31b 가 막는다.
   - purpose 등 다른 절(pA5)도 통과한다.
   - 등록 전 보조선이라면 충분하다. 넓히려면 옛 문구 목록 + 공백 정규화.
3. notify.R(판정 무관):
   - (i) 평가 센티널 `eval_halted` 도 일반 '평가 실패' 문구로 나간다(`:93-96`). evaluation_halt.json 사유(셀 로그 예측표 ≠ 묶인 판 등)와 복구 안내가 없다.
   - (ii) `tl()`(`:107-110`)은 `x$tail_instrument` · `x$rules$tail_instrument` 를 읽는다. 그런데 칸 객체는 `tail_gate` 를 싣는다(`evaluate.R:2449`). 그래서 판정 완료 알림의 ⑮ NW t 가 늘 빈다.
4. 고정 문서의 옛 문장(설계 입력 · tests_dt 핀으로 함께 얼린다):
   - DESIGN 머리 상태 줄(`:4` '초안 v0 · 구현 · 학습 · 측정 · 등록 · 커밋 없음')
   - DESIGN §0b 14 의 "§3.1 … 구현 에이전트가 코드로 확인해 사실대로 고친다"(`:36`) — 이미 고쳤는데 대체 표시가 없다.
   - DT README §9 항목 11(`:154` "평가는 같은 이름의 파일 또는 첫 실행 로그를 쓴다") — 지금 = 묶인 판 1개 + 셀 로그 대조.
   - 머리말의 '사전등록 문장이 이긴다'가 덮는다. 다시 초안을 쓸 일이 생기면 함께 표시한다.

v2 선택 1 · 2 · 3 은 반영되지 않았다. 선택 1 재현 D11: ⑩ 만 거짓 → '결정 미달'(`evaluate.R:550`) — 판정 경로에서는 ⑩ 미달이 먼저 미시험이 되어 닿지 않는다. 선택이라 판정과 무관하다.

## 4. 확인한 것 (결함 없음)

**v2 필수 1 — 해소(코드 · 문장 · 재현)**
- 코드 `evaluate.R:1209-1251` `p5_qpred_log_check`:
  - 대상 = 사양 base_signal 이 DT 분위 엔진인 칸 · 재시드 짝 제외(`:1213-1216`).
    - 실제 칸 16 · 실제 사양(절대 경로 · 역슬래시 판 섞임)으로 돌리면 대상 10 = E2 V1 · V2 · Q50 · N1 · N2 · S1 · S2 · W2 · E3 V1 · V2.
    - RX0 · RX0S · LV 는 밖이다(재현 B0 — RX0S 에 일부러 넣은 다른 판 줄도 무시).
  - 줄이 있으면: 정규화 경로(`:1204-1208` — 역슬래시 · 대소문자 · '.' · '..' · 루트 접두) ≠ 묶인 판 = `p5_halt`(`:1225`) · 그 파일 md5 ≠ = `p5_halt`(`:1227`).
  - 줄이 없으면: 그 칸 기저 적재 줄의 캐시 파일을, 예측표 줄이 묶인 판인 다른 칸이 '실행'했으면 연쇄 · 아니면 대조 불가(`:1237-1242`). 셀 로그 없음 = no_log(`:1233`).
  - 결론 꼬리표: V 칸 '대조 불가' → '⑮ 예측표 셀 로그 대조 불가…'(`:1986`).
  - 판정(tested · pass · 판정어 · R7 · 선택)에는 쓰지 않는다 — qpred_log 사용처 = `:1986` · `:2597-2599` · 보는 창 파일뿐.
- 문장: rules.tail_instrument · failure_semantics · conclusion_names 꼬리표 · measure.sh:142 · 픽스처 N47(`:1009-1047` · 뮤턴트 8 `:1171-1187`) · 리허설 R10(`rehearse.R:304-334` · 요약 R10 8점검 통과) = 같은 정의.
- 재현:

  | 재현 | 상황 | 결과 |
  |---|---|---|
  | B0 | 정상 — E2 분위 칸 실행 · W2 · E3 적중 · 셀 줄 = 역슬래시 · 대문자 절대 경로 | 같음 7 · 연쇄 3 · 대조 불가 0 |
  | Ba | (a) 폴백 — 셀 판 = 새 지문 이름 | 평가 중단(E2_V1) |
  | Bb | (b) 묶음 사이 다시 워밍 — 묶인 판 = 새 워밍 · E2 = 옛 판 | 평가 중단(E2_V1) |
  | Bc | (c) 묶음 사이 데이터 갱신 — E3 재학습 → 새 이름 | 평가 중단(E3_V1) |
  | Bc' | (c) 인데 이름이 같다(달 키 불변 = 예측 동일) | 통과 · 출처 없는 적중 1칸 = 꼬리표 |
  | Bd | E3 가 이번 측정에서 아무도 실행하지 않은 캐시에 적중 | 꼬리표 2칸(⑮ 판정 유지 — 규칙대로) |
  | Bg · Bh | 연쇄 출처 칸이 다른 판 · 한 칸 두 줄 중 하나가 다름 | 평가 중단 |
  | C0 · Cb · Cm · Cu | 센티널 → `p5_warm_resolve` → `p5_qpred_bound` → 대조(스크래치 예측표 실파일 · md5) | ok · 중단 · md5 중단 · 미묶임(not_applicable → ⑮ 미측정) |

- 남은 경로(Bd)는 규칙대로 꼬리표다. 정상 운영에서는 닿기 어렵다.
  - 기저 캐시 키에 RAWDATA 파일 도장이 들어간다(`rf_base_cache.R:147-159`). 데이터가 바뀌면 옛 캐시가 적중하지 않는다.
  - 워밍은 기저 캐시를 시드하지 않는다. `warm_engine.R:67-68` 은 엔진을 sys.source 하고, 기저 캐시 쓰기는 `rf_cell_engine.R:113-153` 뿐이다(`engine_template.R` 에 base_v2 없음).
  - 닿는 현실 경로는 인프라 실패 재측정(기저 캐시 저장 뒤 실패 → 다시 적중)뿐이고, 그때도 같은 데이터 · 같은 판이다.
- 경로 형식: 셀 워커가 CLAUDE_PROJECT_DIR = QM_ROOT = ROOT 로 둔다(`rf_cell_worker.R:19-20` · `detached_env.sh:6`). 그래서 엔진 `.ROOT`(`engine_template.R:131-146`) 아래 절대 경로가 워밍의 저장소 상대 경로(`warm_engine.R:94`)와 같은 정규형이 된다.

**v2 필수 2 — 해소**
- 문장 넷 = 코드: 결론 범위 3 · rules.conclusion_names · DESIGN §10.3(`:651-656`) · changes_after_review[9].
- 재현(evaluate.R 함수 그대로):

  | 재현 | 경우 | 통과 · 판정어 · 결론 기본 이름 · 기계 꼬리표 |
  |---|---|---|
  | D1 | ⑤ 수준만 미달 | 통과 · 노출(β) 방어(⑤ 수준 역행) · 없음 |
  | D2 | ⑤ Δ 만 미달 | β 비대칭 미달 · 선택(특성) 방어(이름 유지) · 없음 |
  | D3 | ⑤ 수준 ∧ ⑥ | β 비대칭 미달 · 노출(β) 방어(⑤ 수준 역행) · 없음 |
  | D4 | ⑤ Δ ∧ ⑥ | β 비대칭 미달 · 선택(특성) 방어 · 없음 |
  | D5 | ⑥ 만 | 꼬리 회피 기계 · 있음 |
  | D6 | ① ∧ ⑥ | 결정 미달 · 없음 |
  | D7 | ⑮ ∧ ⑥ | 미시험(계기) · 없음 |
  | D8 | ③ ∧ ⑥ | 노출 방어 · 방어 이름 없음 |
  | D9 | ① 미달 · ③④ 통과 · ⑭ 미측정 | ⑭ 미측정(결정 미달보다 먼저 — 문장 순서대로) |
  | D10 | ⑤ 수준 ∧ ⑭ 미달 | 크기 · 노출 방어(β 비대칭 미달보다 먼저) |

- register.R:991-994 점검(소스 줄을 그대로 떼어 평가):
  - 현 초안 → 통과(pA0).
  - 결론 범위 3 에 옛 문구 → 정지(pA1). conclusion_names 에 옛 문구 → 정지(pA2).
  - 쓰기(`:995`) 앞에 있다. 범위 밖 변형은 선택 2.
- 옛 문구 잔여(초안 전 문자열 grep):
  - '방어 이름 조건' · '방어 이름 없음' · '⑤ 만' · '약하면' · '복리 미달' · '상태 정의 미측정' · '엔진 보존형' · '꼭대기'는 변경 기록의 옛 문장 인용 · '구 이름' 표기 안에만 있다.
  - '③ · ④ · ⑭ 를 넘었으나' · 'tol 이상' · '전면 급락' · '다른 학습 추첨' · '설정 반증' · 'md5 로 대조'는 0건이다.

**v2 권고 · 선택 반영 상태**
- 권고 1 — 반영:
  - (a) 결론 범위 5 = 기준 문장.
  - (b) 결론 범위 10 출처 = state_turn_classify.md.
  - (c) evaluate.R 사유 = '시작 시점 분류'(재현 F · 픽스처 N31b 가 '꼭대기 시작' 0 을 단정).
  - (d) comparison.reading · expectations.LV = 정본 첫 일치 · 'tol 넘게'.
- 권고 2 — 반영: DESIGN 머리말 1줄 · §0b 4 · 7(두 줄) · 8 · 9 · 11 · 15 · 18 · 19 대체 표시 · §10.3 재작성 · §10.5 · §10.8(git diff).
- 권고 3 — 반영: rules.diagnostics_reading · conclusion_names 의 첫 일치 4단 = `p5_read_lowvol`(`:1868-1890`) 순서.
- 권고 5 — 반영:
  - `measure.sh:102-104` · `:163-165` cp 실패 = rc 11 · 센티널 sentinel_copy_failed(stage=start | regroup).
  - `notify_done.sh:16` · `notify.R:77-92` 가 그 사유를 처리한다.
- 권고 6 — 반영: `rehearse.R` R4(`:217-240` — 합성 센티널 → `p5_warm_resolve` → `p5_qpred_bound` → `p5_tail_block` · 미묶임 · md5 중단) · R10. 요약 11단계 통과 · 실행 중 파일 불변.
- 선택 4 — 반영: notify.R `CW` 11 = `P2R05_VERDICT_NAMES` 글자 같음 11/11(재현 E · 별칭 4 는 사전 밖).
- 선택 5 — 들어갔으나 본문이 비었다(권고 2).
- 권고 4 · 선택 1 · 2 · 3 — 미반영(권고 3 · §3 끝).

**회귀 점검(v2 → v3)**
- 초안 구조 차분(보존본 v2 대 v3 · 39 경로):
  - 바뀐 곳: changes_after_review[9] · comparison.reading · 결론 범위 2 · 3 · 5 · 6 · 10 · expectations.LV · rules 4키(conclusion_names · diagnostics_reading · failure_semantics · tail_instrument) · exposures(v2 항목 추가) · 핀(평가 경로 4 · 설계 1 · 리허설) · 판 표식.
  - 그대로: 칸 · 사양 · final_selection_rule · 나머지 rules 27키 · operational_pins 50 · tests_dt 9 · engines.
- 승계 판정 함수: P2R04 evaluate.R 와 공통 72 중 61 이 본문 동일하다(deparse · 상수 이름 정규화).
  - 다른 11 = v1 의 10(⑮ 13번째 조건 · R7 두 성분 · 칸 표 등) + v2 의 `p2_cell_verdict`.
  - 핵심 19(위기 과반 · 깊은 위기 · 빠른 급락 · β 짝 · 강세 · β 비 Δ · 집중 · ⑭ · 라운드 판정 · 선택 · 결론 기본 이름 · 판정어별 칸 수 …)는 동일하다.
- 판정 칸 수 · 첫 일치 · notify 어휘 · R7 · 선택:
  - 새 대조는 qpred_log(기록 · 꼬리표)만 더한다. tested · pass · verdict · R7 · 선택을 바꾸지 않는다.
  - `P2R05_VERDICTS` 순서와 `p2_verdict_counts` 출력 형식이 그대로다(재현 E).
  - notify `CW` = 판정 구현 글자.
- 보는 창 파일: 새 필드 qpred_cell_logs 에는 날짜가 없다(경로 · md5 · 16진 캐시 이름). `dp_scan_dates` 는 하이픈 날짜만 찾는다(`diagnosis_packet.R:57-76`) → 거짓 정지 없음.
- 측정: 칸 목록 · 묶음 · 순서가 그대로다. 새 종료 코드 11 만 더해졌고, 잠금 해제(trap)는 유지된다.

**핀 · 시험**
- 핀: {path, md5} 124쌍(고유 104) + md5 참조 42 = 현재 파일.
  - 참조 42 = 엔진 md5 · 매니페스트 · 리허설 · evaluate_consistency · rules_source · 설계 문장 · exposures file_md5.
  - 범주: 평가 경로 11 · 리허설 2 · 사양 16 · DT 엔진(engines 18 · 운영 50 중 DT 9) · DT 시험 증거 9 · 설계 입력 10 · 행동 카드 사본 1 · tests 4 · reseed 2.
- 환경 = 초안: R 4.5.2 · data.table 1.17.8 · arrow 24.0.0 · bbdetection 1.0 · PerformanceAnalytics 2.0.8 · venv 파이썬 3.12.10 · torch 2.12.1+cu126 · numpy 2.4.6 · pandas 2.3.3 · pyarrow 24.0.0.
- 시험:
  - 픽스처 99/0 · 뮤테이션 79/79(14초) · template_diff_check rc 0.
  - 리허설 요약: 11단계 통과 · evaluate · round_rules · rehearse md5 = 현재 · 895초.
- 등록 절차 메모: `--register` 는 `prereg_draft_reviewed_v3.json`(= 이 점검 대상 dac42e4a 사본)과 고정 대상 커밋을 요구한다(`register.R:511-513` · `:549-550`).

**PIT**
- v3 변경은 보는 창 경로를 넓히지 않았다.
  - 새 RAWDATA 접근이 없다.
  - 셀 로그 대조는 경로 · md5 만 본다.
  - 예측표 적재는 v2 그대로다(묶인 판 1개 → 보는 창 판).
