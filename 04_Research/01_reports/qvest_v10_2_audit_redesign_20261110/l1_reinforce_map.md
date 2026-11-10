# 1계층 강화(P4) 지도와 빠진 고리 — 읽기 전용 조사 (2026-11-10)

범위: 충실구현 레인 산출 → 프로그램 재료 → P1 상설 자격 → P4 조립 · 처방 루프 → 결과 원장 → 다음 설계.
표기: `파일:행` = 직접 확인. "미확인" = 보지 못함. 2023 이후 성과 수치는 옮기지 않았다(필드 이름만).
절차 고지: 지시는 R · Python 실행 금지였는데, 조사 중 `overlay_catalog.json` 의 상태 집계를 위해 `python -c`(JSON 읽기 한 번 · 쓰기 없음)를 한 번 실행했다. 그 밖에는 grep · 파일 읽기만 했다.

---

## 0. 현재 흐름 (텍스트 그림)

```
[충실구현 레인] rf_replication_auto.sh → run_paper_replication → 검증기 rf_replication_verify.R
   └ .v1001_handoff (rf_replication_verify.R:272-301)
        ├ 행동 카드 bc_card_from_artifacts → behavior_card.json
        └ 등록부 재료 항목 {key="engine:<base_id>", kind="engine", base_status, paper_key, grade, fidelity,
             artifacts, engine_path, routed_by, cr_verdict, + flags(has_short · implementation_suspect · audit_verdict …)}
             → pr_enqueue(<라우터 프로그램>)  (P1/P2/P3 큐)  |  분류 없음 → paper_routing.unrouted
                      (P4 큐로 가는 길 없음 — research_programs.json:3044 "queue": [])
[P1 상설 자격 P1S01] (구현 · 시험됨 · 미등록)
   standing.R 스캔: 레인 폴더 RP_AUTO_* + 등록부 kind=engine 인계 기록, routed_program = P1_RETURN 만
   → rc_p1_cell_spec(엔진 신호 그대로 · 표준 구성 25종 EW) → 측정 → 자격 판정 → standing_ledger.jsonl
   → "자격 목록 = P4 후보" 라고 적혀 있으나 읽는 쪽 없음
[P4 조립 · 처방 루프] P4R01_skeleton_rx (구 round_kit 방식 · 라운드 0회)
   prepare_analyst.R: P0R01 verdict == "reached" 아니면 멈춤 ← P0R01 = not_reached
   → 진단 패킷(보는 창) + 헌장 + 도구 상자 → 분석가 레인(rx_lane.sh · opus · 청정)
   → prepare_prescriber.R → 처방 담당 레인 → 처방 1~3건 + 기계 형식 반증 · 선택 규칙
   → register.R: rx_validate · rx_compile_spec · 사전등록(selection_type = "sweep")
   → (측정 스크립트 없음 — round_kit rk_measure_cell 은 있으나 P4R01 이 부르지 않음)
   → evaluate.R: 기계 반증 · 기계 선택 → 리뷰어 레인
   → close_round.R: 보고 · 등록부 기록(결과 원장 쓰기 없음)
[결과 원장] round_outcomes.jsonl ← round_core rc_close 만 씀 (p1/p2/p3 템플릿 전용) · 파일 아직 없음
   rc_outcomes_md · rc_open_probes 의 코드 소비자 0 (SKILL 의 수동 명령뿐)
```

---

## Q1 기저 유입

**있는 것**
- 레인 → 등록부: `02_Infrastructure/ops/rf_replication_verify.R:285-290` 이 `kind="engine"` 항목을 `engine_path`(레인 `RP_AUTO_*/engine.R`) · `artifacts` · `grade` · `fidelity` · `has_short` 등과 함께 라우터 프로그램 큐에 넣는다. 프로그램 결정 = 등록부 키 → 라우터 v5 산출 → 미분류 보류(`:253-264`).
- 실측 상태: 등록부의 엔진 항목 12건 — P1 4 · P2 1 · P3 5 · 미분류 2(`06_Registry/research_programs.json` 행 1134~1190 · 2099 · 2266 · 3059~). P4 큐는 비어 있다(`:3044`).
- 셀 엔진은 레인 엔진을 기저로 직접 부를 수 있다: `rf_cell_engine.R:102-190` — `base_signal = {kind:"engine", path}` 이면 엔진 파일을 `sys.source` 해 `FACTORS$Score`(또는 `PORTFOLIO$Weight`)를 `.base_sig` 로 쓴다 · 캐시 `rf_base_cache.R`.
- P1 상설 자격의 칸 생성기가 이 경로를 쓴다: `04_Research/programs/_lib/round_core/v1/p1.R:55-76`(`s$base_signal <- list(kind="engine", path=ep)` · `:70`).

**끊기는 곳**
1. **P1S01 미등록** — `stage_artifacts/programs/P1_RETURN/` 에 P1S01 폴더 없음 · 등록부에 P1S01 라운드 없음(grep 0). 설계 `qvest_v10_2_audit_redesign_20261110/README.md:113` "미출시 · 미등록".
2. **스캔이 P1 라우팅분만** — `standing.R:20-23` `routed_program = "P1_RETURN"` 기본 · `:98` 판의 프로그램과 같아야 함. P3 로 라우팅된 엔진 5건 · P2 1건 · 미분류 2건은 어느 상설 판도 안 본다.
3. **롱숏 엔진 다수 탈락** — 입구 사유 `long_leg_absent`(`standing.R:36`). 레인 엔진 대다수가 `has_short: true`(예 `research_programs.json:1168, 1187`). 롱 레그를 따로 꺼내는 변환이 입구에 없다(P1R02 가 한 번 수동으로 했다 — `:252-269`).
4. **자격 → P4 배선 없음** — `standing.R:105` "자격 목록 = P4 후보 · 선택 없음", `p1.R:100` 같은 문구. 그러나 `standing_ledger.jsonl` 을 읽는 코드는 standing.R 과 그 시험 밖에 없다(grep). P4R01 은 골격을 P0R01 `evaluation.json` 에서만 가져온다(`P4R01_skeleton_rx/prepare_analyst.R:12-18`).
5. **PORTFOLIO 만 내는 엔진** — 기저 신호가 보유 종목에만 정의돼 팩터 결합이 막힌다(`rf_cell_engine.R:381-398` 후보 중앙 ≤ 25 이면 팩터 칸 stop).
6. **경로 표기** — 항목 `engine_path` 가 `C:\Users\99922\OneDrive\...`(예 `research_programs.json:1182`), P4R01 스크립트도 `ROOT <- "C:/Users/99922/..."` 하드코딩(`prepare_analyst.R:6` 외 4파일). 이 기기 저장소는 `G:/OneDrive/...`. `/c/Users/99922` 폴더는 있다. 같은 저장소를 가리키는지(정션 등)는 **미확인**. `rc_abs`(p1.R:64)의 해석도 **미확인**.

## Q2 조립 어휘 (셀 엔진 · 처방 도구 상자)

처방이 바꿀 수 있는 축 = `rx_round.R:270` `factors · weighting · universe · rebalance · overlay · defense_sleeve · cap_core`. 고정 = 기저 신호 · `base_weight` · n_max · 비용 · 시그널 월말(`rx_round.R:139-144` 도구 상자 0절).

| 단 | 표현 가능 | 근거 | 못 하는 것 |
|---|---|---|---|
| ① 국면 조건부 노출(게이트) | 오버레이 층(노출 스케일 Σw≤1) — 빌트인 10종 `vol_scale · ewma_vol · har_vol · turbulence · ml_tail_gate · ts_mom_gate · dd_recovery · vol_x_turb · dd_brake · vol_x_dd`(`rf_cell_engine.R:721-722`) + 파일 arm `overlay_arms/<kind>.R`(`:724-737`) · 층 곱(`:622-643`) · 카탈로그 active 만 처방 가능(`rx_round.R:87-96`, `:304-313`) | 빌트인 특징 = 국내 벤치 수익 · 횡단면 분산뿐(`:654-688`) | 매크로 · FRED 국면 입력(BOOK_0001 의 M4 × AE)은 쓸 수 없다 — `pg2_risk_overlay_v1` 은 `suspended`(overlay_catalog), C11 격리(`06_Registry/pit_quarantine.json:378-385`). 국면 조건부 **팩터 가중**은 없다(weight_catalog `regime_tilt` 등 퇴화 배선 — `pit_quarantine.json:385`). 주간 신호에는 오버레이 불가(`rf_cell_engine.R:646-651`) |
| ② 꼬리 · 변동성 오버레이 | 위 오버레이와 같다 + 축소 워밍업(`:708-715`) · 층별 n_min(`:742`) | | 꼬리위험 **종목 β 오버레이**(BOOK_0001 β_R05 · 위기 때 상한 0.20→0.10 — `02_Infrastructure/book/rebalance_spec.json:194-207`)에 대응하는 블록 없음. 파일 arm 은 종목별 노출(`.expo_x`)을 낼 수 있다(`:706`). 새 arm 은 G1/G2 검증 경로(reinforce SKILL:41)를 거쳐야 한다 |
| ③ 구성 | `weighting` = ew · score_tilt · rank_weight · rank_weight_sqrt · inv_vol · catalog(`rf_cell_engine.R:452-550`, 검증 `rx_round.R:282-287`) · `rebalance` = interval · rank_buffer · no_trade_band(turnover_cap 거부 `:300-301`) · `defense_sleeve`(`rf_cell_engine.R:419-450`) · `cap_core`(`:556-591`) · `universe`(`:204-254`) | | **종목 수는 처방이 못 바꾼다**(n_max = fixed_axes · `:37-38`). **종목별 비중 상한 블록 없음** — 카탈로그 ctx `ub = 1`(`:508`). BOOK_0001 상한 0.20 은 표현 불가(v10 상한 폐지 원칙과 별개로 '선택지'로도 없다) |
| ④ 엔진 결합 | 셀 엔진에는 `engine_blend`(엔진 ≥ 2 · 월별 rank-Z **등가중 평균** · `:158-177`) | | 처방 경로에선 불가 — `rx_validate` 가 `base_signal` 을 받지 않는다(`rx_round.R:270-274`) · 도구 상자가 "기저 신호 고정"(`:143`). 결합 가중 · 국면별 결합 없음. 결합은 도훈 확인 대상(SKILL:140 · standing.R:29) |

## Q3 루프의 현재 모양

- 한 라운드(P4R01 설계): 진단 패킷 `dp_build`(보는 창 절단 · `diagnosis_packet.R:230-302`) → ① 분석가(`prepare_analyst.R:66-107` · 입력 = 패킷 md · 헌장 · 도구 상자 · 엔진 설명 · P2R02/P3R01 메모 · 논문 txt) → ② 처방 담당(`prepare_prescriber.R:38-78` · 처방 1~3건 · 기계 형식 반증 · 선택 규칙) → 등록(`register.R`) → 측정 → 평가(`evaluate.R:20-50` 기계 반증 · 기계 선택) → ③ 리뷰어(`:74-93` · deepen/pivot/stop · next_probes) → 닫기(`close_round.R`). 레인 = `rx_lane.sh`(opus · max · 읽기 전용 · `:9-18`).
- **형태 = 스윕**: `register.R:44` `selection_type = "sweep"` · 처방 1~3건 중 하나 선택. 사슬형(한 걸음 = 가설 하나 → 칸 하나)은 구현이 없다.
- 사전등록 양식 = `register.R:58-69`(`rx_prereg_v1`). 선택 규칙 = 처방 담당이 JSON 으로 씀 · R 은 **형식만** 검사(`register.R:28-32`). 변형 수 상한 = `budget.variants_max = 3`(리터럴 · `:69`). 시행 수 = 리터럴 산술 "골격 + 6 + 10 + 처방 수"(`:41-46`). `trial_budget.R` 호출 없음.
- **0회인 이유**
  1. 코드 관문: `prepare_analyst.R:14` P0 `reached` 아니면 stop ← P0R01 `verdict: not_reached`(`research_programs.json:176`).
  2. 결정: `P4-SKELETON-REVIEW-20261018` open · 기본값 "P4 는 착수하지 않는다"(`decision_register.json:3657-3676`). 등록부 P4 `blocked_by: [P0_FRONTIER]` · status_reason(`research_programs.json:3040-3045`). v10.2 는 이를 기준 사다리로 대체 상정(설계 README:238) — 사다리 착수는 도훈 결정 2(README:232).
  3. 빠진 코드: P4R01 에 측정 스크립트 없음 · round_core 에 P4/처방 템플릿 없음(`spec.R` `RC_TEMPLATES` p1/p2/p3/custom · `driver.R:74-78` custom 은 판정 stop) → `round.sh close` 도 못 쓴다(verdict.json 필요). 칸 경로에 A 자격 관문 없음(`close_round.R:34` · 설계 README:318). 칸 측정 어댑터는 있다(`02_Infrastructure/ops/rf_cell_worker.R:90`).
  4. 사슬 자격 검사(걸음당 후보 수 · 보는 창 선택)는 설계에만 있고(README:115) 코드 없음 — round_core 에 `selection_type`·`trial` grep 0(p1.R:73 의 "sweep" 리터럴뿐).

## Q4 목표와 격차

- **BOOK_0001 정본 수치 위치**: `06_Registry/book/book_registry.json:17-26` `official_metrics` = `sr_gross · cagr · mdd · ir_vs_k200 · beta · oos_2024_2026_sr` · `basis = "official gross 267m (book_state v2.6)"`. 등급 근거 `grade_basis = dohoon_mandate_20260829`(`:11`) · `judge_verdict_path: null`(`:12`).
  - gross · **구 축**(K200∪KQ150 · `rebalance_spec.json:79`) · 267개월 = 시험 창을 포함하는 전기간 값. **2022-12-31 이전으로 나뉜 값은 등록부에 없다** → 지금 있는 값은 처방 입력(τ_D)으로 쓸 수 없고 같은 epoch 비교도 안 된다(CLAUDE.md '등급 비교는 같은 epoch 안에서만'). 값은 옮기지 않는다.
  - `rebalance_spec.json` 에는 목표 성과 필드가 없다(입력 · 관문 · 오버레이 배선만 — 키 집계 확인).
- **쓸 수 있는 목표 정본**: `research_programs.json:6-48` `target_spec`(`upside_capture_min 0.55` · `crisis_cum_capture_strong`(파생) · `crisis_dd_capture_for_mdd25`(파생) · `cagr_min 0.16` · `grade_a`). 등급 문턱 = `grade_v3.R::gv3_thresholds`(rx_round.R:205 가 읽음).
- **격차 → 생성기**
  - `rx_charter_md`(`rx_round.R:207-225`)가 보는 창 PORT_t 에서 S ≥ 1 에 필요한 Calmar · MDD 를 역산해 헌장에 싣는다 — 유일한 '격차' 입력. 어느 하한이 A 를 막는지(`grade_v3.R:445` `why = floor:<이름>`)는 패킷 · 헌장에 실리지 않는다.
  - 진단 패킷에 병목 필드 없음(`diagnosis_packet.R:281-299` 키 목록).
  - `.cache/portfolio_gap_vector.json` = 구 판(`base_strategy STR_1469…` · as_of 11-01). 소비자는 구 governor · 훅 · 퇴역 프롬프트뿐(grep) — P4 와 무관.
  - BOOK_0001 높이(사다리 ⓪~③ 단의 현 축 · 보는 창 값)는 아직 측정되지 않았다 — 사다리 = 도훈 결정 2 대기.

## Q5 재귀 · 자기개선

- 결과 원장: 쓰는 곳 = `round_core/v1/register.R:150-161` `rc_close` 뿐. 읽는 함수 = `outcomes.R:85-123`(`rc_open_probes` · `rc_r7_streak` · `rc_outcomes_md`). **코드 소비자 0**(02_Infrastructure · programs · .claude grep). SKILL §0-1 ⑥ 의 수동 명령(`research-program/SKILL.md:69-73`)뿐. 파일 `06_Registry/round_outcomes.jsonl` **없음**(아직 0줄).
- P4R01 `close_round.R` 는 원장에 쓰지 않는다. 리뷰어 `next_probes` 는 out.md 안에만 남는다(`evaluate.R:91` · `close_round.R:16`).
- 생성기 판 관리: **없음**.
  - 프롬프트는 R 문자열에 박혀 있다(`prepare_analyst.R:66-107` · `prepare_prescriber.R:38-78` · `evaluate.R:74-93`). 판 · md5 필드 없음.
  - 사전등록은 에이전트 **산출** md5 만 기록(`register.R:63`) — 입력 프롬프트 md5 · 판은 없다.
  - 도구 상자 판은 머리말 리터럴 "처방 루프 v0"(`rx_round.R:135`)뿐.
  - 탐색 순서 정의 파일 없음. 개정 기록 · 개정 전후 비교 장치 없음. (구 B5 생성 프롬프트 `overlay_arms/prompt_gen_*.txt` 는 날짜 파일일 뿐 판 비교가 아니다.)
- 자연스러운 자리:
  - 생성기 판 = `06_Registry/` 아래 등록부 하나(예: `rx_generator.json` — 프롬프트 파일 경로 · md5 · 판 · 개정 사유 · 비교 근거 라운드). 프롬프트 본문은 `04_Research/programs/P4_ASSEMBLY/_generator/v<n>/*.md` 파일로 뺀다.
  - `rx_prepare_lane`(`rx_round.R:243-254`)에 "판 지정 → 파일 읽기 → md5 반환"을 넣는다. 사전등록이 그 md5 를 핀으로 기록한다.
  - 원장 기록에 `generator_version` 칸 추가(`outcomes.R:54-61`).
  - 다음 설계 입력 = `rc_outcomes_md` + `rc_open_probes` 를 분석가 재료 md 로 넣는다(`prepare_analyst.R:60-61` 의 files 목록). 이미 τ_D 날짜 검사를 거친 글만 원장에 있다(`outcomes.R:51-52`).

## Q6 철학 정합

- **기계 조건이 있는 곳**: round_core 짝 템플릿.
  - β 짝: `pair.R:72-106` · `p3.R:169-190`
  - 집중 −10%: `pair.R:167` · `p3.R:203-207`
  - 알파 비열등: `pair.R:180-184`
  - 강세 참여 ≥ uc_floor · 사이클 과반: `p3.R:149-156`
  - P1 자격 uc ≥ 0.55 — 리터럴 + basis 문구(`p1.R:96-97` · `behavior_card.json::uc_floor` value_ref 아님)
- **P4R01 에는 없다**:
  - 선택 규칙 = 처방 담당 재량. 프롬프트가 "require 에 상승 포착 하한 등을 넣어라"고 권고만 한다(`prepare_prescriber.R:60-63`).
  - 반증 필드 목록(`:18-24`)에 β 짝 결과 · 집중 · 알파 비열등 · 시드 띠가 없다.
  - 헌장 실패 형태(현금 기계 · 노출 방어 · 집중 · 추첨 행운 — `00_Lawbook/specs/investment_philosophy_charter.md:35-45`)를 기계로 거는 코드는 p2/p3 템플릿뿐이다.
  - "여유(시드 띠 하단)로 순위"(SKILL:76)는 P2R05 라운드 전용 코드에만 있고 코어에 없다 — **미확인**(P2R05 evaluate.R 미열람).
- **헌장 빈칸이 P4 에서 미정으로 남기는 것**(모두 open · 기본값 = 현행 헌장)
  - GAPS-4(`decision_register.json:3593~`): ① 선택 방어 정의(크기 × β 동시 짝?) ② 방어 특성 방향 원리 ③ **방어 기준점(엔진 대비 vs 시장 대비 — 철학 P4 가 1순위로 지목, P4 조립까지 확장)** ④ 독립 엔진 정의(같은 DNN 기저 두 구성 = 두 엔진?). 이 넷이 CR '강함' 증거 (b) 와 엔진 결합 칸의 자격을 가른다.
  - GAPS-5(`:3615~`): 꾸준함의 단위(CDaR vs Sharpe) · 엔진 보존 단위(보유 겹침) · 전면 급락 vs 분산 위기 무게.
  - GAPS-6(`:3636~`): 엔진 동일성(추첨 · 손실이 다른 같은 구조) · '추첨 행운' 실패 형태 추가 · '학습 방어' 이름 조건.
  - GAPS-7(`:3677~`): **'매번'의 단위(장치마다 vs 조립 단위 — P4 결합 판정의 핵심)** · **S 가 오른 현금 기계를 후보 · P4 부품에서 뺄지**.
  - 설계 README:238 — 빈칸 4건은 등록된 권고안을 기본값으로 쓰고 사전등록에 그 사실을 적는다(Q 진행 사항 · 다음 라운드 세션에서 집행).

---

## 빠진 고리 목록 (우선순위순)

P2R05 핀 = `P2R05_distribution_target/prereg.json` 의 경로 목록. 셀 엔진 일가(`rf_cell_engine.R` · `rf_rebalance.R` · `rf_sleeve.R` · `rf_axes.R` · `rf_base_cache.R`), `rf_cell_worker.R`, `run_paper_replication.R`, 계약(`diagnosis_packet.R` · `essence_score.R` · `grade_v3.R` · `matched_controls.R` · `behavior_card.R` · `measurement_axis.R`), `constraint_defaults.json`, `factor_registry.json`, `weight_catalog.R`, `replication_harness.R`, `overlay_pit_guard.R`, `round_kit.R` 가 든다.
**들지 않는 것**: `rx_round.R` · `program_registry.R`(노출 서술 문구에만 나옴) · `round_core/v1/*` · `outcomes.R` · `trial_budget.R` · `rf_capcore.R` · `overlay_catalog.json` · `overlay_arms/`.
v10.2 규칙 ⑤ 에 따라 P2R05 는 뒤로 미루고 측정 시작 때 재핀하므로, 핀 파일을 고치면 재개 때 재핀이 필요해진다(금지는 아님).

| # | 고리 | 붙일 자리 | 최소 변경 | P2R05 핀 |
|---|---|---|---|---|
| 1 | P4 라운드가 P0 'reached' 에 묶임 · 골격 출처가 P0 하나 | `P4R01_skeleton_rx/prepare_analyst.R:12-18` · 등록부 P4 `blocked_by` | 골격 출처를 '기저 후보 목록'(P1S01 자격 원장 + 지정 기준 칸)으로 일반화한다. blocked_by 변경은 `P4-SKELETON-REVIEW` 결정 경유 | 무 |
| 2 | P1S01 미등록 · 자격 원장 → P4 소비자 없음 | `round_core/v1/standing.R`(읽기 함수 추가) · P4 준비 스크립트 | `rc_standing_qualified(program)` 같은 읽기 함수 하나 + P4 가 그것을 기저 풀로 읽는다. 등록 = `round.sh register` | 무 |
| 3 | P4/사슬형 템플릿 부재 → round_core 판정 · 닫기 · 결과 원장 · 핀 대조를 P4 가 못 씀 | `round_core/v1/spec.R` `RC_TEMPLATES` · `driver.R:74-78` · `rc_summary:33-42` | `p4_chain` 템플릿: 걸음 = 칸 1(+ 같은 판본 기저) · 판정 = 사전등록 반증 + 짝 판정(pair.R 재사용) · 사슬 자격 검사(걸음당 variant 1 · 규칙이 *_test 안 씀 · 변경 사유 1줄) | 무(코어는 핀 밖) |
| 4 | 칸 경로에 A 자격 관문 없음 | `run_paper_replication.R` §11 셀 분기 · `rf_runner_gates.R::rf_a_eligibility` | 셀 칸에도 관문을 태우고, 사전등록 '최종 후보' 칸에만 A 자격(설계 README:296) | **유**(`run_paper_replication.R` · `rf_cell_worker.R`) |
| 5 | 처방이 기저 · 결합을 못 바꿈 | `rx_round.R:270`(ok_axes) · `rx_compile_spec:318-333` · 도구 상자 0절 | `base_signal` 을 '자격 풀 안의 엔진 id' 또는 `engine_blend`(풀 안 ≥ 2) 로만 허용(경로 직접 지정 금지). 결합 칸 = 도훈 확인 규칙(SKILL:140) 유지 | 무(rx_round) · 결합 가중이 필요하면 `rf_cell_engine.R:158-177` **유** |
| 6 | 국면 게이트 입력이 국내 벤치 상태뿐 · 종목 β 꼬리 오버레이 · 비중 상한 블록 없음 | 새 파일 arm `overlay_arms/<k>.R` + `overlay_catalog.json` active · G1/G2 검증(`rf_overlay_admit.R` · `rf_overlay_adversary.R`) | 엔진 무수정으로 파일 arm 추가(C11 가용 시점 판 · as-of 모수). 비중 상한은 weight 카탈로그 adapter(ub 인자) 또는 엔진 블록 | arm · 카탈로그 무 · 엔진 상한 블록이면 **유**(`rf_cell_engine.R`) |
| 7 | 격차(병목 하한)가 생성기에 안 감 | `diagnosis_packet.R:281-299`(필드 추가) 또는 `rx_charter_md`(`rx_round.R:201-240`) | 보는 창 값으로 `gv3_decide` 의 `why`(하한별 통과/미달)와 각 하한까지의 거리를 계산해 헌장 md 에 싣는다. 패킷을 고치지 않고 rx_round 쪽에서 계산하면 핀 무접촉 | rx_round 쪽 무 · 패킷 쪽 **유** |
| 8 | 결과 원장 소비자 없음 · P4R01 닫기가 원장에 안 씀 | 분석가 재료(`prepare_analyst.R:60-61`) · `close_round.R` → 템플릿 3 으로 대체 | `rc_outcomes_md` + `rc_open_probes` 를 분석가 · 처방 담당 재료 md 로 넣는다. 리뷰어 `next_probes` → `round.sh close --probe` | 무 |
| 9 | 생성기 판 관리 없음 | `06_Registry/rx_generator.json`(신설) · `rx_prepare_lane` · 원장 `outcomes.R:54-61` | 프롬프트를 파일로 빼고 판 · md5 기록 · 사전등록 핀 · 원장 `generator_version`. 개정은 N 바퀴마다 원장 요약 → 새 판(판정 규칙은 건드리지 않음) | 무 |
| 10 | 철학 조건 · 여유 순위가 P4 선택에 기계로 없음 | P4 템플릿(3)의 선택 규칙 — `pair.R` β 짝 · 집중 · 알파 비열등 · `p3.R:149` 참여 재사용 | 처방 담당 재량 선택 규칙 위에 '헌장 하한 묶음'을 코어가 강제 · 순위 = 하한 여유(시드 띠 하단 — P2R05 구현 이식은 미확인) | 무 |
| 11 | 시행 예산 · 사슬/스윕 판정이 등록에 연결 안 됨 | `round_core/v1/register.R`(rc_register) · `P4R01 register.R:41-46` 리터럴 산술 | 스윕형이면 `tb_max_trials` 결과를 사전등록에 첨부하지 않으면 등록 거부 | 무 |
| 12 | 레인 엔진 롱숏 → 롱온리 기저 변환 없음 | `standing.R` 입구(`long_leg_absent`) · `rc_p1_cell_spec` | '롱 레그 점수' 표준 변환을 사양 사전 고정 판으로(P1R02 선례) — 새 판(P1S02) 등록 사안 | 무 |
| 13 | 하드코딩 루트 `C:/Users/99922/...` | P4R01 5파일 · 등록부 `engine_path` | `rc_root()`/`QM_ROOT` 사용 · 경로를 저장소 상대로 | 무 |

---

## 미확인

- `C:/Users/99922/OneDrive/Quant_Module_Moltbot` 가 이 기기에서 `G:/OneDrive/...` 와 같은 저장소인지(정션 등) · `rc_abs` 가 역슬래시 절대경로를 어떻게 해석하는지.
- `rf_replication_auto.sh` · `02_Infrastructure/alpha_search/` 재료 등록 부분 전문(인계는 검증기 `.v1001_handoff` 로 확인).
- `run_paper_replication.R` §11 셀 분기 본문(관문 부재는 close_round.R:34 주석 · 설계 README:318 진술로만 확인).
- weight_catalog 에 비중 상한 arm 이 있는지 · overlay 파일 arm 계약(ctx 필드 전부).
- P2R05 evaluate.R 의 시드 띠 · 판정 여유 구현이 코어로 이식 가능한 형태인지.
- `l1_prescription_redesign_20261013/README.md` 원설계 본문(이번에 읽지 않음) · `06_Registry/reinforce_program.json` 블록 어휘 본문 · `matched_controls.R` · `behavior_card.R` 본문.
- 레인 폴더 `RP_AUTO_*` 의 개수 · 구조(스캔 규칙으로만 확인).
