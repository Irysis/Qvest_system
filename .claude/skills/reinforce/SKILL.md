---
name: reinforce
description: 강화 프로세스 (v10) — A등급 미달 전략을 QEPM(alpha→risk→optimizer→forge→등급)으로 강화. 1계층 = 논문당 최대 25회 = 격자 5블록×5(멀티팩터/비중방법론/유니버스/리스크오버레이/결합) · 2계층 = 무한(국면식별/전략결합). 매 시도 = Axiom 주입 + L-code 발행(근거 논문은 2026-09-03 의무 해제 · evidence 로 기록만). A 달성 시 Judge(PIT) 호출. 원장 = reinforce_ledger_l1/l2.json.
---

# 강화 프로세스 (v10 2026-08-29 — 기계 사다리 퇴역, QEPM 기반 재정의)

**목적 = A등급 달성.** 충실구현(1계층) 또는 로테이션 리서치(2계층)가 A 미달로 끝난
전략을, **논문이 제시한 후속 연구 또는 논문에서 추론 가능한 아이디어**로 강화한다.
구 기계 사다리(reinforce_ladder.R — 고정 3단 arm 스윕)는 퇴역 — 강화는 이제
LLM 주도 심층 리서치이며, "후속 연구까지 포함하여 인뎁스 수준으로 논문 리서치를
진행하라"(도훈)는 뜻이다.

## 상한과 축

| 계층 | 상한 | keyword_axis | 원장 |
|---|---|---|---|
| 1계층 | **논문당 최대 25회 = 격자 25칸(5블록×5)** (소진 → exhausted → 새 논문) | `multifactor` / `weighting` / `universe` / `risk_overlay` / `combination` | `06_Registry/reinforce_ledger_l1.json` |
| 2계층 | **무한** (A 달성까지 — 교훈 지속 주입) | `regime_identification` / `strategy_combination` | `06_Registry/reinforce_ledger_l2.json` |

25회 제한의 목적 = **실패의 재생산 방지**(도훈). 같은 아이디어의 재탕이 아니라
매 시도가 새 논문 근거·새 축이어야 한다.

## §0.1 무인 실행 (도훈 지시 2026-08-30 "모든 작업을 무인화")

v10 의 "무인 파이프라인은 수집까지만" 경계가 **해제**됐다. 강화는 사람 지시 없이 돈다.

★**규칙 개시 위에 LLM 이 닿는 지점 4곳** (2026-09-04 현행 — 구판 "루프에 LLM 없음" 서술 폐기):
① **B1 설계** — 블록 진입 시 entry 당 1회(`rf_b1_design.sh` → `rf_b1_design_lib::b1_verify` 가 등록부 실재성·중복·칸 수 ≤15 를
   재도출로 검증, 실패 = 규칙 선정 폴백 `rf_factor_arms.R`). ② **블록 기전 + 다음 블록 설계** — 블록 종료 시 1회
   (`rf_lcode_mechanism.sh` → `next_block_design` 이 있으면 다음 블록의 셀 목록이 된다, `rf_block_design.R` 검증). ③ **충실도 감사**
   6축 팬아웃(`rf_fidelity_fanout.sh` · `06_Registry/rf_fidelity_axes.json` · 병합 `rf_fidelity_merge.R` 결정론). ④ **arm 생성**(§0.2).
   ★LLM 은 **제안**만 한다 — 등재·집행·판정은 전부 R 이 재도출로 검증한 뒤에만 일어나고, 셀 엔진은 하나이며 러너는 코드를 생성하지 않는다.
   ★프롬프트는 **stdin**(`printf %s "$PROMPT" > "$PF"; claude -p < "$PF"`) — argv 는 Windows 32K 에서 조용히 죽는다(승격 entry 실사고).

| 조각 | 파일 | 역할 |
|---|---|---|
| 격자 | `06_Registry/reinforce_program.json` | 25칸 정의(5블록×5 · 실행 순서 B1→B2→B3→B5→B4). **논문 독립** — 기저 신호만 논문에서 온다 |
| 엔진 | `02_Infrastructure/reinforcement/rf_cell_engine.R` | **단 하나**. 셀 스펙(JSON)을 읽어 FACTORS/PORTFOLIO 산출 |
| 러너 | `02_Infrastructure/ops/reinforce_auto_parallel.R` (`mode=parallel` · 블록 5칸 병렬) | 1 tick = 1블록. 칸 결정 → 워커 실행 → 등급 → 원장 → 기전 → 텔레그램 → 누적 → 다음 블록. `reinforce_auto_run.R` 은 순차 폴백 |
| 이월 | `02_Infrastructure/ops/reinforce_auto_next_paper.R` | 25칸 소진 → exhausted → 큐 다음 논문 착수 요청 |
| 선택 | `02_Infrastructure/ops/rf_next_paper_pick.py` | 큐 상단 1편(술어 정본 import — 재구현 금지) |
| 스위치 | `06_Registry/reinforce_auto_config.json` | `{enabled:false}` → 전면 정지 · `daily_cap` 폭주 backstop |
| 검사 | `08_Tests/ops/test_reinforce_auto.sh` | **양방향** 15항 (가드마다 정상+위반주입) |
| B1 설계 | `02_Infrastructure/ops/rf_b1_design.sh` + `rf_b1_design_lib.R` | LLM 1회/entry · 검증 실패 = 규칙 폴백 · 재료 상한(교훈 기전 700자) |
| 기전·설계 | `02_Infrastructure/ops/rf_lcode_mechanism.sh` + `_lib.R` · `rf_block_design.R` | 블록 종료 시 기전 서술 + `next_block_design`/`avoid` · 빈 블록은 `rf_mech_backfill.R` 이 재시도(상한 2) |
| 순서 | `02_Infrastructure/reinforcement/rf_lesson.R::rf_block_order_decide` | CAGR ≥ 0.16 ∧ Calmar < 0.64 → 위험 축(B5) 2번째 · 기전 `mechanism_pref` 우선 · `QVEST_RF_ORDER_PREF=off` |
| 누적 | 러너 `block_accumulate` | B2·B3·B5 는 **직전까지 최고 구성**을 바닥으로(자기 축만 교체) · B4 = 이 entry 승자 결합 + LOO |
| 승격 | `02_Infrastructure/reinforcement/rf_promote.R` | 소진 시 최고 ≥ B ∧ 부모 최고 PORT_t 초과 ∧ 깊이 ≤ 3 → 승자 구성 carry(팩터·비중·유니버스·오버레이)로 새 25칸 · `count_paper=FALSE` |
| 구제 | `02_Infrastructure/contracts/rolling_grade.R` · `defensive_score.R` | 36M 롤링 창 최근 통과율 ≥ 0.5(롤링점 ≥ 24) → F→C 구제(회복→붕괴 이력 경고) · 벤치 하락월 기준 방어형 → 2계층 풀 `defensive_specialist` |
| 양립·강등 | `02_Infrastructure/reinforcement/rf_arm_compat.R` | arm×유니버스 커버리지 장부 · 승계 비중이 시험 축이 아닌 블록에서 불가면 EW 강등(`rac_degrade_plan`, B2/B4 제외) |
| 회피 집행 | 러너 (`avoid_enforced` / `avoid_noted`) | 기전 `avoid` 중 **측정 무효 사유**만 건너뜀 · 성과 사유는 기록 후 실행(AX-000) · 부모 사슬 walk |
| 결합 | `02_Infrastructure/ops/rf_combination_launch.R` | 재료 풀 → 설계 요청(`replication_request.json` combo) → 충실구현 레인이 LLM 결합 엔진을 1회 측정 → `_combo_rulefast` entry → 같은 격자 · 희석 판정 기록 |
| 텔레그램 | `rf_auto_notify.R` · `rf_block_insights.R` · `rf_grade_fanfare.R` · `rf_round_review.R` | 블록 본문(+`이번 배치에서 알게 된 것` 요약) · 후속 전체판 · B/A 팬파레 · 라운드 종료 리뷰(궤적·LOO·벽) |
| LLM 레인 | `02_Infrastructure/ops/rf_llm_env.sh` · config `llm.lanes` | 모델 = `llm.model`(opus · fable-5-1 은 CLI 차단 기록) · 노력 replication max / fidelity_audit xhigh / b1_design·lcode_mechanism·overlay_propose high |

**자동 정지 지점 2곳** — 무인이 넘으면 안 되는 선:
1. **충실구현 필요** → 논문 원문 판독(롱숏·종목수·비중·리밸 복제)은 규칙으로 환원되지 않는다.
   `06_Registry/replication_request.json` 을 남기고 세션을 기다린다.
2. **논문 큐 소진** → 무동작(정지 아님). 수집이 채우면 재개.

★**Grade A 는 정지 지점이 아니다**(도훈 지시 2026-08-30 "A등급 달성하더라도 리서치가 이어지게").
구판은 A 에서 `enabled=false` 로 전 루프를 세웠는데, 그건 **리서치 루프**와 **BOOK 등재 관문**을
뒤섞은 설계다 — 후보 하나가 A 를 찍었다고 나머지 칸과 다음 논문이 설 이유가 없다.
현행: A → `06_Registry/grade_a_queue.json` 적재 + `judge_request.json` 발행 + 텔레그램 즉시,
그리고 **루프는 계속 돈다**. 등재 관문만 사람이 지킨다 — Judge(PIT) PASS + 도훈 confirm 없이
BOOK 에 들어가는 경로는 없다(헌법 불변).

**승자 판정은 셀 코드 기반**(`essence$cell_code`) — 위치 의존(n번째=격자 n번째)이면 격자를 손보는
순간 조용히 엇갈린다. 그래서 원장 `essence` 에 기계 판독 가능한 수치를 반드시 남긴다.

★**노력수준 (2026-09-04 도훈 승인 레인 배분)**: 한 값으로 정하면 손해다 — 레인마다 한 번 실패의 대가가 다르다.
replication **max**(실패 1회 = 에이전트 12분 + 측정 + 팬아웃 6축) · fidelity_audit **xhigh** · b1_design / lcode_mechanism /
overlay_propose **high**. 정본 = `reinforce_auto_config.json::llm.lanes`(문서 아님). 충실구현·Judge 는 여전히 **깊이 · 단일 에이전트**
(2026-08-29 실증) — 팬아웃은 분류(6축 대조)이지 넓이 탐색이 아니다.

## §0 규칙기반 고속 강화 프로그램 (도훈 지시 2026-08-29 — 현행 정본)

> 도훈 원문: "빠른 속도로 1)다른 여러가지 팩터들을 Z-Score 컴포짓으로 결합하여 멀티팩터
> 포트폴리오를 만들어보고, 2)비중결정 방법론을 다르게 가져가보고, 3)유니버스를 바꿔보면서
> 전략 등급을 업그레이드. 1)5번 2)5번 3)5번 4)1,2,3 조합 5번 = 총 20회. 빠르게 여러 가지
> 강화 방안들을 적용해보는 것이 목적. 게이트 검증 완화, 규칙 기반의 빠른 강화 프로세스."

**구조 (25회 = 5블록 × 5회)** — ★2026-09-01 도훈 지시로 재편: B5 리스크 오버레이 블록 신설, 실행 순서 B1→B2→B3→**B5→B4**, B1·B2·B5 는 격자에 박지 않고 등록부를 소비. 위 인용의 "총 20회"는 8-29 당시 원문이며 상한은 25 로 확장됐다(정본 = `reinforce_program.json` · 원장 `max_attempts=25`).
★아래 실측 인용에 나오는 `1~3/20` · `5/20` · `9/20` 등은 **상한이 아니라 8-29 당시의 시도 번호**다 — 분모를 문서에서 읽지 말고 원장 `max_attempts` 에서 셀 것:

| 블록 | 축 | 내용 | 선행 조건 |
|---|---|---|---|
| B1 (1~5) | 멀티팩터 | **블록 진입 시 LLM 설계 1회**(`rf_b1_design.sh` — 칸 수·팩터 수·조합 방식을 설계가 정하고, 등록부 331종 안에서 `b1_verify` 가 실재성·중복·≤15칸을 검증) · 실패 = 규칙 선정 폴백(깊이 1~5 · IC 시계열 상관 최소 사슬 · 계열 라운드로빈, `rf_factor_arms.R`) · 승격 entry 는 carry 팩터 위에 얹는다 | 없음 — 즉시 |
| B2 (6~10) | 비중방법론 | B1 최고 PORT_t 컴포짓 위에서 `weight_catalog.json` 계열당 1종(`rf_weight_arms.R` — 낙폭 축 계열 우선) ★직전 블록 기전의 `next_block_design` 이 있으면 그 셀 목록 · 바닥 = 직전까지 최고 구성(block_accumulate) | B1 착지 |
| B3 (11~15) | 유니버스 | B1 최고 컴포짓 + EW 로 **적용 유니버스 교체**: 시장별(KOSPI 전수/KOSDAQ 전수)·시가총액별(소형/대형)·섹터 중립 ★기전 설계 우선 · 바닥 = 직전까지 최고 구성 · 승계 비중 불가 시 EW 강등 | B1 착지 |
| B5 (16~20) | 리스크 오버레이 | B1 최고 컴포짓 + EW 위에 `overlay_catalog.json` 계열당 1종(`rf_overlay_arms.R` — 낙폭/combo 계열 우선) · 승자 = Calmar ★기전 설계 우선 · 오버레이는 carry 위에 중첩(`.ov_stack`) · 순서 규칙이 Calmar 미달이면 2번째로 당긴다 | B1 착지 |
| B4 (21~25) | 조합 | B1·B2·B3·B5 승자의 **4축 전체 결합 1칸 + 축별 leave-one-out 4칸** | B1~B3·B5 착지 |

**규율 — 폐기된 것과 불변인 것**:
- 폐기: 착수 게이트(승자-레그 앵커·β 보상·범주) · 논문별 가설설계 라운드 · 무신호 대조 의무 ·
  arm 배터리. 시도의 설계는 **이 표의 규칙**이지 에이전트의 재량이 아니다.
- 불변: **PIT C1~C15** · 실투형 축(long-only·≤25종·K200∪KQ150 경계·2005-01-01~·15bps·Σw=1·
  LIQ 2e8) · **권위 등급 = essence 단일**(모든 시도가 측정에 도달한다 — 미측정 시도 금지) ·
  root_papers 는 있으면 1줄 정본 인용(★2026-09-03 원장 기계 강제 **해제** — 없으면 evidence=none) · `detect_lookahead` 하드 게이트는 불변.
- 유니버스 축(B3)은 **전략 적용 유니버스 자체를 교체**한다 — 도훈 명시 2026-08-29:
  "시장별(코스피, 코스닥), 시가총액별(소형주/중형주/대형주 등), 섹터별 등등 전략 적용
  유니버스를 바꿔보란 거였어". 즉 B3 에 한해 K200∪KQ150 은 고정이 아니라 **비교 기준선**이다
  (구 '부분집합만' 해석은 Q-Lead 오독 — 폐기). ★유동성 하한 adv20 ≥ 2e8(t-1) 은 전 유니버스
  공통 유지(실투 가능성 + C10). ★B1·B2·B4 의 기본 유니버스는 여전히 K200∪KQ150.
- 실행 = engine 1파일(FACTORS 또는 PORTFOLIO) + `run_paper_replication(portfolio_spec=실투형)`
  → `authoritative_remeasure.json::essence_grade`. WT 미사용(원장 wt_id=NULL 허용).
- 보고 단위 = **블록**(시도 5건 등급 일괄 텔레그램 + L-code 1건). Grade A 발생 시 즉시 Judge.

## §0.3 격자 위의 판정 규칙 — 실행 정본 (2026-09-04 · 코드가 정본, 이 절은 지도)

격자(25칸)는 그대로다. 오늘 바뀐 것은 **칸을 채우는 주체와 칸 사이의 이음매**다.

1. **블록 순서 적응** — `rf_block_order_decide`: 기저가 CAGR ≥ 0.16 인데 Calmar < 0.64 면 위험 축 B5 를 2번째로(비중·유니버스는
   MDD 를 거의 안 움직인다 — 그 축을 먼저 돌면 출하되지 않는 구성을 최적화한다). 직전 블록 기전이 `next_block_design` 으로 다음
   블록을 지목하면 그것이 우선(`mechanism_pref`). 실측 09-04: 4 entry 전부 `B1>B5>B2>B3>B4`.
2. **블록 누적** — B2·B3·B5 는 직전까지 최고 구성을 바닥으로 자기 축만 바꾼다. 승계 arm 이 그 블록의 유니버스에서 불가(커버리지 < 80%)면
   시험 축이 아닌 승계 비중만 EW 로 강등해 측정한다(`rac_degrade_plan` · B2/B4 는 그대로 판정). 미측정 칸은 절약이 아니라 헌법 위반이다.
3. **기전 → 설계 → 집행 대조** — 블록 L-code 에 LLM 기전(`mechanism`)·처방(`next_block_actions`)·회피(`avoid`)·다음 블록 설계가
   실린다. 회피는 **측정 무효 사유**(편의·누출·PIT)만 집행하고 성과 사유는 기록만 한다(AX-000). 앞 블록 처방의 집행 여부는
   `rfbd_action_status` 가 재도출한다(executed/partial/ignored/no_design). 기전이 빈 블록은 다음 tick 에 백필(상한 2회).
4. **승격 사슬** — 소진 시 최고 등급 ≥ B 이고 **부모 최고 PORT_t 를 넘었을 때만** 승자 구성(팩터·비중·유니버스·오버레이)을 carry 로
   물려 새 25칸(깊이 ≤ 3, `rf_promote.R`). 승격 entry 의 B1 은 carry 팩터 위에 **더 얹는** 칸이라 단조 희석이 구조적으로 나온다
   (promo1: 2.171 → 1.011, Spearman −0.90) — 재고 항목. 실측 09-04 두 라운드: 최고 칸은 항상 첫 두 블록, 유니버스·오버레이는 LOO 순손실.
5. **구제** — 충실구현 F 라도 36M 롤링 창의 최근 통과율 ≥ 0.5(롤링점 ≥ 24)면 C 로 구제해 강화를 연다(`rg_rescue`; 회복→붕괴 이력은
   경고로 병기). 벤치 **실현 하락월** 기준 방어형(`ds_score`)은 등급 floor 미달이라도 2계층 풀 `defensive_specialist` 경로. 기저 게이트
   (`base_min_port_t`)는 구제된 entry 를 우회한다. 소급 09-04: F 74 → C · 방어형 182.
6. **결합 레인** — 논문 3편마다 검토(`combination_review_every`), 재료 풀에서 쌍을 골라 **LLM 이 두 논문을 읽고 설계한 결합 엔진**을
   충실구현 1회로 측정 → 기저 등급 → `_combo_rulefast` entry 로 같은 격자. 새 논문 소비가 아니므로 `count_paper=FALSE`.
7. **텔레그램** — 블록마다 본문(순위·궤적·LLM 기전·`이번 배치에서 알게 된 것` 요약) + 후속 전체판(판정·갈린 처치·위험·수익 교환·
   군집/단조·경계까지(롤링 창·방어형)·앞 처방 대비·미측정/강등·승격 사슬 — `rf_block_insights.R`, 규칙 기반) · B/A 팬파레 · 라운드
   종료 리뷰(블록별 궤적 · LOO · 무엇이 벽이었나). 계약은 `relaxed` · 미리보기는 `QVEST_TG_DRY_RUN=1`.

★2026-09-04 실사고 목록(재발 방지 검사 = `08_Tests/reinforcement/test_rf_lane_parity.R` · `test_rf_block_insights.R` ·
`test_rf_carry_degrade.R` · `test_rf_jlog_isolation.R` · `test_rf_summarize_once.R` · `08_Tests/ops/test_rp_count_paper.R`):
승격 B1 설계가 argv 상한에서 두 세대 연속 미기동 · 승격 carry 에 오버레이 누락 · 승계 비중이 소형주에서 불가 → 미측정 ·
기전 6/15 빈 채 재시도 없음 · `count_paper` 키 부재 = "세지 말라" · 검사 픽스처가 운영 로그 오염 · 미리보기가 실제 발송.

## 시도 1회의 절차 (원장 writer = `02_Infrastructure/reinforcement/reinforce_ledger.R`)

1. **교훈 주입 (착수 전 의무)** —
   `Rscript -e 'source("02_Infrastructure/reinforcement/reinforce_ledger.R"); print(rf_lessons_digest(<layer>, "<base_id>"))'`
   (직전 attempts 의 등급·교훈) + `Rscript 02_Infrastructure/tools/hypothesis_index.R lookup <축 키워드>`
   (죽은 구성 선례) + 해당 paper_key 의 기존 L-code. Axiom 전제는 에이전트 스폰 시
   `axiom_context_inject.sh` 훅이 자동 주입한다.
2. **아이디어 도출** — 논문의 후속 연구 절, 인용 논문, 또는 추론 가능한 확장.
   근거 논문 원문 링크는 **선택**이다 (도훈 2026-09-03 "강화에는 근거논문 필요없게 배선해").
   원장은 거부하지 않고 시도 레코드에 `evidence` = paper/method/none 을 남긴다.
   ★배경: 계열→논문 표가 8계열만 덮어 선정 풀 332종 중 91종(27%)이 미매핑이었고, 깊이 1 셀은
   거부되는데 깊이 2+ 는 **형제 계열 논문**으로 통과했다 — 시험 중인 축을 덮지 않는 근거로
   의무가 충족되던 상태였다. 지키는 척하는 게이트보다 없는 편이 정직하다.
   같은 뿌리 논문 3회 연속이면 경고(한 논문 매몰 금지 — 교차 논문 탐색).
3. **사전 등록** — `rf_append_attempt(layer, base_id, idea, keyword_axis, root_papers, wt_id)`.
   ★1계층 25회 게이트가 여기서 걸린다 (26번째 = stop + exhausted · 상한값 = 원장 파일 `max_attempts`).
4. **QEPM 실행 (1계층)** — `wt_create(wt_type="reinforcement")` (WT-R) →
   `Workflow(name="qvest-dossier-pipeline", args={wt_id, ...})` 또는 6-agent 수동 체인.
   제약 = **실투형 축**: long-only · ≤25종 · K200∪KQ150 · 15bps · Σw=1
   (★비중 상한 없음 — v10). alpha 가설 설계는 **전기간 데이터** 사용(lockbox 폐지).
   governor 는 부르지 않는다 — QEPM 종점 = essence 등급.
   (2계층은 run_wf_ensemble 재실측 — strategy-rotation SKILL 절차.)

   ★**단일 측정 원칙 (도훈 지시 2026-08-29 — arm 배터리 폐지)**:
   **한 시도 = 실투형 후보 하나.** alpha 구간에서 대비 arm 을 짓지 않는다 — 증분 대비 · 형태
   분해 셀 · 탐색 arm · 아티팩트 대조 · 무신호 대조를 **세션이 추가로 얹지 않는다**.
   판정은 arm 사이의 t 값이 아니라 **체인 종점의 essence 등급**이다.
   - 왜: 2026-08-29 1~3/20 이 arm 5·4·8 개를 짓고 등급은 0 건으로 끝났다. arm 배터리가
     체인의 입력이 아니라 **체인의 대체물**이 돼 있었다.
   - 사전등록은 그대로 남는다 — 다만 등록 대상이 "대비의 t 문턱" 이 아니라 **아이디어 · 논문
     근거 · 기대 등급**이다. 결과를 본 뒤 기대를 고쳐 쓰지 않는 규율은 불변이다.
   - ★**걷어내는 것은 세션이 얹던 배터리이지 계약이 요구하는 검사가 아니다.** `essence_score` ·
     forge · `audit_bt_result` · PIT 계약이 내부에서 부르는 검사는 그대로 돈다. 계약 게이트를
     끄는 것은 측정 우회이고 그건 강화가 아니라 지름길이다(quant-identity ③).
   - 유지되는 착수 관문 2종: **PIT C1~C15**(계층 무관 절대) · **사전 검정력**(논문 함의 효과크기
     대비 `ratio >= 0.15`, 미달이면 착수 중단·설계 변경 — 3/20 이 검정력 3~5% 로 돌았던 교훈).

   ★**착수 게이트 2축 — RETIRED (도훈 지시 2026-08-29 야간 '게이트 검증 완화'. 5회 연속 사전 중단을 낳아 폐기. 아래 규칙기반 고속 강화 §0 이 대체. 사료로만 보존)**:
   측정 예산을 쓰기 **전에** 두 축을 검사한다. 어느 하나라도 막히면 착수 중단·설계 변경이다.

   **축1 — 레그 배분**: 원문에서 **승자-레그 단독 효과크기**를 뽑아 필요 활성수익 대비 `ratio` 를 계산한다.
   - **롱숏 헤드라인을 앵커로 쓰는 것은 금지어**다. 실측 3건이 왜인지 말한다 — LS2000 효과 본체가
     패자·Year2+(승자 Year-1 은 +0.06~0.18%/월) · GH2004 자기금융 우위의 **76.6% 가 숏 레그** ·
     DGW2014 승자 몫 **25~52%**. 롱온리 ≤25종 envelope 이 수확할 몫이 문헌 전반에서 체계적으로 작다.
   - ★**승자-레그 수치를 뽑을 수 없으면 그 자체가 중단 사유**다. 외부 논문의 승자 몫을 곱해 만든 값은
     앵커가 아니라 추정이며 대용 불가(9/20: SS2007 은 Table 3~7 전부 W−L 이고 레그 수준·t 가 0건).
   - `ratio < 0.15` 면 중단. ★**표적은 앵커를 보기 전에 확정**한다 — 8/20 이 표적을 수준에서 지속으로
     앵커 계산 뒤에 바꾼 것을 자백하고 중단됐다. 유리한 앵커를 골라 진행하는 것은 게이트 우회다.

   **축2 — β 보상**: 원문이 **위험조정 수익(알파)을 한 번이라도 보고하는가**, 그리고 원문 모형이
   **합리(위험보상)** 인가 **행태(미스프라이싱)** 인가.
   - 원수익률만 보고하는 **합리 모형** 논문은 레그 배분이 아무리 유리해도 **β-통제 판정량에서 기대 수확 ~0** 이다.
     우리 판정량이 β-통제 PORT_t 이기 때문이며, 이는 축1 과 **독립인 차단 사유**다.
   - 실측(9/20 SS2007): 합리 실물옵션 계보 + 원문이 "승자가 패자보다 평균 요인노출이 높다" 고 명시 +
     **Table 4~7 위험조정 알파 0건** → ratio 가 통과했어도 막힌다.
   - **유형 분류(2026-08-29 판독분)**: 축1형(숏 편중) = LS2000 · GH2004 · DGW2014 / 축2형(β 보상) = SS2007.

   ★**초록 사전 스크린**: 초록만으로 축1/축2 가 판별되면 **등록도 하지 말고 걸러낸다**(에이전트 미사용).
   선례 — HLS2000 은 초록이 "효과가 과거 승자보다 과거 패자에서 훨씬 뚜렷하다" 고 적어 등록 전에 제외했다.
   ★**`hypothesis_index` 는 이름이 아니라 구성으로 조회**한다 — 9/20 이 M/B 를 lookup 했을 때 0건이었는데
   5/20(AMP2013)이 이미 측정한 셀이었다. 변수명이 아니라 어떤 원자료를 어떻게 조합했는지로 찾아야 중복이 잡힌다.

   ★**등급 경로 / 진단 경로 분리 (도훈 지시 2026-08-29 — QEPM 소요 간소화)**:
   라운드당 2~3시간·토큰 1M+ 이던 것을 **등급에 필요한 것**과 **진단에 필요한 것**으로 가른다.

   **등급 경로(기본 · 매 라운드)** — `alpha` → **[optimizer 조건부]** → `forge` → `essence_score`.
   등급의 숫자를 만드는 것은 이 경로뿐이다. 비중이 EW 로 확정되면 forge 가 재는 포트폴리오는
   alpha 의 `period_returns_production.csv` 와 **같다**.

   **진단 경로(조건부)** — `risk` 심층(EVT 꼬리 · 국면 이질성 · 용량 · 스트레스 에피소드 ·
   조작확인 · 집중 귀속)은 **등급 B 이상으로 살아남은 라운드** 또는 **도훈 지명** 라운드에만 돈다.
   ★대가를 알고 쓴다: 2026-08-29 세션에서 판정을 구한 발견 다수가 risk 구간 산물이었다
   (4/20 조작확인 t −14.37 로 negative 를 '미결' 에서 '실측 negative' 로 승격 · LW 3연속 붕괴 ·
   용량 상한 31억 · 저-β 를 위험축소로 오독하지 말라는 경고). 음성 라운드에서는 그것들이 안 나온다.

   **optimizer 조건부 실행 규칙**:
   - alpha 가 **book 기준 특이(비체계) 분산 비중**을 산출한다(전체 Σ 불필요 — 실현 수익 회귀로 족하다).
     추정 방법은 **사전 선언**하고 결과를 본 뒤 바꾸지 않는다.
   - **특이 비중 < 15% → EW 확정, 5종 비교 배터리 생략**하고 바로 forge. 사유를 산출물에 기록한다.
   - **≥ 15% → risk → optimizer** 정규 경로(사이징이 건드릴 표면적이 실재한다).
   - ★근거(2026-08-29 실측): 4/20 3.0%(walk-forward 5.7%) · 5/20 8.5% · 6/20 8.5% · 7/20 10.6% —
     **넷 다 문턱 아래**였고 5/20 optimizer 는 실제로 EW 를 골랐다(적격 3종 최대 격차 0.0091 ≪ band).
     **롱온리 top-25 · K200∪KQ150 envelope 에서는 비중 방법론이 거의 항상 무력**하다.
   - ★문턱은 **사전 규칙**이지 사후 선택이 아니다. 특이 비중이 높게 나왔는데 시간을 아끼려고
     생략하면 그건 간소화가 아니라 측정 우회다.

   ★**걷어내지 않는 것**: PIT C1~C15(계층 무관) · 사전 검정력(ratio ≥ 0.15) · `essence_score` ·
   `audit_bt_result` · forge 의 10-component 계약. 계약 게이트를 끄는 것은 지름길이다(quant-identity ③).

   ★**체인 완주 의무 (도훈 지시 2026-08-29 — 기각 사유에 의한 정지 폐지)**:
   **alpha 구간의 어떤 음성 판정도 체인을 멈추는 근거가 아니다.** 사전등록 1급 기각 ·
   역방향 powered null · **무신호 대조 구별불가** 중 무엇이 나와도 risk → optimizer →
   forge 를 끝까지 돌려 **essence 등급을 발행한다**. 종점은 등급이지 alpha 의 권고가 아니다.
   - 왜: 2026-08-29 강화 1~3/20 이 전부 alpha 에서 끊겨 **등급 0건**으로 마감됐다. 그 결과
     원장 grade 축에 A/B/C/F 대신 설명 문자열이 들어갔고, L-code 가 `record_type="performance"`
     로 못 들어가 `"process"` 로 적립돼 **등급 기반 집계·증류에서 성과 기록으로 잡히지 않는다**.
     시도 간 비교 자체가 불가능해진다.
   - ★**계기의 범위**: 무신호 대조의 결론은 `screen-tier 등재 불가`(measurement-graduation §3)
     이지 "forge 를 돌리지 말라" 가 아니다. 그것을 체인 정지 게이트로 쓰는 것은 **범위 밖 사용**이다.
     구별불가는 등급을 **낮게** 만들 뿐 등급 발행을 막지 않는다.
   - **리스크 오버레이 축은 예외 없이 전체 체인**: PIT `S0/S1 오버레이 금지` 때문에 오버레이
     적용은 alpha 에서 불가능하고 optimizer/forge 에서만 일어난다. alpha 에서 끊으면 그 라운드는
     **아무것도 측정하지 못한다**.
   - 기록은 지우지 않는다 — 폐지되는 것은 "그 판정을 근거로 체인을 멈추는 규칙" 이지 판정 수치가
     아니다. 음성 판정은 그대로 산출물·L-code 에 남고, 그 위에서 등급이 발행된다.
5. **결과 기록** — `rf_record_result(layer, base_id, n, grade, essence, artifacts, l_code, lessons)`.
6. **L-code 발행 (완결 후 의무)** — `emit_lcode(mode="reinforcement", ...)` (prefix RF).
   next_probe 연속성 계약(C/F ≥2건) 준수.
7. **텔레그램** — `tg_agent_brief(agent="AlphaSearch", title="[1계층·강화 n/25] {전략} — {축} (등급 {g})")`.
   2계층은 `[2계층·강화 n]`(무한 — 분모 없음). 양식 = qvest-telegram SKILL.
8. **분기** —
   - **Grade A** → Judge(PIT 전담) 스폰 (`.claude/agents/judge.md`) →
     `rf_record_judge(...)`. PASS → BOOK 등록 후보(도훈 confirm). FAIL → 등급 무효,
     수리 후 재측정(원장 자동 재활성화).
   - **미달** → 다음 시도(1단계부터). 1계층 25회 소진 → 큐의 다음 논문으로.
   - ★**등급 미발행은 분기 사유가 아니다** — 계약 미경유(NA)로 마감하는 것은 체인이 실제로
     막혔을 때(데이터 부재·계약 오류)뿐이며, 그 경우 **막힌 지점을 사유로 명시**한다.
     "신호가 음성이라 등급을 안 냈다" 는 허용되지 않는다(위 4단계 체인 완주 의무).

## §0.2 arm 생성 재귀 루프 (v10.2 2026-09-03 — B5 오버레이 축)

**왜**: 격자는 카탈로그에 있는 것만 재조합한다. 루프 안에 **새 기전을 카탈로그에 넣는 장치가 없었고**,
오버레이 10 arm 은 계열 라벨이 6종이었지만 행동은 전부 "총노출 스칼라 축소" 하나였다.
기전 지도로 재보니 B5 50 측정 중 **40이 이미 포화된 세 칸**에 몰려 있었다.

**한 바퀴**: 포화 감지 → 표적 칸 → `claude -p` 생성 → 오프라인 probe → 자동 등재 → 지도 갱신

| 단계 | 도구 | 성질 |
|---|---|---|
| 포화 감지 | `rf_mechanism_map.R` | (action × state) 14칸. `rf_next_target()` = 가장 덜 탐색된 미포화 칸. **전 칸 포화면 생성기를 안 부른다**(포화는 절단점) |
| 생성 | `ops/rf_overlay_propose.sh` | tick 안. 하루 1건. claim·타임아웃·auth 처리는 충실구현 레인 규약 |
| 검증 | `overlay_probe.R` | 백테 **0 소모**. 5축: 함수계약·측정누출·리터럴문턱·미래참조(`fwd[t]` 섭동 불변)·처치전달 |
| 등재 | `ops/rf_overlay_admit_cli.R` | **R 이 등재한다.** LLM 은 카탈로그를 못 쓴다 |
| 원장 | `06_Registry/overlay_arm_ledger.jsonl` | 측정 **전** 방출 기록. `selection_type` 은 k 에서 구조적으로 파생(LLM 이 선언 못 함) |

**생성기가 쓰는 것 2개뿐**: `overlay_arms/<kind>.R`(함수 하나) + `<kind>.arm.json`(id·family·basis).
`--add-dir` 는 그 디렉터리 하나다.

**★생성기는 성과를 보지 않는다** — 이게 구조로 강제된다:
① 프롬프트의 기전 지도는 측정 횟수·포화 여부만(`rf_target_brief` 축약본, 성과 수치 0)
② 세션은 `QVEST_ARM_GEN=1` 로 돌고 **`arm_gen_read_guard.sh`** 가 원장·권위재측정·지도 파일 Read/Grep 을 막는다
   (`--add-dir` 는 쓰기만 가두고 읽기는 안 가둔다 — 이 구멍을 닫는 것이 훅의 존재 이유다)
③ 방출은 측정 전에 원장에 남아 패자를 숨길 수 없다

**arm 계약** (`dbeta_tilt.R` 가 기준 본보기):
```r
overlay_expo_<kind> <- function(H, t, ctx)   # -> 스칼라 e  또는  data.table(Ticker, e)
```
- `H` = 확장창(t 행까지). **`H$fwd` 의 t 행은 미실현 — 읽으면 probe 가 잡는다**
- `ctx$hold` = 보유 종목 확장창 상태 `Ticker·beta·dbeta·ovol·bcorr·n_obs`
- 임의 상수 문턱 금지(quantile/median/ecdf 로 그 시점 데이터에서 추정) · 추정 불가면 `e <- 1`
- action 이 `cross_sectional` 이면 **반드시 종목별 표**를 낼 것 — 스칼라만 내면 등재 거부

**실측 근거**: 같은 기저·같은 위기에서 스칼라 arm 은 평균노출 0.749·완전현금 15/144개월,
종목별 arm 은 0.887·**0/144개월**(날짜 안 비중 sd 0.0148). 상방을 덜 버리면서 축소분을
하방 기여가 큰 종목에 몰아준다 — 대칭 축소가 Calmar 를 못 올리던 구조적 한계를 깨는 축이다.

## 결합 검토 (1계층 — 논문 3편마다 의무)

원장이 논문 3편 소비 시점을 알린다. Q-Lead 는 **착수 여부와 무관하게** 논문 간
아이디어 결합 기회를 검토하고 `rf_record_combination_review(reviewed_papers,
verdict, note)` 로 기록한다. 결합 착수 시 = `keyword_axis="combination"` +
root_papers 복수로 새 시도.

## 경계 (HARD)

- **Q-Lead 는 오케스트레이션만** — 자체 리서치·자체 백테·수치 산출 금지.
  측정은 QEPM 체인(AX-008: 산출은 Forge)이 한다.
- 하드코딩 금지 — 모든 수치(파라미터·문턱·비중)는 논문 근거 또는 데이터 추정.
- PIT C1~C15 계층 무관 불변. 등급 권위 = essence_score 하나.
- 구 기계 사다리(`reinforce_ladder.R`)·구 원장(`reinforce_ladder_ledger.json`)은
  read-only 사료 — 소비·재기동 금지 (`QVEST_LADDER_NORUN` 문서 잔재 무시).
- 페르소나 = `02_Infrastructure/docs/rules/quant-identity.md` (최정상급 퀀트 ·
  방법론을 향한 냉소 · 최신 수리통계/ML 적극 · 리서치는 지난하다).

## 참조

`.claude/rules/lean-loop.md`(1계층 룰) · `.claude/skills/strategy-rotation/SKILL.md`(2계층) ·
`.claude/agents/judge.md`(PIT 검증) · `02_Infrastructure/book/book_registry.R`(BOOK)
