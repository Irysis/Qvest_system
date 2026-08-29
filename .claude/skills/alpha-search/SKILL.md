---
name: alpha-search
description: 1계층 알파 서칭 (v10) — 논문 1편을 완전 충실구현(롱숏·종목수·비중 논문 그대로, 유니버스만 K200∪KQ150)으로 검증하고 권위 등급 산출, 2차트·성과요약 텔레그램 발송. A 미달 → 강화 원장 open / A → Judge(PIT). 의미있는 실패만 L-code 적립.
---

# 1계층 알파 서칭 (v10 2026-08-29 — 완전 충실구현)

논문 한 편을 검증하는 1계층 기본 단위(QEPM 미사용 — QEPM 은 강화 프로세스의 도구).
러너 = **`run_paper_replication()`** (구 run_alpha_search 는 실투형 측정 도구로 존치 —
강화·재측정 경로에서 사용). 페르소나 = `quant-identity.md`.

## ★ 제1원칙 — 완전 충실구현 (도훈 2026-08-29: "논문의 충실구현을 제1목적으로 함")

1. **명시값 전부 복제**: 시그널 정의(회귀기간·skip·표준화·랭킹) · 비중 방식 · **종목수
   (상한 없음 — 데실 100종 그대로)** · **롱숏 그대로**(long-leg 사상 폐지) · 리밸 주기.
2. **유일한 변경 = 유니버스** `K200_KQ150`(PIT 시변 멤버십 치환).
3. 유동성 필터 = 논문 우선(`paper_faithful` — 논문 무명시면 무필터). LiqPass 미적용.
4. 비용 = **이중 측정**: 논문 명시값(무명시 = 0/gross)으로 충실구현 성과 병기 +
   **등급은 15bps 순비용 판**(essence 문턱 15bps 보정 — gross 등급은 인플레).
5. **미명시 값만 보충**하고 보충 사실을 명시. PIT C1~C15 는 절대(t-1 규약).
6. **근거 논문 원문 링크 필수** — `source_paper=list(url=...)` 없으면 러너가 거부.
★구 E-5(25종 절단·L/S long-leg 사상)는 **충실구현 단계에서 폐지** — 실투형 축(long-only·
≤25종)은 강화 프로세스부터 적용된다(`.claude/rules/lean-loop.md` 축 2층).

## 선례 조회 (advisory)

- `hypothesis_index` 자동 조회 1줄(차단 아님 — 히트 시 차별점 1줄 보고).
- `alpha_frontier_queue.json` 의 `parked_reason=dohoon_decision` 항목 임의 착수 금지.
- 강화 원장 L1 에 active entry 가 있으면 그 강화가 새 논문보다 우선.

## 동작 절차 (4-step)

### 1. 논문 intake
`mcp__arxiv__*` / `mcp__jina__read_url` 로 시그널·구성·기간·저자 주장 성과 추출.
`strategy_name` + `strategy_idea` + `source_paper(url, paper_key)` 확정.

### 2. engine 작성
`FACTORS(Date, Ticker, Score)` 또는 논문 비중 직접 산출 시 `PORTFOLIO(Date, Ticker,
Weight[, Leg])`. **PIT 필수**: 동일시점 순환참조 금지, 과거 윈도우만, 재무 지연(연간
익년 3/31·분기 45일+). 위반 시 중단.

### 3. 실행 (충실구현)
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
→ 분기(A → `judge_request.json` / 미달 → 강화 원장 open).

### 4. 결과 해석 + 분기
- 등급·수치는 **`authoritative_remeasure.json` 값만 인용**(권위 = essence). 손계산 금지.
  `hurdle` 등급 = 진단(proxy) — 인용 금지. MDD 는 등급을 접지 않는다(Calmar 하나).
- 보고 3줄(lean-loop 양식): ①등급·CAGR·SR·MDD·n_max(+논문 기준 병기) ②기전 1줄 ③다음.
- **Grade A** → Judge(PIT 전담) 스폰 → PASS → BOOK 후보(도훈 confirm).
- **미달** → `Skill(reinforce)` — 원장 n/20, 축 = 멀티팩터/비중방법론/리스크오버레이/결합.

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
