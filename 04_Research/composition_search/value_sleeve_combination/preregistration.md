# Pre-registration — Value Sleeve Combination A/B (Composition Search Track C)

**Locked before execution.** Forge measurement agent. 도훈 mandate 2026-06-11:
"밸류 슬리브를 조합했을 때 성과가 개선되는지를 제대로 확인."

## Question
Incumbent book (STR_1715_AR_on_M4_R05_overlay_PG2) 단독 vs book + value-sleeve blend 의
실측 A/B. value sleeve 의 기초체력은 약하나 (standalone SR 0.375), cor vs book ≈ −0.042
(직교) 이므로 조합 시 위험조정성과가 개선되는지 측정.

## Stage 정의
- **Stage 1 (이번 과제)**: sleeve-level blend — post-overlay book 월간 net return 시계열 ×
  value sleeve 월간 net return 시계열. 상한/하한 추정용 1차 증거.
- **Stage 2 (이번 범위 밖)**: 충실한 통합 = value 신호를 core layer 에 합류시킨 뒤 overlay
  (AR/R05) 재적용. 본 과제는 Stage 1 만 수행.

## 사전등록 grid (불변)
- `w_value ∈ {0.05, 0.10, 0.15, 0.20, 0.30}` (book = 1 − w_value)
- **n_trials = 5, selection_type = "sweep"** (열거된 5 비중에서 ΔIR/ΔSR argmax 선택 구조 →
  sweep. DSR n_trials=5 계상하여 진단 산출·기록.)

## 측정 방법 (합성 금지 준수)
- blend 월간 수익률 = R `PerformanceAnalytics::Return.portfolio(R, weights, rebalance_on="months")`
  로 구성 (weight drift·월간 리밸 정확). `w*r1+(1-w)*r2` 손계산 금지.
- SR/CAGR/MDD/Calmar = PerformanceAnalytics 표준 함수 (table.AnnualizedReturns, maxDrawdown,
  Return.cumulative). IR/PORT_t(NW lag-3)/alpha/beta/cor = contract `build_benchmark_compare()`
  (annualization_factor=12, 월간).
- book-marginal ΔIR: book_optimizer.R `book_information_ratio` 는 cross-WT package
  (alpha/risk/opt JSON) 입력 전제라 sleeve-return-series A/B 에는 구조적 부적합. 따라서
  **series-level 충실 analog = build_benchmark_compare 의 Information_Ratio** (active/TE,
  book_mu/book_te 와 동일 개념) 를 사용하고 summary 에 치환 사유 명시. ΔIR = IR(blend) − IR(book).

## 비용 처리 (정직성)
- book 시계열 = net (v2.3_kr_retail_15bps, forge_package 확인). value sleeve 시계열 = net
  (15bps delta-based, run_alpha.R build_sleeve_series 확인). **두 시계열 모두 net.**
- blend 단계 추가 비용 = sleeve 간 월간 리밸런싱 회전분만. Return.portfolio 는 두 sleeve 간
  drift 후 target 복원 시 회전을 발생시키나, sleeve 단위 weight 변동(5%~30% 고정 target 근방
  drift)은 작음. 보수적 처리: blend 리밸 회전에 15bps 과금 추가 (절차/근거 summary 명시).
- **라벨 불일치 기록**: book = v2.3 flat per-rebalance, value sleeve = delta-based 15bps.
  혼합 시계열 비교의 한계로 summary 에 명시 (구 v2.3 baseline 라벨 confirm).

## 기간
두 시계열 + 벤치 공통 교집합 (realized_ym 키). 200개월 미만이면 사유 보고.

## 출처 (provenance)
- book: `05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv`
  컬럼 `ret_L5_V2` (= L5_V2_aggressive_regime, PG2 admit variant. forge_package.json
  sr_realized_share_based=1.9536 @255m, 267m full SR 1.8861). realized_ym 키, 2004-02..2026-04.
  벤치 = 동 파일에는 없음 → `.cache/benchmark.parquet` (BM_Ret) 월간 compounding.
- value sleeve: `04_Research/strategies/STR_WT-D20260611_001_value_sleeve/scores_cache.parquet`
  → run_alpha.R `build_sleeve_series()` 로직 read-only 재구성 (top-20 EW long-only,
  delta-based 15bps, realized_ym 키). standalone SR 0.375 / cor vs book −0.042 재현 확인 의무.

## 판정 기준 (참조선, 연구단계 보고만)
- ΔIR ≥ 0.05 (admission book-marginal 게이트 참조)
- cor(value, book) < 0.30 (게이트 참조)
- DSR ≥ 0.5 (sweep 게이트 참조)
- 합산 보유종목수 ≤ 25 (admission 제약, 연구단계 보고만 — 두 sleeve top-20 union > 25 예상)
- **AX-000 정직보고**: TO 1639%/yr sleeve 의 marginal 이 음수일 개연성 높음. 미화 금지.
