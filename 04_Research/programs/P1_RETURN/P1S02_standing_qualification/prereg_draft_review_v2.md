# P1S02 사전등록 초안 격리 교차 점검 v2(변경분)

- 점검자: 격리 교차 점검(서브에이전트). 초안을 만든 세션과 맥락을 공유하지 않았다. 이 판의 설계 · 구현 · 리허설에 참여하지 않았고 측정 결과를 보지 않았다. 기술 점검만 했다(판단 · 철학 정렬은 다른 감독 몫 — 감독 도전이 옳은지는 판단하지 않았다). 점검 시각 2026-11-12 21:34~21:58 · HEAD 시작 · 끝 모두 `cabb70341`.
- 점검 종류: 변경분 점검. 기준 = 점검 v1 §3 + 감독 수용 변경(사양 `changes_after_review` · `changes_after_superfan` 두 블록 — 철학 P1 R-20261111-009 · 판단 T1/T4 R-20261111-010 · 011). T1 C-079 의 `standing_cfg.rejudge_prior_editions` true → false 는 수용 변경으로 본다.
- 대상(md5 앞 8자리)
  - 지금 판: `prereg_draft.json`(draft_version 2 · **b3f180ff**) · `prereg_draft.md`(811438ee) · `drafts.json`(4e743501 · v1 review = revise · v2 review = null) · `round_spec.json`(e336f653) · `specs/P1S02_E2_C0.json`(687d6517) · `specs/P1S02_E3_RX0.json`(3a085178) · `standing_rules.md`(3c0213bb) · `DESIGN.md`(298a45e9) · `behavior_card_cfg_at_prereg.json`(6a2a1d21) · `tick_hold`(517198b1) · `tools/`(init_p1s02.R 17ecb78a · prejudge_check.R 55830c22 · p1s02_seed_watch.sh db4bd41b) · `rehearsal/`(rehearse.R f09247af · rehearsal_summary.json 1f9ce650 · REHEARSAL.md b337843f · 엔진 115790a4)
  - v1 대조본(저장소 밖 사본): 초안 de259d86 · md 71a0c8e9 · 사양 89b014c4 · 칸 사양 2 · `standing_rules.md` 3c0213bb
- **판정: ok** — 사양에서 바뀐 곳은 점검 v1 §3 목록과 감독 수용 변경뿐이고, 고정 블록은 바이트 동일이다. 핀 35 · 규칙 문서 md5 · 시드 칸 사양 md5 를 다시 도출했고 모두 맞는다. 리허설의 격리와 신선도 주입 범위도 코드로 확인했다. 등록을 막을 것은 없다.
  - 권고 3 은 모두 판정 밖(감시 셸 운영 · 뒤 판의 회계 약속 · 보고 경로)이다. R-1 은 감시 셸을 띄우기 전에 고친다(판 폴더 도구 — 사양 밖).
  - R-2 · R-3 은 결론 범위 문장의 실행 경로 문제다. DESIGN 에 뜻과 실행자를 적으면 사양을 고치지 않아도 된다. 사양 문장을 고치려면 초안 v3 + 변경분 점검이 필요하다.
- **건수: 필수 0 · 권고 3 · 선택 7**

## 0. 정보 경계 선언

- 연 것
  - 점검 v1(`prereg_draft_review_v1.md`) 전문 · 철학 P1 리뷰 `20261111_2344_P1_P1S02.md` 전문 · 판단 T1/T4 리뷰 `20261111_2349_T1_T4.md` 전문.
  - 판 폴더: 사양 · 초안 v2(json · md) · `drafts.json` · `DESIGN.md` · `standing_rules.md` · `tick_hold` · 도구 3 · `rehearsal/`(rehearse.R · REHEARSAL.md · rehearsal_summary.json · 엔진은 md5 만). v1 대조본 5개.
  - 코어 v3: `register.R`(1-200) · `standing.R`(17-65 · 186-316 · 335-366 · 457-537 · 572-1075 · 1119-1189) · `pins.R` 전문 · `rules.R`(80-95) · `cell_eval.R`(12-18) · `p4.R`(176-186) · `util.R`(42-45 · 227-237) · `driver.R`(100-138) · `round.sh`(1-60 · 100-150).
  - 운영(읽기): `rf_base_align.R` 전문 · `rf_base_cache.R`(머리 주석 · grep) · `standing_board_run.sh`(35-55) · `qv_lock.py`(머리 주석 · grep) · `rf_replication_slots.py`(status 경로) · `refresh_barrier.sh`(status 분기) · `measurement_axis.R`(grep) · 시드 엔진 `engine.R`(팩터 DB 호출 grep 개수만).
  - 기록(grep 줄만): P1S01 `DESIGN.md` · `BUILD_EDITION2.md` · `superfan_protocol.md` · `.gitignore`.
  - 리허설 산출(`rehearsal/out/**`) — 파일 목록 · 두 실행 원장의 사건 종류와 순서 · 측정 줄의 ok · fp_same · rc · artifacts 경로 · 판정 줄의 **필드 이름**(값 아님) · 사전등록 두 사본 md5 · `scan.json` 의 디렉터리 수 · 통과 수 · 사유 개수 · 리허설 판 사양 키 대조 · 리허설 판 초안의 핀 수.
  - 판단 원장: `rc_p1_check` 가 읽었다(출력 = ok · 리뷰 id · 파일 · 도전 수). 허용 id `J-20261112-003` 의 id · at · 필드 이름만.
- 안 연 것
  - `rehearsal/out` 의 `judge.log` · `report_dryrun.txt` · `status.txt` · `prejudge.log(.err)`. `results/**` 전부(eval · verdict · standing_visible · 진단 패킷 · `full/behavior_card.json` · 측정 결과 json). `sa` 원장 verdict 줄의 본문(필드 이름만 봤다).
  - `stage_artifacts/replication/**` · 모든 `authoritative_remeasure.json` · 산출 `behavior_card.json` · 2023 이후 성과 수치 · 등급 · 판 2 `results/`(비어 있음).
- 우연 열람: 없다. 요약 · REHEARSAL.md 에서는 개수 · 상태 문자열 · τ_D 이전 날짜만 보았다.
- 실행한 것
  - Rscript 임시 스크립트 3개(세션 스크래치 폴더)
    - 사양 · 초안 블록 대조.
    - 재도출: 핀 재계산 · 규칙 문서 · 시드 칸 사양 재생성(tempfile) · validate · 생성 함수 핀 · `rc_p1_check` · `rc_uncommitted` · md 재생성.
    - 리허설 산출 대조(사건 종류 · 개수).
  - `bash -n tools/p1s02_seed_watch.sh` · `P1S02_SELFTEST=1 bash tools/p1s02_seed_watch.sh`. 조정 지시 전에 끝났다. 임대 · 측정 없음 · 종료 0. 출력 = 레인 busy(live) · 임대 free · 가용 메모리 12 GB · 21:43.
  - git 은 읽기만 했다(status · ls-files · log · show --stat · diff --stat · check-ignore). PowerShell 은 프로세스 목록 읽기 한 번.
  - **시험**: 사양 `tests` 7종을 순차로 띄웠다가 조정 지시(도훈 "테스트 좀 그만하자")로 TaskStop 했다.
    - 1종(`test_round_core_v3.R`)이 종료 rc 0 으로 끝났고 2번째는 도중에 멈췄다.
    - 멈춘 뒤 남은 시험 프로세스 0 을 확인했다(명령줄에 `08_Tests` 가 든 프로세스 0건).
    - 그 출력은 판정 근거로 쓰지 않았다(§3 A6).
  - 돌리지 않은 것
    - `round.sh` 하위 명령 전부. `check` 도 돌리지 않고 같은 계산을 R 로 했다.
    - `standing-check` 는 코드상 `standing_rules.md` 를 다시 쓴다(standing.R:1169). 쓰기 경계 밖이라 돌리지 않고 생성 함수만 불렀다.
    - `prejudge_check.R` · `rehearse.R` · `init_p1s02.R`.
- 쓴 것: 이 파일 1개. 그 밖의 쓰기는 저장소 밖 스크래치(임시 스크립트 · 중단된 시험 출력)뿐이다.

## 1. 판정

**ok.** 점검 v1 항목은 다음처럼 처리됐다.

- F-1 해소: DESIGN §5-2 · BUILD:126 = 'tick_hold 커밋 → register'. `tick_hold` 는 있고 아직 미커밋이다 → 등록 조건 ⑦ 목록에 있다.
- F-2 해소: 핀 +3 · basis 제외 4개의 사유.
- R-1 · R-2 · R-3 · R-4 · R-6 은 사양에 반영됐다. R-5 는 도구에 반영됐다(기대값 인자 3).
- S-1 · S-2 · S-3 · S-4 반영. S-5 는 기록만이었고, 시드 칸 사양은 바이트 그대로다.
- S-6 은 판단 T1 C-086 으로 대체됐다. 다만 E3 에서 남았다(R-1).
- 감독 수용 변경은 철학 · 판단 문안 그대로 들어갔다. 코드와 맞지 않는 곳은 R-2 · R-3 두 문장의 실행 경로뿐이다.

## 2. 지적

### 필수

없음.

### 권고

**R-1. 감시 셸이 E2 직후 E3 용 임대를 쥔 채 시각 창을 다시 기다린다 — C-086 의 '창 대기 중 임대 없음'이 E3 에서 깨지고, 다음 날로 밀리면 E3 가 E2 와 다른 자료 판으로 잰다(캐시 미적중 · DNN 재학습)**

- 주장
  - `main` 은 E2 를 잰 뒤 곧바로 E3 용 임대를 선점한다(p1s02_seed_watch.sh:53-54). 이 선점은 E2 성공 판독(:55)보다 먼저라, E2 가 실패해도 잠깐 쥔다.
  - 그다음 E3 의 `measure_until_done` → `wait_window_and_lane` 이 시각 창을 처음부터 다시 본다(:68-71 · 93). 시작 허용은 08:20~11:45 다(:31).
  - E3 는 E2 의 기저 캐시를 쓰는 증분 측정이다(DESIGN.md:36 '같은 기저(같은 엔진 · 캐시 공유)' · P1S01 DESIGN.md:28 'E3 몫은 증분 비용'). 셸 가정은 'E2 + E3 약 6시간'이다(:6 · 31).
  - 그러면 E2 가 3시간 25분을 넘는 순간 E2 는 11:45 뒤에 끝난다. 08:20 에 시작해도 마찬가지다. 그날 E3 시작 조건은 다시 서지 않는다.
  - 기다리는 동안 E3 보유자 임대가 살아 있다(상한 12시간 · qv_lock.py:36-37). 레인 GPU 슬롯은 그동안 새 claim 을 보류한다.
  - 이것은 머리 주석 :4 · :14 '임대를 미리 쥐지 않는다(창을 기다리는 동안 레인 GPU 슬롯을 세우지 않는다)'와 다르다. DESIGN §5-4(DESIGN.md:58) · BUILD:127 의 설명과도 다르다. 판단 T1 C-086 의 수용 내용('창이 열려 있고 레인이 빌 때만 임대')이 E3 에서 지켜지지 않는다.
  - 다음 날로 밀리면 밤 체인(00:03)이 RAWDATA 를 바꾼다. 기저 캐시 키에는 RAWDATA 도장과 내용 지문이 들어 있어(rf_base_cache.R:15-21) 키가 달라진다. 그러면 E3 는 캐시 미적중으로 DNN 을 한 번 더 학습하고(GPU 한 번 더), E2 와 E3 의 자료 판이 갈린다. DESIGN §3 '캐시 공유'와 §5-6 'E3 도 같은 기저라 같은 기대값'의 전제가 깨진다.
  - 덧붙여: `wait_window_and_lane` 은 시작할 때 지문 안정 시계를 0 으로 돌린다(:84). 그래서 창 안이어도 E3 앞에서 20분 이상 임대를 쥔 채 기다린다.
- 근거: p1s02_seed_watch.sh:4 · 6 · 9 · 14 · 31 · 53-57 · 68-79 · 84 · 93 · qv_lock.py:36-37 · rf_base_cache.R:15-21 · DESIGN.md:36 · 58 · P1S01 DESIGN.md:28 · BUILD_EDITION2.md:127.
- 판정에는 닿지 않는다(측정 · 판정 분리 그대로 · 사양 밖). 등록을 막지 않는다 — 셸을 띄우기 전에 고친다.
- 고칠 것(둘 중 하나)
  - (가) E3 호출에서는 시작 시각 창을 보지 않는다. 체인 · 배리어 · 메모리 · 레인 조건은 그대로 둔다. 'E2 + E3 를 한 창 안에서 시작한다'는 설계 뜻 그대로다.
  - (나) 선점을 E3 의 창 · 레인 조건이 선 뒤로 옮긴다. E2 → E3 사이 틈을 메우는 힘은 약해지지만, 창을 기다리는 동안 쥐는 임대는 0 이 된다.
  - 어느 쪽이든 E2 가 실패하면(e2ok = 0) 선점하지 않는다. 머리 주석과 DESIGN §5-4 문장을 코드와 맞춘다.

**R-2. '다시 재기 조건' 줄의 시드 회계가 T1 문안 '판정받은 판 수만큼'에서 '판마다'로 바뀌었고, 코드 · 추적 자리가 없다**

- 주장
  - T1 C-079 대안 (가)의 문안(20261111_2349_T1_T4.md:25): '조건 = 판정 경로 결함을 판정 결과와 무관하게 **파일:행으로 특정** · 범위 = 판 2 전 항목 · 뒤집힌 판정은 기저 풀에서 표식을 달고 사슬 판 T1 이 본다 · **시드는 판정받은 판 수만큼 회계에 더한다**'.
  - v2 의 줄(round_spec.json:141): '… 고르지 않고 전 항목 · 뒤집힌 판정(미달 → 통과)은 표식 · **시드도 판마다 시행으로 센다**'. '파일:행으로 특정'이 빠졌고, '판정받은 판 수만큼'이 '판마다'가 됐다.
  - '판마다'는 이 판 자신과 어긋나게 읽힐 수 있다.
    - 판 1 은 시드를 원장에 넣었지만(enqueue) 판정은 0건이다.
    - '판마다'로 읽으면 판 2 시드 n_family 는 앞선 최댓값 + 1(265)이어야 한다.
    - 그런데 사양 회계 규칙은 '시드 = 무가산'이고(round_spec.json:47), 두 시드 칸의 n_family 는 264 다(재도출: `rc_standing_nf_prior("2002.06975")` = 264).
    - '판정받은 판 수만큼'으로 읽으면 판 1 이 0 이라 264 와 맞는다.
  - 실행 경로가 없다.
    - v3 의 앞선 회계는 variant 칸과 variant enqueue 만 센다(standing.R:346-354). 그래서 시드(reference)는 몇 판이 판정해도 다음 판에서 늘 같은 값(무가산)으로 돌아온다.
    - DESIGN §6 의 다음 코어 판 후보(DESIGN.md:78-85)에는 `editions_judged` · `flipped_from_fail` 만 있다. 시드 판 수 회계는 없다.
- 판 2 판정에는 닿지 않는다(판 2 시드 264 는 두 문안 모두에서 맞다). 뒤 판의 회계 약속이다.
- 고칠 것(둘 중 하나)
  - (가) 문구를 T1 문안으로 고친다('시드는 판정받은 판 수만큼 회계에 더한다 · 결함은 파일:행으로 특정'). 사양 문장이라 초안 v3 + 변경분 점검이 필요하다.
  - (나) 사양은 그대로 두고 DESIGN §6 에 추적 줄을 적는다: '"판마다" = 판정받은 판 수 · v3 는 시드를 무가산으로 돌려준다(standing.R:346-354) → 다음 판 init 에서 손으로 +k, 또는 다음 코어 판 후보'.

**R-3. '통과 엔진마다 철학 P2 한 줄을 그 엔진의 다음 일 요약에 반드시 싣는다' — 그 줄을 싣는 경로가 v3 에 없고, 확인 수단(superfan-mark)은 '실렸다'가 아니라 'P2 를 받았다'를 적는다**

- 주장
  - 결론 범위 마지막 줄(round_spec.json:152)과 DESIGN §5-9(DESIGN.md:65-66)는 철학 C3 문안 그대로다(20261111_2344_P1_P1S02.md:201). 규약에도 같은 규칙이 있다(superfan_protocol.md:179).
  - v3 `rc_standing_report` 가 하는 일은 다르다.
    - 일 요약은 미달 · 미시험 항목만으로 만들고, 그런 항목이 없는 날은 보내지 않는다(standing.R:996-998 · 1017-1033 — `if (length(fail))`).
    - 통과 엔진은 push 만 받는다(:1004-1016).
    - P2 리뷰나 superfan 표식을 읽는 줄이 없다.
  - 첫 판정 뒤에는 `tick_hold` 를 지우고 무인 틱(`standing_board_run.sh --send`)이 보고를 잇는다(DESIGN.md:67). 그 경로에서는 아무도 P2 줄을 싣지 않는다. 통과가 나온 뒤 미달이 없으면 '그 엔진의 다음 일 요약' 자체가 생기지 않는다.
  - DESIGN §5-9 의 확인 `superfan-mark --kind pass --p2 <리뷰 id>` 는 원장에 P2 리뷰 id 를 적을 뿐이다(standing.R:1046-1052). 일 요약에 줄이 실렸는지는 보지 않는다. 또 이 명령은 `--codes` 가 필수인데(standing.R:1185) 문서의 명령에는 빠졌다.
- 판정에는 닿지 않는다(보고 · 감독 경로). 등록을 막지 않는다.
- 고칠 것
  - DESIGN §5-9(사양 밖)에 실행자 · 통로 · 확인을 적는다. 예: 'Q 가 P2 를 받은 뒤 그 엔진의 다음 [1계층] 보고 1통(`prep_send`)에 한 줄을 싣는다 · 무인 틱의 일 요약은 싣지 않는다(v3) · 확인 = `superfan-mark --codes <code> --kind pass --p2 <id>` + 보고 발송 기록'.
  - DESIGN §6 다음 코어 판 후보에 '일 요약에 통과 엔진의 P2 한 줄(superfan 표식 판독)'을 더한다.
  - 사양 문장('다음 일 요약')을 바꾸려면 초안 v3 이 필요하다. 문장은 두고 DESIGN 에서 그 뜻을 정하는 쪽이 싸다.

### 선택

- **S-1. 판정 전 점검 기대값 `--expect-engine-dates 268` 은 자료 판에 묶인 수다**(DESIGN.md:61 · BUILD:127)
  - `n_engine_dates` 는 엔진 산출의 전 기간 날짜 수다(rf_base_align.R:42 · 65 — τ_D 절단 없음). 268 은 산수로 2004-07 ~ 2026-10 월말이다.
  - 측정일 자료에 월말이 하나 더 들어오면 같은 엔진이 269 를 내고, 점검이 ★ 로 멈춘다. 안전 쪽이지만 거짓 멈춤이다.
  - 측정이 12월로 밀리면 일어날 수 있다(레인 THGNN 측정 중).
  - 고칠 것: DESIGN §5-6 에 '268 = 2026-10 월말까지의 자료 기준 — 측정일 자료의 마지막 월말까지 센 수로 바꿔 넣는다'를 적는다. 첫 엔진 신호일 2004-07-30 은 자료 판과 무관하다.
- **S-2. 리허설이 리허설 폴더와 S9 대조 밖에 쓴 것 두 가지가 REHEARSAL.md §3 · §4 에 없다**
  - `.cache/round_core/perf/P1SR02_rehearsal.jsonl`(rc_perf_log — util.R:227-231 · standing.R:759 · 893 · 919 · 973).
  - 리허설 엔진의 기저 캐시 `.cache/rf_base_signal/`(rf_base_cache.R:4). 요약의 `from_cache = TRUE` 는 앞 실행이 쓴 캐시를 읽었다는 뜻이다.
  - 둘 다 파일 이름 · 키가 리허설 판 · 리허설 엔진 md5 라 판 2 판정에 닿지 않는다. 워커 산출(`stage_artifacts/replication/`)은 이미 공시했다.
  - 요약에 `rehearse.R` md5 가 없다. run 2 → run 3 사이에 스크립트를 고쳤으므로(REHEARSAL.md:48) 어느 판이 돌았는지 요약만으로는 알 수 없다.
  - 고칠 것: 공시 한 줄 + 요약에 스크립트 md5.
- **S-3. `rehearsal/out/` 은 .gitignore 에 걸리지 않는다**(`*.log` 만 걸린다 — .gitignore:59)
  - 등록 전 '판 폴더와 함께 커밋'(DESIGN.md:56 · BUILD:126)을 `git add <판 폴더>` 로 하면 out/ 아래 사람 쪽 파일까지 들어간다(전기간 행동 카드 · 판정 파일 · 사전등록 사본 · scan.json). REHEARSAL.md:4 '커밋하지 않는다'와 어긋난다.
  - 등록 조건 ⑦ 은 out/ 을 빼고 보므로(register.R:103) 등록은 막지 않는다.
  - 고칠 것: §5-2 에 경로 제외를 적는다 — `git add -- <판> ':!<판>/rehearsal/out'`.
- **S-4. DESIGN §2 '측정 관문' 행(DESIGN.md:24)은 아직 '신호가 월말 격자 밖이면'이다**
  - 결론 범위 측정 관문 줄(round_spec.json:138)은 v1 R-2 대로 '한 달 신호 둘 이상(n_superseded > 0) · 달력 밖(n_offcal > 0)'으로 고쳤다.
  - 월말이 아닌 날짜라도 한 달에 하나뿐이면(n_moved > 0) 관문을 지난다(standing.R:845-848).
  - 사고 기록이라 판정과 무관하다. 같은 말로 맞춘다.
- **S-5. 감시 셸 근거 두 곳**
  - 메모리 하한 근거 줄(p1s02_seed_watch.sh:33-35)의 '기저 사용 약 3 GB' 는 인용한 기억 카드 수치(레인 12.7 · R 작업 8.7 · 물리 31.8 GB)에 없다.
  - 낮 창의 '17:45 전 종료'(:6 · 31 · DESIGN.md:58)는 왜 17:45 인지 적혀 있지 않다. 밤 체인 00:03 · 아침 07:10 과는 따로 정한 값이다.
  - 고칠 것: 근거를 한 줄씩 적는다.
- **S-6. 결론 범위 시드 줄과 가설 · 노출이 자료 판에서 다른 말처럼 읽힌다**
  - 결론 범위 시드 줄(round_spec.json:145)은 '같은 학습창 · 입력 · 시드'라고 한다. 가설 · 노출(:9 · :125)은 '차이 = … 자료 판'이라고 한다.
  - E2 엔진은 팩터 DB 를 부르지 않는다(engine.R grep 0). 그러나 RAWDATA 판은 바뀐다. E3 의 DB 팩터 3 은 11-09~10 수리 뒤의 팩터 DB 에서 온다.
  - 철학 (3) 문안 그대로라 '문안대로'는 맞다.
  - 고칠 것: 다음 판에서 '같은 학습창 · 시드(자료 판은 다를 수 있다)'로 쓴다.
- **S-7. 리허설이 지나지 않은 경로 두 가지를 REHEARSAL.md §1 에 한 줄로 공시한다**
  - GPU 임대를 실제로 잡는 길 — 리허설 엔진은 cpu 다(S4g).
  - 조립 칸 경로(E3) — 비중 카탈로그 entropy · `method_registry` 정규화 · as-of IC DB 팩터 · 순위 버퍼.
  - 리허설 칸은 표준 구성(등가중 상위 25) 하나다. 위 두 경로는 판 2 첫 판정에서 처음 지난다.

## 3. 확인한 것(통과 · 근거)

| # | 항목 | 재도출 · 근거 | 결과 |
|---|---|---|---|
| A1 | 사양 블록 대조 | v1(89b014c4) ↔ v2(e336f653) 최상위 키 20개. **같음** = schema · program · round_id · template · core_version · tau_d · purpose · standing · cells · rules · selection · behavior_card_cfg. **다름** = hypothesis · standing_cfg · exposures · conclusion_scope · changes_after_review · changes_after_superfan · tests · pins. 원문 diff 로도 rules(80-118) · selection(119-122) · cells(66-79) · tau_d(7) · behavior_card_cfg 행은 바이트 동일 | 일치 |
| A2 | standing_cfg | 하위 9키 가운데 `rejudge_prior_editions`(true → false)만 다르다. generator_pin · scan · accounting · report · superfan · edition · program · generator 는 같다 | 일치(수용 C-079) |
| A3 | 바뀐 곳 ↔ 목록 | hypothesis · exposures[1](R-1 · 철학 정정) · exposures[2](S-3) · cs[2](R-2 · R-3 4 · 철학 C2 (4) · C4) · cs[3](R-2) · cs[4](R-3 지연) · cs[5](R-4 · R-3 9 · C-079) · 새 cs[6](C-079) · cs[10] · cs[11](C2 (3)) · 새 cs[12](C2 (1)) · 새 cs[13](C2 (2)) · 새 cs[14](C-080) · 새 cs[15](R-3 6 · 4) · cs[17](C3 · C1 (가) · C-087) · tests +3(R-6) · pins.files +3 · basis(F-2) · changes 두 블록. 목록 밖 변경 0 | 일치 |
| A4 | 초안의 비사양 블록 | rules_resolved · sentences · pins.core(매니페스트 4d00113a) · packages · r_version · cells · behavior_card_cfg 가 v1 초안과 같다. 핀 파일 32 → 35(+ factor_z_standard c82870c7 · method_registry a4a8d90b · advanced_weights 9706fcba). 공통 32 경로의 md5 차이 0 · 초안 spec = 디스크 사양 | 일치 |
| A5 | 핀 35 | `rc_pins_compute` = 35 = 기본 18(pins.R:6-13) + pins.files 13 + 엔진 1(RP_AUTO_2002_06975/engine.R fe301130) + 칸 사양 2 + 카드 1 · 겹침 0. 경로별 md5 = 초안 · `rc_pins_mismatches` 0. 코어 매니페스트 = 초안 = RELEASES v3(4d00113a) | 일치 |
| A6 | 시험 7종 | **재실행 안 함(도훈 지시) · 근거 = 점검 v1 실행 결과 + 핀 동일.** 점검 v1 §4 #8 은 4종 + 3종 모두 fail 0 이었다(HEAD 1b1bda18d). 판정 경로 파일 md5 는 그때와 같다(A4). 시험 파일 7종과 코어 v3 는 1b1bda18d 뒤 변경 0(git diff · status). 등록 때 register.R:122-127 이 7종을 다시 돌린다(run_tests 기본 TRUE) | 갈음 |
| A7 | 규칙 문서 | `rc_standing_rules_md(사양)` 재생성 md5 = 3c0213bb = 디스크. rejudge 를 true 로 바꿔 생성해도 3c0213bb 다 — 그 값은 문서에 닿지 않는다(standing.R:1134 고정 문장) | 일치 |
| A8 | 시드 칸 사양 | init_p1s02.R:21-22 그대로 tempfile 에 재생성 → 687d6517 · 3a085178 = 디스크. `nf_prior` = 264 = 두 칸 n_family_at_registration · P0R01_E3_C0 1b9b4052 · 엔진 fe301130 | 일치 |
| A9 | 그 밖 | 규칙 재해석 · 문장 재생성 = 초안 · `rc_rules_test_window_use` 0 · `rc_standing_validate(check_pin)` 통과 · 생성 함수 핀 차이 0 · 카드 사본 = 정본 6a2a1d21 · 초안 md 재생성 = 디스크(811438ee) | 일치 |
| B1 | 입구 문장(cs[2]) | base_off_month_grid = 보는 창 달력 월의 최대 신호일 수 ≥ 2(standing.R:515-518 · τ_D 절단 :501). 폭 = 충족 날이 하루라도 있으면 통과. 패널 판독 불가 = NA → 사유 없음(:506-511 · 604-611) | 일치 |
| B2 | 측정 관문(cs[3]) | base_alignment_missing → base_not_score_panel → n_superseded > 0 ∨ n_offcal > 0 순서(standing.R:822-849 · rf_base_align.R:26) | 일치 |
| B3 | 달 스냅 지연(cs[4]) | 신호일 s 를 s 이상 첫 월말로 옮긴다(rf_base_align.R:45-47). 판정에 가는 측정의 지연 ≤ 그 달 거래일 수 − 1. 달력 밖 신호(다음 달로 가는 경우)는 관문에서 멈춘다 | 일치('약 21') |
| B4 | 판 1 항목(cs[5]) | rejudge = false 면 스캔 · 넣기가 다른 판 원장의 엔진 md5 를 known 으로 본다(standing.R:662-665 · 740-742). 시드는 그 검사를 거치지 않는다(:683-700). 1908.01112 가 portfolio_only_base(:600 — FACTORS 대입 없음)를 벗으려면 engine.R 이 바뀌어야 하므로 md5 가 새로 되고, 판 1 known 에 걸리지 않는다. 최신 판 우선(:296-303) · 사슬이 끊긴 원장은 건너뜀(:276) | 일치 |
| B5 | 다시 재기 조건(cs[6]) | 정책 약속이라 코드 없음. 문안 차이 · 시드 회계 | R-2 |
| B6 | 3치 논리(cs[14]) | `.rc_and` 는 Kleene 논리곱(rules.R:89-91)이고, na = untested 는 NA 를 그대로 둔다(:88). `.rcs_judge_unsettled`(standing.R:978): status ≠ evaluated 이거나 자격이 NA 면 eval_failed(:949-956), 거짓이 하나라도 있으면 미달 판정 | 일치 |
| B7 | 먼지 · 폭(cs[15]) | 실효 시작 보유 수 = `Weight != 0`(measurement_axis.R:249) · 폭은 하루만 충족해도 통과(standing.R:508-509) | 일치 |
| B8 | 원장 열(cs[17]) | `RC_STANDING_VIS_COLS`(standing.R:61-62) = t(α) · 연 α · β · PORT_t · 월 수 · 상승 포착 · CAGR · 하락노출(중앙 · 최악 · 위기 수) · error. 통과 push 판정 줄에 하락노출이 실린다(:1010-1013). '다음 일 요약'은 R-3 | 일치(R-3) |
| B9 | 철학 문안 | C2 (1)~(4) · 노출 정정 · C3 · C1 (가) · C4 · C1 (다) 판독 목록(DESIGN §5-9)을 철학 리뷰 :136-143 · 169-184 · 201 과 글자로 대조했다. 차이는 'S3 ·' 생략 · '헌장' 덧붙임뿐이다. 코드: 기저 풀 현금 기계 = uc_vis < uc_floor(p4.R:180-184) · 칸 감사는 w ≠ 0 행만(cell_eval.R:15) · 기저 풀이 읽는 보는 창 값은 uc_vis 하나(standing.R:290) | 일치 |
| B10 | T1 문안 | C-080 3치 줄(T1 :54) · C-087 사이드카(:61) · C-088 · C-082 → DESIGN §6(DESIGN.md:83-85) · C-081 기대값(prejudge_check.R:9-12 · 49 · 65-66) · C-079 | 일치(R-2) |
| B11 | 시드 재학습 문장 | hypothesis · exposures[1] = 'S2 스케줄 대조 7/0 · 겹치는 262개월 창 · 번호 · 시드 동일'(BUILD:158) | 일치(S-6) |
| B12 | 성과 필드(exposures[2]) | `rc_standing_paper` 는 권위 기록에서 `replication.source_paper` 만 읽는다(standing.R:526-531). 인계 기록에서 쓰는 필드에 등급이 없다(:578-632) | 일치 |
| C1 | F-1 | `tick_hold` 첫 줄 = 사유('판 2 첫 판정 전 — 측정 → 판정 전 점검 → judge(DESIGN 5절) · 첫 판정 뒤 지운다'). DESIGN §5-2 · BUILD:126 의 순서 = 'tick_hold 커밋 → register'. 무인 틱은 tick_hold 를 보면 HELD 로 건너뛴다(standing_board_run.sh:47). 지금 tick_hold 는 미커밋(??) | 절차 맞음 · 커밋 대기 |
| C2 | S-1 · S-2 · S-4 | scan 손으로(DESIGN.md:57) · `--eval` 캐시(DESIGN.md:62 · prejudge_check.R:13) · 규칙문 뜻(DESIGN.md:76 — standing.R:662-665 · 683-700 · standing_rules.md §4 에 관문 셋 없음) | 일치 |
| C3 | R-5 | 기대값 인자 3개(prejudge_check.R:17) — 다르면 ★(항목 5 · 9 — :49 · 65-66). 시작 주입 확인(:63). 실효 시작 날짜는 눈으로 본다(DESIGN.md:61) | 일치(S-1) |
| C4 | C-086 감시 셸 | 순서 W → L → M(p1s02_seed_watch.sh:82-107) · E2 앞 선점 없음 · E3 는 R-1 · `bash -n` 통과 · SELFTEST(임대 · 측정 없음) 종료 0 | R-1 |
| C5 | 창 · 메모리 근거 | 메모리 근거 줄 있음(:33-35 — 보장 문턱이 아니라고 밝힌다) · 이른 창을 뺀 이유(:7) | S-5 |
| D1 | 리허설 격리 | `RC_SA_ROOT` = out/<run>/sa(rehearse.R:26) · 등록부 사본(:108 · 118) · 판단 원장 스텁 · 리뷰 뿌리(:109-114) · check_git · run_tests 끔(:118) · 보고 `send = FALSE` + `QVEST_TG_DRY_RUN`(:26 · 199). S9 = 실제 파일 10개 md5 + 판 1 · 판 2(rehearsal/ 제외) 폴더 해시 + 공유 원장 3개 표식(:63-74 · 212-223). 무인 틱은 깊이 2 의 사양만 보고(standing_board_run.sh:39) 실제 사전등록 뿌리를 요구한다(:46) — 리허설 판을 집을 수 없다. 실제 `rc_standing_known` · `qualified` 는 실제 뿌리만 본다(standing.R:255-263 · 271-276) | 일치(S-2) |
| D2 | 허용 id | ALLOW 는 판단 원장 대조에서만 쓰인다. 그 id 의 judgments · reviews · challenges 항목만 빼고 앞뒤 같은 식으로 센다(rehearse.R:52-62 · 73 · 213). 요약에 기록됐다(`allowed_ledger_ids` = J-20261112-003). 그 판단의 at = 21:27:31 로 run 2(21:23:43 시작)와 run 3(21:29:12 시작) 사이다 — REHEARSAL.md:48 진술과 맞다. 리허설에는 실제 판단 원장에 쓰는 경로가 없다(스텁) | 일치 |
| D3 | 신선도 주입 | 함수 인자 하나다(rehearse.R:154-155) → `rc_standing_measure_item(freshness =)`(standing.R:853) → `rc_fresh_gate` 한 곳(:864). 워커 인자 · 환경변수 · 파일로 넘기지 않는다(:874-880). 실제 경로는 기본값이다: CLI(:1180) · `round.sh standing-measure`(round.sh:136-143) · 감시 셸 measure-item | 리허설 밖으로 새지 않음 |
| D4 | 요약 ↔ 산출 | 두 실행 원장 = enqueue → scan → measure → verdict 4줄(S3 · S4a '2 → 2' · S4b · S6 · S8 '4줄'). reported 0(S7). 사전등록 두 사본 md5 490f9536 = S2. `results/<code>/eval.*` · `standing/<code>.verdict.json` · `standing_visible.json` 이 있다(S5 · S6 — 보는 창 파일은 τ_D 누출이면 쓰기 전에 멈춘다, standing.R:987). scan.json = 디렉터리 51 · 통과 0(S3). 리허설 판 사양은 판 2 사양과 round_id · purpose · hypothesis · cells · exposures · conclusion_scope · changes 만 다르다 | 일치 |
| D5 | 초안 rehearsal = 요약 | ok · at · core · steps · engine_md5 가 같다. `rehearsal.ok` TRUE · out/<run> 요약 md5 = 판 폴더 요약 md5 · 엔진 md5 115790a4 = 디스크 · 요약 at(21:32:58) < 초안 drafted_at(21:33:39). 초안의 `"3": null` 은 register.R:58 의 `[c("ok","value","error")]` 가 error 없는 성공값에서 만든 빈 칸이다. 등록 판독은 `$ok` 뿐이라(:120) 영향 없다 | 일치 |
| D6 | 리허설이 찾은 결함 | defects 0 · 12단계 pass. 실행 이력의 실패 둘(판 id 형식 · 표식 오탐)은 리허설 스크립트 쪽이다 | 결함 0 |

### 등록 조건 ①~⑧ 의 지금 상태(register.R:106-145)

| 조건 | 지금 | 등록 전 할 일 |
|---|---|---|
| ① 마지막 초안 = 격리 점검 ok | drafts 의 마지막 = v2(b3f180ff = 디스크) · review null · 이 점검 = ok | `reviewed 2 <이 파일> ok` |
| ② 사양 · 칸 사양 md5 = 초안 | e336f653 · 687d6517 · 3a085178 일치 | — |
| ③ 핀 재대조 | 35 · 불일치 0 | (등록 때 다시 본다) |
| ④ 라운드 시험 | 재실행 안 함(도훈 지시) · 갈음 근거 = A6 | 등록 때 register.R:122-127 이 7종을 돌린다(run_tests = TRUE 기본) |
| ⑤ 리허설 | `rehearsal.ok` = TRUE(register.R:120) | — |
| ⑥ 철학 P1 | `rc_p1_check` ok · R-20261111-009 · 도전 4 응답 · 열린 보류 0 | — |
| ⑦ 고정 대상 미커밋 | 제외 정규식 밖 9건: `behavior_card_cfg_at_prereg.json` · `rehearsal/REHEARSAL.md` · `rehearsal/rehearsal_summary.json` · `rehearsal/rehearse.R` · `round_spec.json` · `specs/P1S02_E2_C0.json` · `specs/P1S02_E3_RX0.json` · `standing_rules.md` · `tick_hold`. 코어 v3 폴더는 깨끗하다 | 이 9건을 커밋한다(`rehearsal/out` 은 빼고 — S-3). 이 점검 파일은 이름(`prereg_draft`) 때문에 검사에서 빠지지만 함께 커밋하는 편이 낫다 |
| ⑧ 두 사본 + 등록부 | 실행하지 않았다 | — |

## 4. 못 본 것

- 시험 7종의 이번 실행. 도훈 지시로 중단했고, 1종만 끝났다. 그 출력은 근거로 쓰지 않았다.
- 리허설의 판정 · 보고 원문과 eval 내용(경계 안). 단계 결과는 파일 존재 · 사건 종류 · 개수로만 대조했다.
- 감시 셸의 실제 대기 · 측정. 자가 시험만 돌렸다. R-1 의 시간 산수는 셸 자신의 가정('E2 + E3 약 6시간')과 'E3 = 증분'(DESIGN §3 · P1S01 DESIGN:28)에 기댄다 — 실측이 아니다.
- 시드 엔진이 마지막 부분월에 신호를 내는가. 268 이 끝나는 달은 산수로만 추정했다(S-1).
- GPU 임대를 실제로 잡는 경로와 E3 조립 칸 경로(리허설이 지나지 않음 — S-7).
- `check` · `standing-check` 하위 명령. 돌리지 않고 같은 계산을 R 로 했다. `standing-check` 는 `standing_rules.md` 를 다시 쓴다(standing.R:1169) — 브리프의 '쓰기 없음'과 다르다.
- 판단 T1/T4 도전들의 원장 응답 상태. 등록 조건 ⑥ 은 철학 P1 만 본다.
- 철학 C1 (나)(결정 기록부 항목) · N1 · T1 C-082 의 시험 사례(B1g). v2 변경 목록 밖이라 반영 여부를 보지 않았다.
- 셀 엔진 · 러너의 나머지 줄. 판정 경로 대조는 인용한 분기만 봤다.
