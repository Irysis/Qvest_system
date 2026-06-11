---
name: alpha-search
description: 알파 서칭 모드 — 논문/가설을 빠르게 백테스트 검증하고 전략별 2차트(Equity Curve vs BM + 연간수익률 vs BM)·전략아이디어·성과요약을 텔레그램 발송. PASS/의미있는 실패만 모드별 L-code 적립 → Axiom 자가발전. QEPM 풀파이프라인 미사용(Risk/Optimizer/Forge/Judge/Governor 미호출, Codex/WorkTask/certificate 없음). Grade A는 PG 편입 권고만(book_state는 수동 승인).
---

# 알파 서칭 모드 (alpha-search)

Qvest 초기 모델처럼 **논문 한 편을 빠르게 검증**하는 가벼운 독립 루프.
무거운 QEPM 6-에이전트 파이프라인 대신, 알파 단독으로 백테스트 → 리포트 → 교훈 적립.

## ★ 제1원칙 — 논문 완전 복제 (Faithful Full Replication)

**알파 서칭 모드는 논문 완전 복제가 원칙이다** (도훈 mandate 2026-06-05). 논문/가설의 전략을 **원본 그대로** 재현해 검증하는 것이 본 모드의 목적이며, 재현 충실도 자체가 검증의 전제다.

- **각종 파라미터를 논문 명시값 그대로 복제**한다:
  - **팩터 구성 방법론**: 회귀 기간(예 36m)·skip(예 11-1, 직전 1개월 제외)·표준화(잔차 σ 분모)·윈도우·랭킹 방식.
  - **포트폴리오 구성 비중**: equal-weight / value-weight / decile / signal-proportional 등 — **논문이 쓴 방식 그대로**.
  - **종목수 · 리밸 주기**: 논문대로(decile이면 decile, 10종목이면 10종목).
  - **★ long/short 구조는 예외 — 롱숏 불허** (도훈 mandate 2026-06-11, 기존 "L/S 논문대로" 조항 대체): 논문이 L/S여도 **검증 단계 포함 전면 long-only로 사상**(long leg 기반, 스케일링류는 λ∈[0,1] 무레버리지 캡). 사상 사실과 논문 원형과의 차이를 명시 보고. L/S 수치는 판정 근거로 사용 금지(산출했다면 진단 참고 라벨만). 근거 사건: BSC(2015) faithful L/S 검증(STR_AS_BSC_20260611_153021) 직후 도훈 정정.
- **유니버스 = 고정 K200∪KQ150** (도훈 mandate 2026-06-05): 외국 논문 유니버스(US NYSE/Russell/S&P)는 KR 직접 적용 불가(데이터 부재·시장구조 차이) → **모든 검증을 KOSPI200∪KOSDAQ150 실투 유니버스로 고정**(`universe="K200_KQ150"`, PIT 시변 멤버십). 소형주 논문도 이 범위로 좁혀 검증(size effect 알파는 약화될 수 있으나 실투·비교 정합 우선). 방법론·비중·종목수는 복제하되 유니버스만 K200∪KQ150 단일 고정.
- **백테 기간 = 2005-01-01~현재 고정** (도훈 mandate 2026-06-05): KR value/재무 데이터 한계(book-to-market 2002-08~, factor DB `V01_BM`·fundamental 공통) + FF3 36m 회귀 → FF 의존 전략 실효 2005-08. 공통 표준을 `start_date="2005-01-01"`로 고정. 가격 기반 전략은 1990~ 가능하나 비교 일관성 위해 2005 통일. (factor DB `M08_Residual_Mom`은 1995~ 있어 2000 우회 가능했으나, 논문 FF3 복제 충실 택함.)
- **Q-Lead/agent의 임의 변형 금지**: 종목수·비중scheme를 시스템 관습(top20 / 순수스코어 등)으로 **바꾸지 말 것**. 변형하면 그것은 논문 검증이 아니라 별개 전략이며 **검증 무효**다. (유니버스는 위 KR 치환 예외 — 단 논문 의도에 맞게, 무근거 축소는 금지.)
- **논문 미명시 값만** 시스템 표준 적용(PIT C1~C15, 15bps 비용, 유동성 2e8) — 단 무엇을 보충했는지 **명시**.
- **production constraint(max25 등)와 논문(decile 등)이 충돌**하면 검증 단계는 **논문 우선**, 충돌 사실을 명시 보고(production 적용은 운용 단계 별도).
- 근거 사건: residual momentum(Blitz-Huij-Martens 2011) 검증 중 Q-Lead가 top20·순수스코어가중·KR_TOP500으로 임의 변형 → 도훈 정정 "논문 그대로 비중". 본 원칙으로 재발 차단.

## 동작 절차 (4-step)

### 1. 가설 intake
- 입력이 논문 URL이면 `mcp__jina__read_url` / `mcp__arxiv__*` / `mcp__jina__search_arxiv|search_ssrn`로 핵심 시그널·구성·기간을 추출. (MCP 서버 6종 `.mcp.json` 등록 — 2026-06-10 재구축. arxiv 전문 PDF는 `mcp__arxiv__download_paper` → `.cache/arxiv_papers/`)
- MCP 불가 시 fallback: WebFetch(abs 페이지) + 로컬 추출기 `02_Infrastructure/alpha_search/paper_extract.py`(venv python — pymupdf/pdfplumber/pypdf 설치됨).
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
  n_holdings = 20, weight_method = "ivol", commission = 0.0015,   # ★ 제1원칙: 종목수·비중을 논문 명시값으로 대체(예 decile·equal-weight). 여기 값은 예시일 뿐 임의 기본값 아님
  start_date = "2010-01-01",  # 시그널 시작일. 빠른 검증 권장(전기간 NULL은 36년 풀시뮬로 매우 느림)
  universe = "ALL",           # "ALL"=전종목(유동성 2e8만) / "KR_TOP500"=top500. ★ 외국 논문이면 KR 시장으로 치환(US→KOSPI200∪KOSDAQ150 등), 논문 의도(대형/소형)에 맞는 KR 유니버스 선택
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
- **논문 완전 복제(제1원칙)**: 팩터 구성 방법론·포트폴리오 비중·유니버스·종목수·리밸을 논문 그대로. 임의 변형 = 검증 무효 (상단 ★ 제1원칙 참조).
- **QEPM 이행 금지**: Risk/Optimizer/Forge/Judge/Governor 미호출. Codex Critic Round 없음. WorkTask status 전이/`*_package.json`·`*_verdict.json` 산출 없음. certificate 의존 없음.
- **WT-id 사용 금지** (worktask_sequence_enforcer 등 Hook 오발동 회피).
- 텔레그램 직접 호출 금지 — `tg_agent_brief()`만(run_alpha_search 내부에서 처리).
- 백테스트 PIT 준수 필수.
- **외부 데이터 의존 팩터(fe_ml 등 parquet/cache 입력) PIT 책임**: `detect_lookahead` 정적분석은 factor_engine.R **텍스트만** 검사하므로, 외부 생성 파이프라인(예 `ml_momentum_ensemble.py`)의 forward-label lookahead를 **검사하지 못한다**(13줄짜리 fe_ml.R은 무조건 CLEAN 통과). 생성 `.py/.R`가 forward-label sanity(COVID 등 bear date 음수 검증 / `validate_label_direction()` / `bear_date_audit.R` 또는 동등 self-assert)를 통과하도록 **별도 보증 필수** (python-policy.md 언어무관 의무, Cycle 50 교훈). run_alpha_search는 외부 의존 감지 시 `[PIT-WARN]`을 출력한다.
