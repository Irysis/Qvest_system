# P1S04 사전등록 초안 격리 변경분 점검 v1

- 점검자: 격리 변경분 점검(서브에이전트). 이 판의 설계 · 구현에 참여하지 않았고 측정 결과를 보지 않았다. 기술 점검만 했다(철학 정렬 · 판단 감독 몫은 판단하지 않았다). 점검 시각 2026-11-15 05:30~05:55(KST) · HEAD 시작 · 끝 모두 `39e16a8f2`.
- 점검 종류: 변경분 점검 — 등록된 판 2(P1S02 · 코어 v3) 대비 판 3(P1S04 · 코어 v4) 초안 v1. 근거 결정 `P1S02-EDITION3-REGISTER-LATER-20261114`(resolved · '판 3 등록(같은 시드 · 코어 v4 · v3.5 핀) · 측정 = 첫 GPU 창(레인 양보 · 워커 3 · PYTHON_CPU_COUNT=4)').
- 대상(md5)
  - `prereg_draft.json`(draft_version 1 · **e8589cc49b14cbef501b8e6ff0f890ec**) · `prereg_draft.md`(3456b3f1) · `drafts.json`(8ea95e66 · v1 review = null) · `round_spec.json`(7f26e14b) · `specs/P1S04_E2_C0.json`(b748062d) · `specs/P1S04_E3_RX0.json`(60a9d823) · `behavior_card_cfg_at_prereg.json`(6a2a1d21) · `standing_rules.md`(c4580f49) · `DESIGN.md`(8f607b5d) · `tick_hold`(01a249d8) · `tools/init_p1s04.R`(eec03ff7)
  - 코어 v4 매니페스트 95d4a286(= `RELEASES.json` v4 항목 = 초안 pins.core)
- 비교 기준: 판 2 `../P1S02_standing_qualification/` — 등록본 `prereg.json`(65021bbd · 코어 v3 4d00113a) · `round_spec.json`(e336f653) · `specs/P1S02_E2_C0.json`(687d6517) · `specs/P1S02_E3_RX0.json`(3a085178) · `DESIGN.md` · `prereg_draft_review_v1.md`(revise — 머리 · grep) · `prereg_draft_review_v2.md`(ok — 머리 · §2).
- **판정: ok** — 사양에서 판 2 와 다른 곳은 의도된 차이뿐이다(코어 v4 · 판 3 · 갈래 lane · 결론 범위 앞 레인 철학 줄 2 · 판 3 노출 3 · 판 3 결론 범위 2 · 시험 없음 · 시드 칸 코드 · 회계 문구 · 목적 · 가설 머리). 규칙 · 선택 · 문턱 참조 · 입구(scan) · 생성 함수 핀 · 회계 규칙 · 보고 · 감독 설정은 판 2 와 같다. 핀 35 를 v4 함수로 다시 재 불일치 0 이고, 등급 v3.5 계약 6 파일이 지금 md5 로 핀에 든다. 등록 조건은 철학 P1 · 판단 T1 · 이 점검 기록 말고 지금 모두 선다(리허설 없음 · 시험 없음은 코어 규칙상 통과). 등록을 막을 것은 없다.
  - 권고 셋은 모두 판정 밖이다. R-1 · R-2 는 판 2 에서 그대로 옮긴 결론 범위 문장이 v4 의 레인 갈래 실제 동작과 어긋나는 곳이다 — 사양 문장을 고치려면 초안 v2 + 변경분 점검, 사양을 두려면 DESIGN 에 뜻 · 실행자를 적는다(판 2 점검 v2 R-3 선례). 사양 문장은 등록 뒤 못 고치므로 **처리 방식은 등록 전에 정한다**. R-3 은 등록 뒤 만드는 도구(감시 셸 · 판정 전 점검)의 v4 이식이다.
- **건수: 필수 0 · 권고 3 · 선택 8**

## 0. 정보 경계 선언

- 연 것
  - 판 3 폴더 전부: 사양 · 초안(json · md) · `drafts.json` · `DESIGN.md` · `standing_rules.md` · `tick_hold` · `tools/init_p1s04.R` · 칸 사양 2 · 행동 카드 설정 사본. `results/` 는 비어 있다.
  - 판 2: `round_spec.json` · 등록본 `prereg.json`(규칙 해석 · 문장 · 핀 · 칸 · 키 이름) · 칸 사양 2 · `DESIGN.md`(목차 · §5 · §6) · 점검 v1(머리 · '다음 판' grep) · 점검 v2(머리 · §2) · 도구 `p1s02_seed_watch.sh`(머리 주석 · grep) · `prejudge_check.R`(grep).
  - 상설 원장(사건 종류 · code · 엔진 경로 · 엔진 md5 · 시각 · 측정 줄의 ok · fp_same · rc · seconds · artifacts 경로만): 판 1 `P1S01` · 판 2 `P1S02` 전 줄, P1S03 은 사건 종류 · 갈래 · 판 번호 개수만. 판 1 · 판 2 scan 줄의 디렉터리 수 · 통과 수 · 새 항목 수 · 제외 사유 **키 이름**(값 아님)도 봤다 — 11-11 · 11-12 기록이고 판 2 노출 [9] · DESIGN §5-3 에 이미 있는 사실이다. 판정 줄 본문(visible 값)은 출력하지 않았다.
  - 판 2 `results/`: 파일 이름 · 크기만(E2 측정 시도의 json · log · err.log) — 내용은 열지 않았다.
  - 코어 v4: `register.R` · `pins.R` · `load.R` · `spec.R` · `driver.R` · `measure_cell.R` 전문 · `standing.R`(1-460 · 783-1270 · 1273-1500 · 1600-1766 · v3 대비 diff 전체) · `p1.R`(1-40 · 120-131) · `p4.R`(1-40 · 160-300 · 986-1030 · 1140-1175) · `util.R`(85-226) · `cell_eval.R`(grep) · `fingerprint.sh`(v3 대비 diff) · v3 대비 나머지 파일 diff. 코어 `README.md` v4 절 · `RELEASES.json`(키 · v4 항목 일부) · `round.sh` 전문.
  - 운영(읽기): `standing_board_run.sh`(36-140) · `rf_compute_class.py`(grep · `engine_dependency` 실행) · `rf_replication_slots.py`(grep) · `superfan_watch.py`(470-520) · `superfan_components.json`(standing_board 규칙 grep) · 시드 엔진 `engine.R`(grep · 95-127 · 540-600 · 668-669).
  - 등록부 · 설정: `decision_register.json`(위 결정 항목 하나) · `grade_v3.json`(rules_version · cr_notch.selection_control 키 값만) · 등록부 라운드 목록(`rc_standing_editions` 판독 — 라운드 id · 상태 · 판 · 갈래).
  - P4C01: `DESIGN_draft.md`(grep 'blend · 부품') · `chain_spec.json`(키 · core_version · rules_version · base key).
- 안 연 것: P1S02 · P1S03 · P1R04 의 `results/verdict.json` · `results/<칸>/full/` · `results/<칸>/eval.json` · `results/standing/*.verdict.json` · `report/charts/` · `finalize.json` · `selection_reality_check.json` · `04_Research/01_reports/rawdata_seam_20260330_repair_20261113/` · git `6de5d0678` · `e0ce78c5c` · 모든 `authoritative_remeasure.json` · `stage_artifacts/replication/**` · 판단 원장 · 철학 리뷰.
- 우연 열람: 작업 트리의 `factor_registry.json` diff 머리(커밋 안 된 새 커스텀 팩터 1개 추가 — 이 판 시드의 DB 팩터 3 과 무관)에서 무관한 레인 엔진 하나의 레인 기록 요약 문자열을 봤다. 이 점검에 쓰지 않았고 값은 옮기지 않는다.
- 실행한 것: Rscript 임시 스크립트 3개(세션 스크래치 폴더 — `source(v4/load.R)` 뒤 재도출 · 임시 파일 쓰기만) · Python 판독 4회(원장 · JSON 구조 diff · 엔진 계산 등급 판별). 저장소 쓰기 = 이 파일 하나. `scan --dry-run` 은 돌리지 않았다(노출 [12] '레인 미리보기는 아직 보지 않았다'를 이 점검이 깨지 않게 — 이 파일은 Q 가 읽는다).

## 1. 판정

**ok.** 과제 1~6 을 파일 · 코드로 다시 도출했고 등록을 막는 결함은 없다(근거 §3).

- 사양 차이 = 의도된 목록뿐 · 고정 블록(rules · selection · scan · generator_pin · accounting · report · superfan · pins.files · tau_d · template)은 판 2 와 JSON 동일(§3-1).
- 시드 칸 사양 = 같은 생성 함수 · 같은 원본 사양으로 다시 만들면 디스크 md5 그대로 · 차이는 code · 회계 문구뿐(§3-2).
- 핀 재계산 불일치 0 · 판 2 pins.files 13 전부 · 등급 v3.5 계약 포함(§3-3).
- 등록 조건 ①~⑦ 지금 상태 = 점검 기록만 남았다 · 리허설 없음 · 시험 없음은 코드상 허용(§3-4).
- 판 3 등록 뒤 판 2(v3)는 새 항목을 받지 않고(판 번호 규칙 + 이미 핀 불일치) · 판 3 은 앞 판 항목을 이어받지 않으며 · 자체 사양 판 P1S03 을 막지 않는다 · 시드 GPU 엔진은 상설 측정 경로의 GPU 관문을 지난다(§3-5).
- 사양 글에 시험 창 성과 수치 · 등급 표기 없음 — 코어 검사의 걸림은 모두 식별자 · 창 표기 · 문턱의 거짓 양성(§3-6).

## 2. 지적

### 필수

없음.

### 권고

**R-1. 레인 갈래 통과 칸(이 판 · 시드 포함)에는 v4 기저 풀의 철학 P2 관문이 걸리지 않는다 — 판 2 에서 옮긴 결론 범위 [20] '사슬 판 등록은 그 판독 없이 기저를 받지 않는다 · 첫 사슬 판은 기저의 철학 판독 영수증을 읽는 코어 판(기저 풀 사유 philosophy_unread)으로 등록한다'와 목적의 '기저 풀 관문' · DESIGN §2 표 '기저 풀 v4 관문(철학 영수증 · 저위험 확인 · 판 표식)'이 이 판 통과 칸에도 기계 관문이 있는 것처럼 읽힌다**

- 주장
  - v4 `rc_p4_base_pool` 은 철학 관문(philosophy_unread · philosophy_hold)과 저위험 확인을 자체 사양 엔진 행에만 건다 — `if (own) { … }`(p4.R:250-253 · 261-263) · 머리 주석 '자체 사양 통과 칸만 … 레인 · 등록부 기저의 판정은 v3 그대로'(p4.R:18-19) · 코어 README v4 §5 '자체 사양 통과 칸만 — 레인 · 등록부 행 판정 = v3'(README.md:104).
  - 판 3 의 행은 own = FALSE 다: 갈래 lane · 시드 엔진 폴더에 `own_spec.json` 없음(재도출 FALSE) · 판정 기준 `qown`(p4.R:188).
  - 사슬 판 등록 `rc_p4_chain_register` 도 기저가 자체 사양일 때만 원천 시행을 보고(p4.R:1001), 레인 기저의 철학 P2 영수증은 보지 않는다(p4.R:986-1023 — 사슬 자신의 P1 · T1 영수증만). 블렌드 걸음의 상대 엔진은 '풀 자격'만 요구한다(p4.R:1143-1147).
  - 판 2 DESIGN §6 다음 코어 판 후보(P1S02 DESIGN.md:97)는 'philosophy_unread — 상설 통과 칸 원장의 철학 P2 표식 … 없으면 eligible = FALSE · **blend 상대 칸도 같게** · 첫 사슬 판은 이 사유가 있는 코어 판으로 등록한다'였다 — 대상은 레인 판 2 의 통과 칸이었다. v4 는 이것을 자체 사양 행에만 실었다.
  - 이 판의 시드 E2 · E3 은 결론 범위 [11] 대로 '엔진 결합(blend) 블록의 상대로만' 쓰인다. 통과하면 v4 풀 자격만으로 블렌드 상대가 될 수 있다. 첫 v4 사슬 P4C01 의 부품 계획은 자체 사양 엔진이라(P4C01 DESIGN_draft.md:24) 당장 닿지는 않지만, 블록 어휘가 사슬마다 열려 있어(README v4 §9 p4_rules_v3) 생성기가 레인 통과 칸을 상대로 낼 수 있다.
  - 그래서 [20] 의 약속은 판 3 에서 기계가 아니라 절차로만 선다. 문장은 그 차이를 말하지 않는다.
- 근거: p4.R:18-19 · 188 · 250-263 · 986-1023 · 1143-1147 · README.md:96 · 104 · P1S02 DESIGN.md:97 · round_spec.json:8(목적) · 149([11]) · 158([20]) · DESIGN.md:15(§2 표).
- 판정에는 닿지 않는다(상설 판정 · 원장 그대로). 등록을 막지 않는다.
- 고칠 것(둘 중 하나)
  - (가) 사양 — 결론 범위에 판 3 한 줄: '코어 v4 기저 풀의 철학 관문(philosophy_unread · philosophy_hold)은 자체 사양 통과 칸에만 걸린다 — 이 판(레인 갈래) 통과 칸 · 시드에는 기계 관문이 없다. [20] 의 "판독 없이 기저를 받지 않는다"는 이 판에서 절차로 지킨다: 이 판 통과 칸을 기저 · 블렌드 상대로 받는 사슬 판 등록 · 걸음 전에 그 칸의 철학 P2 리뷰 id(superfan-mark --kind pass --p2)를 사슬 판 판단 T1 이 확인한다 · 기계 관문은 다음 코어 판 후보.' 초안 v2 + 변경분 점검이 필요하다(R-2 와 함께 하면 한 번).
  - (나) 사양은 두고 DESIGN §6 · §7 에 위 뜻 · 실행자 · 확인을 적고, DESIGN §2 표 코어 칸의 '기저 풀 v4 관문'에 '(자체 사양 통과 칸만 — 레인 행 = v3 판정)'을 덧붙인다. 철학 P1 점검에 이 사실을 함께 넘기면 그쪽 판단이 빠르다.

**R-2. 옮겨 온 결론 범위 다섯 줄이 '코어 v3' · '다음 코어 판'을 그대로 말한다 — 넷은 v4 레인 갈래에서 동작이 같아 이름만 낡았고, 하나([20] 의 괄호)는 v4 에서 사실이 아니다**

- 주장
  - [6] '측정 관문(코어 v3)' · [8] '(코어 v3 — 읽을 수 있는 원장만 본다)' · [15] '기저 풀(코어 v3 rc_p4_base_pool)' · [18] '(코어 v3 알려진 한계)'(round_spec.json:144 · 146 · 153 · 156).
    - v4 에서: 기저 정합 관문 본문이 v3 와 같다(standing.R:1323-1350 · v3 대비 diff 덩어리 없음) · 같은 칸 최신 판 = 같은 갈래 안 판 번호 비교(standing.R:436-445 — 레인 한 갈래면 v3 와 같다) · 레인 행 기저 풀 판정 = v3(p4.R:250 주석) · 실효 시작 먼지 = 셀 평가 본문 동일(cell_eval.R 은 머리 줄만 다름)이고 하네스(rf_axes.R · run_paper_replication.R)가 판 2 핀과 같은 md5 라 한계 그대로. 뜻은 맞고 이름만 v3 다.
  - [20] 괄호 '(통과 보고의 판정 줄에 귀속 없는 위기 하락노출이 실린다 — 다음 코어 판에서 가른다)'(round_spec.json:158) — v4 통과 보고는 이미 판정 줄(판정 두 조건) · 보고 열(위기 하락노출 + 고정 문구 `RC_STANDING_REPORT_NOTE`) · OOS 줄로 갈랐다(standing.R:64-65 · 1494-1533 · README v4 §9 '통과 보고'). 판 3 통과 push 에는 괄호의 상태가 생기지 않는다.
  - 같은 줄의 '통과 엔진마다 철학 P2 한 줄을 그 엔진의 다음 일 요약에 반드시 싣는다'는 v4 에도 기계 경로가 없다(README v4 알려진 한계 'C-046 … 없음' · README.md:147 · standing.R:1499-1563 은 superfan 표식을 읽지 않는다). 판 2 DESIGN §5-9 의 절차(Q 가 그 엔진의 다음 [1계층] 보고 1통에 싣는다)가 판 3 에도 그대로 필요하다 — 판 3 DESIGN §5 는 이 단계를 따로 적지 않았다('판 2 §5 승계'로만 덮인다).
  - [21](판 3 줄)은 "'판 2' 라고 적힌 정책"만 판 3 으로 읽게 하고 '코어 v3' 표기 · '다음 코어 판' 약속은 다루지 않는다.
- 판정에는 닿지 않는다(해석 · 보고 경로). 등록을 막지 않는다.
- 고칠 것: (가) R-1 (가)와 같은 초안 v2 에서 [21] 에 한 마디 — "'코어 v3' 라고 적힌 동작은 v4 레인 갈래에서 같다(측정 관문 · 최신 판 판독 · 기저 풀 레인 행 · 실효 시작 한계). [20] 의 '판정 줄에 … 실린다 — 다음 코어 판에서 가른다'는 v4 에서 갈렸다(판정 줄 · 보고 열 · OOS 줄) · P2 한 줄은 판 2 DESIGN §5-9 절차로 싣는다." (나) 사양을 두면 같은 말을 DESIGN §6 에 적고, §5 에 판 2 §5-9(실행자 · 통로 · 확인) 승계를 한 줄로 명시한다.

**R-3. 결론 범위 [22] 가 '판 2 의 것을 판 3 경로로 옮겨 쓴다'고 한 두 도구가 v3 에 묶여 있다 — 감시 셸의 지문 = v3 지문(결합용 뷰 없음) · 판정 전 점검 = v3 코어 적재 · 측정 시간 가정은 워커 8 시절 값**

- 주장
  - 감시 셸 `p1s02_seed_watch.sh:24` `FPS=04_Research/programs/_lib/round_core/v3/fingerprint.sh` — 창 조건 '지문 20분 안정'과 E3 follow 의 '지문 = E2 측정 시작 때'(:6 · :9-11 · :48)를 이 지문으로 본다. 판 3 측정의 fp_same 은 v4 지문이다(`rc_standing_fingerprint` = RC_DIR/fingerprint.sh · standing.R:1273). v4 는 결합용 뷰 `.cache/factor_combinable` 줄을 더했다(v4/fingerprint.sh:4-7 · 20-21). 경로만 바꿔 옮기면 결합용 뷰가 다시 지어지는 동안에도 셸은 '안정'으로 보고 재고, 코어는 fp_same = FALSE 로 그 측정을 버린다(지문 불일치 = 실패 셈 · 상한 `RC_STANDING_MAX_FAILS` = 2 뒤 사람 확인 · standing.R:62 · 305-311).
  - 판정 전 점검 `prejudge_check.R:20` 이 `round_core/v3/load.R` 를 적재한다. `--eval` 이 쓰는 칸 평가 캐시 키에는 코어 매니페스트가 든다(cell_eval.R:35-39) — v3 로 쓴 eval.key 는 v4 judge 가 버리고 다시 평가한다. 판정은 바뀌지 않지만 판 2 DESIGN §5-6 의 '뒤의 judge 가 같은 파일을 읽는다 — 같은 함수'가 깨지고 판정 전 점검이 v3 코드로 돈다.
  - 측정 시간 가정: 셸의 낮 창은 'E2 + E3 약 6시간'(:6 · :34) 가정이다. 판 3 은 워커 3 이다(`PYTHON_CPU_COUNT=4` → os.cpu_count 4 → `min(32, 8, 4 − 1)` = 3 · engine.R:668-669 · venv 파이썬 3.15.2 라 그 변수를 읽는다). DNN 예측 캐시는 입력 내용 주소라(engine.R:564-574 — X · y · Xp 바이트 · 종목) 앞선 측정 뒤 자료가 바뀐 달은 다시 학습한다. 판 2 E2 시도는 약 28.8시간 뒤 rc 1 · 산출 없음으로 끝났다(판 2 원장 측정 줄의 seconds · rc). 6시간 가정을 그대로 두면 밤 체인 · 배리어와 겹쳐 지문 불일치로 버려질 수 있다.
  - 기대값 `--expect-engine-dates 268`(판 2 DESIGN §5-4 · §5-6)은 측정 때 자료의 마지막 월말까지 센 수로 바꿔 넣는다(판 2 점검 v2 S-1 · 판 3 측정은 더 늦다).
- 근거: p1s02_seed_watch.sh:6 · 9-11 · 24 · 34 · 48 · prejudge_check.R:20 · v4/fingerprint.sh:4-7 · 20-21 · standing.R:62 · 305-311 · 1273 · cell_eval.R:35-39 · engine.R:564-574 · 668-669 · P1S02 원장 측정 줄 · round_spec.json:160([22]) · DESIGN.md:29-30.
- 판정에는 닿지 않는다(측정 · 판정 분리 · 사양 밖 도구). 등록을 막지 않는다 — 셸 · 점검 도구를 띄우기 전에 고친다.
- 고칠 것: 이식본은 `FPS=…/round_core/v4/fingerprint.sh` · `source(…/round_core/v4/load.R)` · 기본 판 경로 P1S04 로 바꾸고, 시간 가정 · 창을 워커 3 · 캐시 적중 여부로 다시 정한다. 사양 [22] 는 그대로 두고 DESIGN §5-3 · §5-4 에 'v4 지문 · v4 코어로 이식'을 적는다.

### 선택

- **S-1. 노출 [10] '판 2 는 측정 0건'**(round_spec.json:134) — 판 2 원장에 E2 측정 줄이 1개 있다(ok = FALSE · fp_same = FALSE · rc 1 · artifacts 없음 · 11-14). 판 2 `results/` 에 그 시도의 json · log · err.log 가 있다(이름 · 크기만 봤다). '측정 성공 0건(E2 시도 1회 실패 · 산출 없음 · 성과 값 없음)'이 정확하다. 노출 [7](판 1 의 1908.01112 측정 로그)의 선례대로, Q 가 그 로그를 봤으면 한 줄로 공시한다.
- **S-2. 판 3 결론 범위 두 줄의 '그대로'** — [21] '위 줄들은 판 2 결론 범위 그대로다'의 '위 줄들'에는 판 2 에 없던 v4 레인 철학 줄 2([1] · [2] — p1.R:15-17 `RC_P1_PHILOSOPHY_LINES_GENERAL`)가 든다 → '위 [3]~[20] 18 줄'. [22] '판 3 첫 판정 전 점검 = 판 2 DESIGN §5 절차 그대로'는 판 2 §5-1(등록 전 리허설)까지 품는데 판 3 DESIGN §2 · §5 는 리허설을 뺐다 → '판 3 DESIGN §5(판 2 §5 승계 · 리허설 없음)'. 문구만 — R-1 · R-2 로 초안 v2 를 만들면 함께.
- **S-3. DESIGN §2 의 시험 수 · '실자료 미통과' 문장 · 첫 scan 순서** — DESIGN.md:19 · init_p1s04.R:9 의 '코어 v4 출시 시험 46/46'은 낡은 수다 — `RELEASES.json` v4 tests_at_release = `test_round_core_v4.R` 71 통과 · 0 실패(README v4 시험 줄: 출시 전 수리 전 46). DESIGN.md:20 '레인 입구(lane_handoff scan)는 v4 실자료로 아직 안 지났다'는 반만 맞다 — 출시 시험 O4(test_round_core_v4.R:342-345)가 실제 RP_AUTO_* 전부로 v4 레인 후보 표 = v3 표(열 · 값)를 확인했다. 안 지난 것은 레인 원장에 쓰는 scan(시드 enqueue · scan 줄)이다(코드는 v3 와 같은 길). DESIGN §5-2 '사유 코드별 개수만 보고 이상하면 멈춘다'를 되돌릴 일 없게 하려면(원장은 추가 전용) 등록 뒤 `scan --dry-run`(쓰기 없음) → `scan --max 0`(시드만 · standing.R:1243) → `scan` 순서로 한다. 등록 뒤 미리보기라 노출 [12] 와 충돌하지 않는다.
- **S-4. 판 2 점검 v2 S-6 미반영** — 결론 범위 [13](round_spec.json:151 — 시드 재측정 = '같은 학습창 · 입력 · 시드')은 판 2 문장 그대로다. v2 S-6 은 '다음 판에서 "같은 학습창 · 시드(자료 판은 다를 수 있다)"로 쓴다'였다. DNN 캐시가 입력 내용 주소라(engine.R:564-574) 자료 판이 바뀌면 같은 시드라도 다시 학습한다 — '입력'이 같다는 말은 자료 판에 달려 있다.
- **S-5. 비상설 단계가 상설 판에서 막히지 않는다(v3 부터 그대로)** — `round.sh <판 3> measure` 는 `measure_cell.R`(:11-29 — 상설 여부 · GPU 관문 검사 없음)로 시드 DNN 을 임대 없이 돌리고, `evaluate` 는 `results/verdict.json`(비상설 판정 파일 · driver.R:59-101)을 쓴다. 상설 측정은 그 잔재를 지우고 다시 재지만(standing.R:1374), 임대 없는 GPU 측정은 레인과 겹친다. DESIGN §5 에 '상설 판에는 scan · standing-measure · measure-item · judge · standing-report · standing-status 만'을 한 줄로.
- **S-6. torch · venv 판은 핀 밖** — `RC_PIN_PACKAGES` 는 R 패키지 다섯뿐이다(pins.R:14). DNN 수치는 venv torch 판에 달려 있고 DNN 캐시 키에도 torch 판은 없다(engine.R:564-574 — CODE_VERSION · 사양 · 입력 바이트). 등록과 시드 측정 사이 venv 를 바꾸지 않고, 측정 로그의 torch 판(engine.R:120-127 가 찍는다)을 판정 전 점검에서 본다. 판 2 와 같은 한계다.
- **S-7. 핀이 갈리는 창을 짧게** — 판 2 는 등록(11-12)과 측정 사이에 등급 v3.5 교체(317a9c0e0 · 계약 6 파일)가 들어와 멈췄다. 판 3 도 같은 핀 35 를 건다. 등록을 측정 창 직전에 하거나, 시드 판정이 끝날 때까지 핀 대상(등급 계약 · 셀 엔진 · 하네스 · 커넥터) 교체를 '측정 · 평가 끝난 뒤 미러 → 원자 교체' 순서로 미룬다.
- **S-8. 감시기 scan_stale 은 갈래를 모른다(알려진 한계)** — `superfan_watch.py:485-492` 는 프로그램 폴더마다 판 번호가 가장 큰 원장 하나만 본다. 판 3 첫 scan 뒤에는 판 3 원장만 보이고(P1S03 스캔 정체는 지금처럼 안 보인다), tick_hold 로 손 단계 사이가 26시간을 넘으면 warn 이 날 수 있다(superfan_components.json standing_board `scan_stale` · max_age_h 26). 등록에는 영향이 없다 — 알고 넘어가면 된다.

## 3. 확인한 것(통과 · 근거)

### 3-1. 사양 차이 전수(과제 1 · 판 2 e336f653 → 판 3 7f26e14b · JSON 구조 diff)

- 바뀐 키(전부 의도된 것)
  - `round_id` · `core_version` v3 → v4(round_spec.json:6) · `standing_cfg.edition` 2 → 3(:12) · `standing_cfg.track` 추가 "lane"(:14 · `.rcs_track_of` standing.R:128-131 · 사양 검사의 원천 · 갈래 일치 standing.R:169-172 통과).
  - `purpose` = 판 3 머리 + '아래는 판 2 의 목적 문장 그대로다 — ' + 판 2 문장 · `hypothesis` = '판 2 와 같다 — ' + 판 2 문장(init_p1s04.R:30-35).
  - `cells[].code` · `cells[].spec` 경로 · `behavior_card_cfg` 경로(파일 md5 6a2a1d21 = 판 2 사본 = 지금 `06_Registry/behavior_card.json`).
  - `exposures` 9 → 12 — [1]~[9] 판 2 와 문자열 동일 · 같은 순서 · [10]~[12] 판 3 줄(:134-136).
  - `conclusion_scope` 18 → 22 — [1] · [2] = `rc_p1_philosophy_lines("lane")` = `RC_P1_PHILOSOPHY_LINES_GENERAL`(p1.R:15-17 · 21 · `rc_init_standing_p1` 이 앞에 붙인다 standing.R:1667) 문자열 동일 · [3]~[20] = 판 2 18 줄 동일 · 같은 순서 · [21] · [22] 판 3 줄(:159-160).
  - `tests` 7 → 0(:164) · `changes_after_review` 2 → 0 · `changes_after_superfan` 2 → 0(새 초안 v1 이라 빈 목록 — 판 2 의 두 블록은 판 2 초안의 반영 기록이다).
  - `pins.basis` 머리 · 꼬리 문구(files 13 은 같다 — 3-3).
- 같은 키(판 2 와 JSON 동일): `schema` · `program` · `template` · `tau_d` · `standing` · `rules` · `selection` · `standing_cfg` 의 program · generator · generator_pin(fn_md5 80f8311f · like P0R01_E2_C0 080cfea8 · canon 축 · 25 · 15 · 2e8 · long_only) · scan(9 키) · accounting · rejudge_prior_editions = false · report{pass push_each · fail daily_summary} · superfan{T1 · P1 / T2 · P2 / daily_batch} · `pins.files`.
- scan: v4 레인 기본값 `RC_STANDING_SCAN_DEFAULT`(standing.R:66-69)에 orientation_admit 만 얕게 덮은 재현(`sc[names(scan)] <- scan` standing.R:1653 · init_p1s04.R:47) = 판 3 scan = 판 2 scan(JSON 동일). 실효 방향 층 집합 = engine_native · factor_db_static(`rc_standing_orient_admitted` standing.R:716 — engine_native 이면 factor_db_static 을 함께 넣어 v4 기본값 그대로여도 같은 집합). 노출 [12] 문장과 맞다.
- 규칙: 지금 해석(`rc_rules_resolve`) = 판 3 초안 `rules_resolved` = 판 2 등록본 `rules_resolved`(JSON 동일) · `sentences` 동일 · 사양 rules = v4 P1 템플릿(`.rcs_p1_template_rules`) · q_t_alpha = `constraint_defaults.json::tier_graduation.grade_b_min_portfolio_alpha_t` → 2 · q_uc = 0.55(헌장 근거 문구) · test_hold = 보고 전용 · `rc_rules_test_window_use` = 없음 · `rc_standing_validate(check_pin = TRUE)` 통과 · 생성 함수 핀 차이 0(`rc_standing_pin_diff`).
- 규칙 문서: `rc_standing_rules_md(spec)` 재생성 md5 c4580f49 = 디스크 `standing_rules.md`. 판 2 문서와 다른 줄 = 머리(판 3) · §3 제목의 갈래 표기 · 사유 표의 v4 자체 사양 사유 5행 · `paper_meta_missing` 문구 · §4 '같은 입구 갈래' 문장 — 모두 코어 v4 상수에서 나온다. `prereg_draft.md` 도 `rc_prereg_md` 재생성 md5 = 디스크(3456b3f1 = drafts.json md5_md).

### 3-2. 시드 칸 사양(과제 2)

- 구조 diff(판 2 칸 ↔ 판 3 칸, 두 칸 모두): `code` · `selection_accounting.n_trials_basis` 문구만 다르다.
- 재생성: E2 = `rc_p1_cell_spec("P1S04_E2_C0", RP_AUTO_2002_06975/engine.R, paper, "2002.06975", 264, 판 3 문구)` → b748062d = 디스크 · E3 = `rc_standing_seed_respec(P0R01_E3_C0.json, "P1S04_E3_RX0", 264, 판 3 문구)` → 60a9d823 = 디스크. 판 2 칸 2개도 v4 함수 + 판 2 문구로 다시 만들면 판 2 디스크 md5(687d6517 · 3a085178)와 같다 → 같은 생성 경로 · 원본 사양(P0R01_E2_C0 080cfea8 · P0R01_E3_C0 1b9b4052) 불변.
- 엔진 경로 = `04_Research/strategies/RP_AUTO_2002_06975/engine.R`(E2 슬래시 · E3 역슬래시 섞인 절대 경로 — 판 2 와 같은 표기 · `rc_rel` 로 같은 저장소 상대 경로 1개 · C:\Users\99922\OneDrive → G:\OneDrive 정션으로 같은 파일) · 엔진 md5 fe301130 = 판 2 핀 = 판 2 원장 enqueue md5 = 지금.
- 측정 축 `all_hyg_px1000_2000_v1` = `measurement_axis.active` · 표준 구성 = 판 2 와 같다(E2: 롱온리 · 25 · 15bps · 2e8 · ew · base_weight 0.5 · 2000-01-01 · ALL_HYG / E3: + DB 팩터 3(M01_Mom_12_1 · V10_FCF_Yield · M08_Residual_Mom) · `lean:entropy` · rank_buffer ×2).
- n_family 264 = `rc_standing_nf_prior("2002.06975")`. 판 2 DESIGN §6(P1S02 DESIGN.md:86-90)의 '판마다 = 판정받은 판 수' 뜻으로 판 1 · 판 2 시드 판정 0 → 무가산 264 가 맞다. 엔진 옆 own_spec.json 없음 → 레인 시드 경로(자체 사양 시드 검사 standing.R:214-231 대상 아님).

### 3-3. 핀(과제 3)

- `rc_pins_mismatches(pre$pins, rc_root())` = **0건**(코어 판 · 매니페스트 · 파일 35 · 패키지 5 · R 판).
- `rc_pins_compute(spec)` 재계산 = 초안과 파일 35 · md5 집합 동일 · 코어 v4 매니페스트 95d4a286 = RELEASES v4 = 초안 · 패키지 data.table 1.18.6.1 · jsonlite 2.0.0 · arrow 26.0.0 · PerformanceAnalytics 2.0.8 · bbdetection 1.0 · R 4.6.2.
- 구성: `RC_PIN_FILES_DEFAULT` 18 전부(pins.R:6-13) + 판 2 pins.files 13 전부 + 엔진 자동 핀 1(pins.R:27-35) + 칸 사양 2 + 행동 카드 사본 1 = 35.
- 등급 v3.5 계약: `contracts/grade_v3.R`(436debe9) · `06_Registry/grade_v3.json`(7677c169 · rules_version = v3.5 · cr_notch.selection_control = size_beta) · `essence_score.R` · `matched_controls.R` · `matched_controls.json` · `diagnosis_packet.R` · `behavior_card.R` · `beta_controlled_alpha.R` 모두 핀에 든다.
- 판 2 등록 핀과 대조: 같은 35 경로 중 판 폴더 3 파일만 경로가 다르고, md5 가 다른 것은 등급 v3.5 교체 6 파일(diagnosis_packet.R · essence_score.R · grade_v3.R · matched_controls.R · grade_v3.json · matched_controls.json — 317a9c0e0)뿐이다 = 판 2 를 멈춘 6 개. 그 6 파일은 317a9c0e0 뒤 커밋 없음 · 핀 대상 경로 전부 작업 트리 변경 없음(git status).

### 3-4. 등록 조건(과제 4 · register.R:107-145)

- ① 마지막 초안 v1 의 review = null(지금). 이 점검 뒤 `round.sh <판> reviewed 1 <이 파일> ok` 가 `rc_mark_reviewed`(register.R:66-77 — 디스크 초안 md5 = v1 md5 확인 · 파일 md5 · git HEAD 기록)로 채운다. 판정이 ok 여야 등록된다(register.R:112-113).
- ② 디스크 초안 md5 e8589cc4… = drafts.json v1 md5(register.R:114) · 사양 md5 7f26e14b = 초안 spec_md5(register.R:116 · `rc_spec_load` = 파일 바이트 md5 spec.R:39-43) · 초안 안 spec 사본 = 디스크 사양(JSON 동일).
- ③ 칸 사양 md5 2 = 초안 cells md5(register.R:117).
- ④ 핀 불일치 0(register.R:118-119).
- ⑤ 리허설: register.R:120 은 `pre$rehearsal` 이 **있고** ok 가 아닐 때만 멈춘다 — 초안에 rehearsal 키 없음 → 통과. 리허설은 `rc_draft(rehearse = )` 의 선택 인자다(register.R:45 · 58). **리허설 없는 등록은 코어 규칙상 허용**된다.
- ⑥ 시험: register.R:121-127 은 사양 `tests` 를 돌 때만 — `tests` [] → 돌 것 없음 → 통과(`run_tests` 값과 무관) · 등록본 tests = 빈 목록. 근거 '직전 결과 + 핀 동일'(도훈 11-12): 코어 v4 파일 md5 = RELEASES v4 매니페스트(출시 시험 71/0 의 그 파일들).
- ⑦ `rc_uncommitted`(register.R:99-104) = 0 — 판 폴더 · v4 코어 · 칸 사양 커밋됨(39e16a8f2 · tick_hold 포함 · `git ls-files` 11 파일). 이 점검 파일과 drafts.json 갱신은 필터(`prereg_draft|drafts[.]json|/results/|rehearsal/out`) 안이라 ⑦ 을 막지 않는다.
- ⑧ 철학 P1(`rc_p1_check` — 파일 형식 `…/philosophy/<8자리>_<4자리>_P1_P1S04.md` · 도전 응답 · 열린 보류 없음) · 판단 T1 = 이 점검 범위 밖.
- 등록 뒤 쓰는 곳: `stage_artifacts/programs/P1_RETURN/P1S04_standing_qualification/prereg.json`(지금 없음) + 판 폴더 사본 + 등록부(실패 시 둘 다 되돌림 register.R:137-143). 등록본이 생기면 무인 틱 `standing_board_run.sh` 가 판을 찾지만 `tick_hold` 로 HELD(standing_board_run.sh:38-48).

### 3-5. 위험 판독(과제 5)

- (a) 레인 입구 v3 → v4 에서 바뀐 곳(standing.R v3 ↔ v4 diff 전수)
  - 옛 판 받기 정지 = **같은 갈래**의 더 높은 판만(v4 standing.R:331-336 · v3 :234-235 는 갈래 없이 번호만) · 판 목록에 track 열(:342-356) · 원장 줄 머리에 track(:274-285 · schema 그대로).
  - 레인 후보 표: `scan.source = own_spec` 일 때만 자체 사양 판독으로 분기(:783-788). 레인 판독 본문(v3 :311-636 = v4 :457-782)은 diff 덩어리가 없다. 출시 시험 O4(test_round_core_v4.R:342-345)가 실제 RP_AUTO_* 로 v4 표 = v3 표를 확인했다.
  - enqueue · 시드: 엔진 폴더에 own_spec.json 이 있거나 갈래 own_spec 일 때만 자체 사양 길(:1124-1151 · :1178-1184) — RP_AUTO_* · 시드 엔진에는 없다 → v3 와 같은 회계 · 기록. 판정 출시 관문은 own_spec 갈래만(:981-990). 측정(:1352-1399) · GPU 관문(:1282-1321) · 기저 정합(:1323-1350) 본문은 v3 와 같다.
  - 판 2 정지: 판 2(v3) 맥락은 지금도 핀 불일치 6 으로 모든 단계가 멈춘다(v3 standing.R:229-230 이 판 번호 검사보다 먼저). 판 3 등록 뒤에는 enqueue 맥락의 판 번호 규칙(3 > 2 · v3 :234-235)으로도 막힌다 — 모의: v3 규칙 → P1S04 가 막음. v4 규칙 모의: 판 3 을 막는 lane 판 없음 · P1S03(own_spec · 판 1)을 막는 판 없음 → 판 3 등록이 자체 사양 갈래를 멈추지 않는다(코어 README v4 §3 · 시험 T4 와 같은 결론).
  - 이어받지 않음: 시드는 판 3 등록본 칸만 넣는다(`.rcs_enqueue_seeds` :1168-1192 · `for (c in ctx$pre[["cells"]])` :1170). 스캔 행은 rejudge_prior_editions = false 라 K = 모든 상설 원장의 enqueue md5(`rc_standing_known` :357-366 · :1236-1238 · enqueue 재확인 :1111-1114) → 판 1 · 판 2 원장 엔진(6b6a8e1a · 66443a35 · fe301130)은 known 으로 다시 넣지 않는다. 판정은 자기 원장만 읽는다(:1403-1407).
    - 판 2 원장 = 시드 enqueue 2(fe301130) · scan 1 · 측정 실패 1 · 판정 0(레인 항목 없음 — 판 2 DESIGN §5-3 '등록 전 미리보기 = 0'과 같은 사실). 판 1 원장 = 시드 2(6b6a8e1a) · 레인 1(1908.01112 · 66443a35) · 측정 실패 2 · 판정 0. → 판 3 이 이어받을 판정은 없다.
    - 주의(동작 그대로 · 결론 범위 [8] 과 맞음): known = '다른 판 원장에 넣은 적 있음'(판정 여부 무관 — :357-366)이고 CLI 표기는 '이미 판정'이다(:1751). 판정 0건으로 멈춘 판의 항목도 md5 가 같으면 막힌다 — 지금 해당 = 1908.01112 하나(md5 66443a35 지금도 같음 · 판 2 DESIGN §6 대로 입구에서 portfolio_only_base 로 빠지는 엔진) — 점수 패널 패치(엔진 md5 변경) 뒤에만 새 항목으로 온다.
  - 기저 풀 판독(`rc_standing_qualified` :384-455): 같은 갈래 안 최신 판 · 판 1 · 판 2 판정 0 → 같은 칸(엔진 경로 + 구성)의 판정은 판 3 것 하나가 된다.
- (b) GPU 관문: 상설 측정 `rc_standing_measure_item` 의 기본 gpu = `rc_gpu_guard`(standing.R:1354 · 호출 :1369) · `round.sh standing-measure` → `standing.R measure-item`(round.sh:136-143) 이 그 함수를 기본 인자로 부른다. 판별 `rf_compute_class.engine_dependency("04_Research/strategies/RP_AUTO_2002_06975")` = `(True, 'engine.R:import torch')` → class gpu(엔진 본문 engine.R:449 — DNN 파이썬 원본이 engine.R 안 문자열이라 엔진 md5 핀이 DNN 코드를 덮는다). 그래서 레인 live claim 0 + `gpu_lease_acquire` 를 잡은 뒤에만 재고, 못 잡으면 원장 무기록 · 다음 틱 재개(:1369-1371). v3 와 같은 본문이고 판 2 의 11-14 E2 시도가 이 길을 지났다. 비상설 경로(`round.sh measure` → measure_cell.R)에는 이 관문이 없다 — S-5.

### 3-6. 정보 경계(과제 6)

- `rc_input_issues`(v4 util.R:209-225)를 사양 글의 필드 · 줄마다 돌렸다. 걸린 것은 모두 거짓 양성이다(식별자 · 창 표기 · 문턱):
  - 목적 — 결정 id 안 날짜(…-20261114 · …-20261111).
  - 가설 — '보고 전용' 창 낱말과 상승 포착 문턱 수가 한 칸에 있다.
  - 노출 [1] — 시험 창 시작 연도 표기(창 이름) · [5] — 전기간 낱말과 논문 id 의 소수부 · [8] — 판단 리뷰 id 안 날짜 · [11](판 3 새 줄) — 라운드 id 'P1S03' 의 'S0' 을 지표 이름 + 수로 읽는다.
  - 결론 범위 [1] — 코어 상수 철학 줄의 결정 id 안 날짜.
  - 등급 표기 검사(`.rc_grade_hits`) = 0 · 시험 창 성과 수치 · τ_D 뒤 성과 날짜 = 0.
- 판 2 사양에도 같은 거짓 양성(노출의 창 표기 · 리뷰 id · 논문 id)이 있다. 판 3 에서 새로 생긴 것은 노출 [11] 의 라운드 id 하나다. 노출 [11] 은 Q 가 사람 쪽 지표를 본 사실만 적고 수치는 옮기지 않았다.
- `rc_after_tau_leaks(초안 json)` = drafted_at · R 판 문자열의 날짜뿐. `DESIGN.md` · `standing_rules.md` · `tick_hold` · `init_p1s04.R` · 커밋 39e16a8f2 메시지도 같은 종류(결정 id 날짜 · 라운드 id)만 — 등급 표기 0.
- 참고: `rc_register` 는 이 검사를 부르지 않는다(등록 조건 밖) — 위는 이 점검의 판독이다.

## 4. 못 본 것

- 철학 P1 · 판단 T1 판독(범위 밖) · 판단 원장 내용.
- 레인 미리보기(`scan --dry-run`) — 일부러 돌리지 않았다(§0). 지금 레인 산출로 입구를 지나는 엔진 수는 모른다.
- 시드 실측(GPU · 워커 3 · 실제 소요 시간) · 감시 셸 · 판정 전 점검 이식본(아직 없음) · venv torch 판.
- 판 2 `results/` 파일 내용 · P1S03 판정 내용 · P4C01 의 걸음 · 풀 스냅샷.
- 결합용 뷰 · 팩터 DB 의 지금 빌드 시각(측정 때 지문이 판독한다).
