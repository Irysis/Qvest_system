---
name: alpha-search
description: 알파 서칭 모드 — 논문/가설을 빠르게 백테스트 검증하고 전략별 2차트(Equity Curve vs BM + 연간수익률 vs BM)·전략아이디어·성과요약을 텔레그램 발송. PASS/의미있는 실패만 모드별 L-code 적립 → Axiom 자가발전. QEPM 풀파이프라인 미사용(Risk/Optimizer/Forge/Judge/Governor 미호출, Codex/WorkTask/certificate 없음). Grade A는 PG 편입 권고만(book_state는 수동 승인).
---

# 알파 서칭 모드 (alpha-search)

Qvest 초기 모델처럼 **논문 한 편을 빠르게 검증**하는 가벼운 독립 루프.
무거운 QEPM 6-에이전트 파이프라인 대신, 알파 단독으로 백테스트 → 리포트 → 교훈 적립.

## 동작 절차 (4-step)

### 1. 가설 intake
- 입력이 논문 URL이면 `mcp__jina__read_url` / `mcp__arxiv__*` / `mcp__jina__search_arxiv|search_ssrn`로 핵심 시그널·구성·기간을 추출.
- 입력이 가설 문장이면 그대로 사용.
- 한 문장 `strategy_idea`(전략 아이디어 요약)와 `strategy_name`(STR명) 확정.

### 2. factor_engine.R 작성 (PIT 준수)
- 템플릿 복사: `02_Infrastructure/alpha_search/factor_engine_template.R`.
- 가설의 "팩터 정의" 블록만 교체 → `FACTORS(Date, Ticker, Score)` 산출.
- **PIT 필수**: 동일시점 순환참조 금지, 과거 윈도우(shift/rolling)만, 재무 지연(연간→5월/분기→45일). `detect_lookahead`가 검사하며 위반 시 백테스트 중단.

### 3. 실행
```r
source("02_Infrastructure/alpha_search/run_alpha_search.R")
run_alpha_search(
  strategy_name      = "STR명",
  strategy_idea      = "한 줄 전략 아이디어",
  factor_engine_path = "<작성한 factor_engine.R 절대경로>",
  n_holdings = 20, weight_method = "ivol", commission = 0.0015,
  start_date = "2010-01-01",  # 시그널 시작일. 빠른 검증 권장(전기간 NULL은 36년 풀시뮬로 매우 느림)
  universe = "ALL",           # "ALL"=전종목(유동성 2e8만) / "KR_TOP500"=유동성통과 중 시총 top500(PIT-safe)
  factor_analysis = TRUE      # FF3/FF5/Carhart 알파 + Fama-MacBeth 회귀 동시 산출(텔레그램 [팩터분석] 별도 발송)
)
```
- **start_date 권장**: 전기간(`NULL`)은 1990~현재 풀시뮬이라 수십 분 소요. "빠른 검증"에는 데이터가 충실한 구간(예 `"2005-01-01"`/`"2010-01-01"`)을 주면 수 분 내 완료. RAWDATA는 전체 유지되고 FACTORS 시그널만 제한된다.
- 발송 없이 양식만 점검하려면 `send_telegram=TRUE, tg_dry_run=TRUE`.
- 내부: `load_rawdata` → 유동성필터 → universe필터(ALL/KR_TOP500) → PIT검증 → `run_monthly_simulation` → `generate_charts`(equity_curve.png + annual_returns.png) → `run_hurdle_gate`(등급·점수·지표) → (factor_analysis 시) `run_analysis`(FF3/FF5/Carhart 알파 + Fama-MacBeth) → 텔레그램 → 조건부 L-code → Grade A PG 권고.

### 4. 결과 해석
- 반환 `list(strategy_id, grade, score, pass, notable, excess_cagr, out_dir, charts, l_code)`.
- 텔레그램은 `tg_agent_brief(agent="AlphaSearch")` 단일 진입점 — 헤더 `🔭 AlphaSearch · 제목`이 모드 배지.

## 스코어링
- 별도 임계값 신설 금지. 기존 `run_hurdle_gate()` 재사용 → `grade`(A/B/C/F) + `score`(0–100) + `verdict$metrics`.
- 성과요약 텔레그램 kv에 스코어링 지표 노출: 등급·종합점수·샤프지수·연복리수익률·최대낙폭·칼마지수·정보비율·회전율·벤치마크상관·감가샤프지수·초과수익.
- `factor_analysis=TRUE`(기본)면 별도 `[팩터분석]` 메시지로 FF3/FF5/Carhart4 대비 알파(연%·t값·유의성) + Fama-MacBeth + IC 발송(`analysis_multifactor.csv` 경유). 성과요약 kv에도 "팩터모델 대비 알파(3·4·5팩터)" 섹션 추가.

## L-code 적립 (PASS + 의미있는 실패만)
- 모드별 디렉터리 `stage_artifacts/l_code/alpha_search/`, `research_mode="alpha_search"`.
- 성공: "무엇이 통했나". 실패: "왜 안 통했나" + `VALIDATED_HARD_FAIL` 태그(역패턴 마이너 입력).
- 단순 노이즈(미세 변형·사소 음수알파)는 미생성.
- 작성 직후 harvester+cluster 자동 호출(자가발전).

## PG 편입 (자동 판정 + 수동 최종 편입)
- Grade A → `STR_AS_` 등록 + `pg1_admission_with_book_context`로 편입 **권고**(ADMIT/DEFER + book ΔIR).
- **`book_state.json`은 코드가 쓰지 않음** — 실제 편입은 도훈 수동 승인(기존 안전장치 준수).

## 제약 (반드시 준수)
- **QEPM 이행 금지**: Risk/Optimizer/Forge/Judge/Governor 미호출. Codex Critic Round 없음. WorkTask status 전이/`*_package.json`·`*_verdict.json` 산출 없음. certificate 의존 없음.
- **WT-id 사용 금지** (worktask_sequence_enforcer 등 Hook 오발동 회피).
- 텔레그램 직접 호출 금지 — `tg_agent_brief()`만(run_alpha_search 내부에서 처리).
- 백테스트 PIT 준수 필수.
- **외부 데이터 의존 팩터(fe_ml 등 parquet/cache 입력) PIT 책임**: `detect_lookahead` 정적분석은 factor_engine.R **텍스트만** 검사하므로, 외부 생성 파이프라인(예 `ml_momentum_ensemble.py`)의 forward-label lookahead를 **검사하지 못한다**(13줄짜리 fe_ml.R은 무조건 CLEAN 통과). 생성 `.py/.R`가 forward-label sanity(COVID 등 bear date 음수 검증 / `validate_label_direction()` / `bear_date_audit.R` 또는 동등 self-assert)를 통과하도록 **별도 보증 필수** (python-policy.md 언어무관 의무, Cycle 50 교훈). run_alpha_search는 외부 의존 감지 시 `[PIT-WARN]`을 출력한다.
