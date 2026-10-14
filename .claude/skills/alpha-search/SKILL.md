---
name: alpha-search
description: 1계층 알파 서칭 (v10.01) — 논문 1편을 완전 충실구현(롱숏·종목수·비중 논문 그대로, 유니버스·기간만 측정 축 — 현행 전 종목 + 위생 · 2000~)으로 검증하고 권위 등급 산출, 2차트·성과요약 텔레그램 발송. A 미달 → 재료 등록(행동 카드 · 리서치 프로그램 재료 큐 · v10.01 고정 격자 강화 퇴역) / A → 러너가 A 자격 관문 rf_a_eligibility(충실구현 어댑터 · P0-13)를 태워 통과 = 산출 judge_request.eligible.json(Judge(PIT) 트리거) · 보류 = judge_request.held.json(사유 코드 · 트리거 아님) → [1계층] A 후보 보고. 의미있는 실패만 L-code 적립.
---

# 1계층 알파 서칭 (v10 2026-08-29 — 완전 충실구현)

논문 한 편을 검증하는 1계층 기본 단위(QEPM 미사용 — QEPM 은 강화 프로세스의 도구).
러너 = **`run_paper_replication()`** (구 run_alpha_search 는 실투형 측정 도구로 존치 —
강화·재측정 경로에서 사용). 페르소나 = `quant-identity.md`.

## ★ 제1원칙 — 완전 충실구현 (도훈 2026-08-29: "논문의 충실구현을 제1목적으로 함")

1. **명시값 전부 복제**: 시그널 정의(회귀기간·skip·표준화·랭킹) · 비중 방식 · **종목수
   (상한 없음 — 데실 100종 그대로)** · **롱숏 그대로**(long-leg 사상 폐지) · 리밸 주기.
2. **유일한 변경 = 유니버스·기간 = 측정 축**(정본 `constraint_defaults.json::measurement_axis` · 현행 epoch `all_hyg_2000_v1`
   = 전 종목 + 위생 · 2000-01-01~ · 2026-10-13 전환 · 구 `K200_KQ150` · 2005~). 러너가 적재 직후 K200/KQ150 플래그를
   위생 멤버십(PIT 시변)으로 바꿔 끼우고 시작일을 `.RP_START_DATE` 로 준다 — 엔진은 플래그로 자르고 시작일 리터럴을 쓰지 않으며,
   러너에 `universe`·`start_date` 를 넘기지 않는다(넘기면 그 값이 측정 축을 덮는다). 등급은 같은 epoch 안에서만 비교한다.
3. 유동성 필터 = 논문 우선(`paper_faithful` — 논문 무명시면 무필터). LiqPass 미적용.
4. 비용 = **이중 측정**: 논문 명시값(무명시 = 0/gross)으로 충실구현 성과 병기 +
   **등급은 15bps 순비용 판**(essence 문턱 15bps 보정 — gross 등급은 인플레).
5. **미명시 값만 보충**하고 보충 사실을 명시. PIT C1~C15 는 절대(t-1 규약).
6. **근거 논문 원문 링크 필수** — `source_paper=list(url=...)` 없으면 러너가 거부.
★구 E-5(25종 절단·L/S long-leg 사상)는 **충실구현 단계에서 폐지** — 실투형 축(long-only·
≤25종)은 처방·조립 단계부터 적용된다(`.claude/rules/lean-loop.md` 축 · v10.01).

## 선례 조회 (advisory)

- `hypothesis_index` 자동 조회 1줄(차단 아님 — 히트 시 차별점 1줄 보고).
- `alpha_frontier_queue.json` 의 `parked_reason=dohoon_decision` 항목 임의 착수 금지.
- (v10.01) 원장 L1 은 충실구현 소비 기록이다 — active entry 우선 규칙은 고정 격자 강화와 함께 퇴역했다. 착수 순서 = 리서치 프로그램 등록부(lean-loop 입력).

## 동작 절차 (4-step)

### 1. 논문 intake
`mcp__arxiv__*` / `mcp__jina__read_url` 로 시그널·구성·기간·저자 주장 성과 추출.
`strategy_name` + `strategy_idea` + `source_paper(url, paper_key)` 확정.

### 2. engine 작성
`FACTORS(Date, Ticker, Score)` 또는 논문 비중 직접 산출 시 `PORTFOLIO(Date, Ticker,
Weight[, Leg])`. **PIT 필수**: 동일시점 순환참조 금지, 과거 윈도우만, 재무 지연(연간
익년 3/31·분기 45일+). 위반 시 중단.

### 3. 실행 (충실구현)
**선확인(측정 직전)**: `bash 02_Infrastructure/ops/refresh_barrier.sh status` 가 `state=free` 가 아니면 측정 보류 — 잠금 해제 후 재시도(`daily_refresh` 창에선 RAWDATA K200/KQ150 이 NA 라 에러 없이 틀린 등급 · 러너는 배리어를 안 본다 — 무인 레인만 본다).
```r
source("02_Infrastructure/alpha_search/run_paper_replication.R")
run_paper_replication(
  strategy_name = "전략명", strategy_idea = "한 줄 아이디어",
  factor_engine_path = "<engine.R>",
  portfolio_spec = list(construction = "decile_long_short",  # 논문 그대로
                        weighting = "ew", long_frac = 0.10,   # 논문값
                        rebalance = "monthly"),
  source_paper = list(url = "https://...", paper_key = "axv:...", title = "..."),
  commission_paper = NULL)   # NULL = 논문 무명시 → gross 병기, 등급은 15bps 판
```
경로: 데이터(전기간 — lockbox 폐지) → engine → 유니버스 치환 → **PIT(중단 게이트)** →
`run_replication_simulation`(비중 기반·롱숏·상한 없음) → bt_result 계약 → essence 등급
(`authoritative_remeasure.json`) → 2차트 → 텔레그램 `[1계층]` → L-code(`paper_replication`)
→ 분기(A → A 자격 관문 `rf_a_eligibility`(충실구현 어댑터 · P0-13): 통과 = 산출물 `judge_request.eligible.json`(Judge 트리거) · 보류 = `judge_request.held.json`(사유 코드 · 요청 미발행) / 미달 → 재료 등록(검증기가 행동 카드를 쓰고 엔진을 리서치 프로그램 재료 큐에 넣는다 · 처방은 research-program 라운드 · v10.01 고정 격자 강화 퇴역)).

### 4. 결과 해석 + 분기
- 등급·수치는 **`authoritative_remeasure.json` 값만 인용**(권위 = essence). 손계산 금지.
  `hurdle` 등급 = 진단(proxy) — 인용 금지. 등급 = 등급 v3(S · 하한 · 위기 복원력 노치 — CLAUDE.md 등급 절) · MDD 직접 문턱 없음(Calmar 와 CR 노치로만 닿는다) · 구 5조건 판정 `grade_v921` 은 인용 금지.
- 보고 3줄(lean-loop 양식): ①등급·CAGR·SR·MDD·n_max(+논문 기준 병기) ②기전 1줄 ③다음.
- **Grade A** → 러너 §11 이 A 자격 관문(`rf_a_eligibility` · 충실구현 어댑터 · P0-13)을 태운 결과를 읽는다(반환 `a_gate` · 산출 디렉터리). 통과 = 산출물 `judge_request.eligible.json`(`status=pending` = Judge 트리거) → Judge(PIT 전담) → PASS → BOOK 후보(도훈 confirm) · 보류 = 산출물 `judge_request.held.json`(사유 코드 · 요청 미발행 · 등급 불변) → `[1계층]` A 후보(보류 사유 병기)로 도훈 보고. 정본 = `.claude/agents/judge.md` §스폰 조건.
- **미달** → 재료 등록(검증기가 행동 카드를 쓰고 엔진을 리서치 프로그램 재료 큐에 넣는다 · 처방은 research-program 라운드 · v10.01 고정 격자 강화 퇴역). 보고 = `prep_send`(qvest-telegram SKILL §0).

### 5. 감사 상충 — 세션 판정 (2026-10-14 · 1810.08384 실측)
재구현 판의 재감사가 앞 회차 지적을 **원문 근거로 번복**(`prior_review` overturned)했는데 판정이 misdeclared 이면, 검증기는 그 기각을 구현 실패(`proceed_suspect`)로 세지 않는다.
대신 그 논문만 보류한다. 보류 표식은 셋이다: 스킵리스트 `held_audit_conflict`, 요청 `held_audit_conflict`, `<wdir>/audit_conflict.json`. 소비와 재료 등록은 하지 않고, 레인은 다음 논문으로 간다.
- **판정 = 원문으로만**: 어느 회차가 원문과 맞는지만 가린다(성과를 보지 않는다). 대조는 격리 읽기 전용 에이전트에 맡겨도 된다. `audit_conflict.json` 에 번복 항목 · 근거 · 두 회차 피드백 전문이 있다.
- **앞 회차가 오독이었다(재구현이 틀린 지적을 따랐다)**:
  - `06_Registry/reimplement_queue.json` 에 reserved 항목을 둔다. `audit_feedback` 은 판정한 지적만 담고, `audit_retries` 는 1, `decided_by` 를 기재한다.
  - 스킵리스트 항목은 `status=revoked` 로 바꾼다.
  - 다음 발행이 재구현을 집는다.
- **재감사의 번복이 오독이었다 · 남은 지적이 경미하다**:
  - 요청 슬롯이 비었을 때 그 논문 요청을 `status=pending` · `failure=audit_ruled` · `audit_ruling={action: proceed|proceed_suspect, by, decision, feedback}` 로 쓴다.
  - 스킵리스트 항목은 `revoked` 로 바꾼다.
  - 레인은 에이전트 없이 검증기만 돈다. 감사 관문(`rf_audit_gate(ruling=)`)이 감사를 다시 사지 않고 남은 감사 파일로 처분한다.
- 판정은 decision_register 에 남긴다. 재감사 지시문 = 축 프롬프트의 '재감사다' 절(`rf_fidelity_fanout.sh`), 재구현 반박 통로 = FIDELITY `audit_disputes`.

## L-code 적립 (PASS + 의미있는 실패만)

- `stage_artifacts/l_code/paper_replication/`, `research_mode="paper_replication"`.
- 의미있는 실패 = 기전이 특정되는 실패. 연속성 계약: `next_probes` ≥2(C/F) — WARN 후 발행.
- `lesson_text` 에 논문기준 vs 15bps 순 성과 격차 명시(충실구현의 핵심 정보).

## 제약

- 제1원칙 준수(임의 변형 = 검증 무효 — 시스템 관습으로 바꾸면 별개 전략).
- 충실구현 단계에서 QEPM 이행 금지(강화부터). **WT-id 사용 금지.**
- 텔레그램 직접 호출 금지 — `tg_agent_brief()`만(러너가 처리). 표제 = `[1계층] …`.
- 외부 parquet/cache 의존 팩터 = `detect_lookahead` 사각 — 생성 코드 forward-label sanity
  별도 보증(python-policy.md). 러너 `[PIT-WARN]` 출력.
