---
name: alpha-search
description: 알파 서칭 모드 — 논문/가설 1편을 lean 백테로 검증하고 2차트·성과요약 텔레그램 발송, 의미있는 실패만 L-code 적립.
---

# 알파 서칭 모드 (alpha-search)

논문 한 편을 빠르게 검증하는 독립 루프(QEPM 6-에이전트 미사용). 기본 = **lean 라운드**(`deep=FALSE`) — 측정·판정·교훈까지만.

## ★ 제1원칙 — 논문 완전 복제 (6불릿)

1. **명시값 그대로 복제**: 팩터 구성(회귀기간·skip·표준화·랭킹), 비중 방식, 종목수, 리밸 주기.
2. **L/S는 long-leg 사상**: 롱숏 논문도 long-only(스케일링 λ∈[0,1], 무레버리지). L/S 수치는 판정 근거 금지(진단 라벨만).
3. **유니버스 고정** `universe="K200_KQ150"`(K200∪KQ150, PIT 시변). 논문 유니버스는 이 범위로 치환.
4. **기간 고정** `start_date="2005-01-01"`. 단축·전기간은 진단 라벨용, 판정 근거 아님.
5. **임의 변형 금지**: 종목수·비중을 시스템 관습(top20 등)으로 바꾸면 별개 전략 = 검증 무효.
6. **미명시 값만 시스템 표준**(PIT C1~C15, 15bps, 유동성 2e8) — 보충한 것을 명시.

★**고정 축 우선**(2026-08-23 도훈 결정 E-5, 구 "논문 우선" 폐기). 논문 종목수가 25를 넘으면(decile·quintile 등)
**상위 25로 절단**하고, 절단 사실과 **절단 전 N**을 `paper_assumption_broken` 에 적는다.
강제 지점은 규범이 아니라 코드다 — `backtest_harness.R` 의 `n_hold_eff <- min(n_hold_eff, 25L)` 캡(물리)
+ `contracts/audit_bt_result.R::holdings_cap` 검사(계약 FAIL). 구 규범으로 돌린 런은 계약이 FAIL 로 잡는다.
근거 사건 = `02_Infrastructure/docs/CHANGELOG_constitution.md` 아카이브 절 + 2026-08-23 실측(리밸일별 distinct ticker 최대 167종).

## 선례 조회 (advisory)

- 러너가 `hypothesis_index` 를 자동 조회해 `[hypothesis_index] 선례 N건 …` 1줄을 찍는다. **차단 아님** — 히트가 있으면 차별점을 1줄 보고.
- `alpha_frontier_queue.json` 의 `parked_reason=dohoon_decision`/`dohoon_data_work` 항목은 임의 착수 금지.

## 동작 절차 (4-step)

### 1. 가설 intake
논문 URL이면 `mcp__arxiv__*` / `mcp__jina__read_url` 로 시그널·구성·기간 추출(MCP 불가 시 `alpha_search/paper_extract.py`). 가설 문장이면 그대로. `strategy_name` + `strategy_idea` 확정.

### 2. factor_engine.R 작성
`02_Infrastructure/alpha_search/factor_engine_template.R` 복사 → "팩터 정의" 블록만 교체 → `FACTORS(Date, Ticker, Score)`.
**PIT 필수**: 동일시점 순환참조 금지, 과거 윈도우(shift/rolling)만, 재무 지연(연간 익년 3/31·분기 45일+). 위반 시 백테 중단.

### 3. 실행 (lean)
```r
source("02_Infrastructure/alpha_search/run_alpha_search.R")
run_alpha_search(
  strategy_name = "STR명", strategy_idea = "한 줄 아이디어",
  factor_engine_path = "<factor_engine.R 경로>",
  n_holdings = 20, weight_method = "equal",   # ★논문 명시값으로 대체
  start_date = "2005-01-01", universe = "K200_KQ150",
  source_paper = "<논문 식별자>", paper_assumption_broken = NULL,
  deep = FALSE)
```
lean 경로: 데이터·유니버스 → 선례 advisory → **PIT 검증(위반 시 중단)** → `run_monthly_simulation` → bt_result 계약 → 2차트 → `run_hurdle_gate` → FMT 판정 → manifest → 텔레그램 1회 → 조건부 L-code(+harvester 비동기).
`deep=TRUE` 는 **지명 후보에만**(자본 층 입구) — `register_module` · FF3/FF5/Carhart+FM · 권위 재측정(essence/PORT_t) · improvement_potential 추가.

### 4. 결과 해석
- 반환 `list(strategy_id, grade, score, pass, notable, excess_cagr, out_dir, charts, l_code, ...)`.
- 성과 수치는 **`hurdle_result.json` 값만 인용**(proxy 라벨). 손계산·재구성 금지.
- 보고 3줄: ①등급·점수·초과CAGR ②탈락축(FMT/fail_reasons) ③다음 probe 2건.

## 스코어링
- 별도 임계값 신설 금지 — `run_hurdle_gate()` 재사용: `grade`(A/B/C/F) + `score`(0–100) + `verdict$metrics`.
- 텔레그램 kv = 등급·점수·샤프·연복리·최대낙폭·칼마·정보비율·회전율·벤치상관·초과수익.

## L-code 적립 (PASS + 의미있는 실패만)
- `stage_artifacts/l_code/alpha_search/`, `research_mode="alpha_search"`.
- **의미있는 실패** = clean-PIT F 중 **탈락축이 잡힌 것**(FMT ≥1 또는 `fail_reasons` ≥1). 축 없는 F는 미적립.
- **연속성 계약은 여기 한 곳**: `next_probes` ≥2(C/F) + `live_trigger`. 미충족이면 `[L-CODE WARN]` 후 발행 — 차단 아님.
- `lesson_text` 꼬리 = `사유: <축>; 논문 가정 대비: <깨진 가정>`.

## PG 편입
- Grade A → `STR_AS_` 등록 + `pg1_admission_with_book_context` 편입 **권고**(ADMIT/DEFER + book ΔIR).
- **`book_state.json`은 코드가 쓰지 않는다** — 실제 편입은 도훈 수동 승인.

## 제약
- 제1원칙 준수(임의 변형 = 검증 무효).
- QEPM 이행 금지: Risk/Optimizer/Forge/Judge/Governor 미호출, WorkTask 전이·`*_package.json` 없음.
- **WT-id 사용 금지**(hook 오발동 회피).
- 텔레그램 직접 호출 금지 — `tg_agent_brief()`만(러너가 처리).
- 외부 parquet/cache 의존 팩터는 `detect_lookahead` 사각 — 생성 코드의 forward-label sanity를 별도 보증(python-policy.md). 러너가 `[PIT-WARN]` 출력.
