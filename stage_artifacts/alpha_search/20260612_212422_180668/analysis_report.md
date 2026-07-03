# Strategy Diagnostic Report: Best FM + Best Regime — FM_39 최적 × RC_50 최적 결합
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0259 | **ICIR:** 0.173 | **IC > 0 rate:** 57.5%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.669 | **Positive rate:** 67.6%
- **3Y Rolling Sharpe (avg):** 0.421

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00111 | **NW t-stat:** 1.302 (not significant)
- **Avg Cross-sectional R²:** 0.0797

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -0.19%/yr (t=-0.083)  | **Adj R²:** 0.6278

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0987 (lower = more diversified)
- **Avg Period Turnover:** 13.4%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 5)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 55.0% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.18 < -0.1 & 초과CAGR -2.3%p < 0 — KR에서 팩터 방향 역작동 의심
- [x] FMT-03: Ensemble Dilution — AUTO: 앙상블/블렌드 구성 + grade C — 결합 시 강점 희석 의심 (키워드 기반 heuristic)
- [x] FMT-04: Regime Blindness — AUTO: MDD 55.0% > 35% & BM상관 0.80 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [x] FMT-08: Regime Overfit — AUTO: 국면 게이팅 구성 + 초과CAGR -2.3%p < 0 — 회복랠리 상실로 CAGR 훼손 의심

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
