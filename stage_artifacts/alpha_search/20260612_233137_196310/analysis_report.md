# Strategy Diagnostic Report: [진단] 앙상블 방법 전수 비교 — EW/SR/Calmar/Median/RP/MaxSR/FF5/Jackknife 8종
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0312 | **ICIR:** 0.159 | **IC > 0 rate:** 57.1%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.594 | **Positive rate:** 62.5%
- **3Y Rolling Sharpe (avg):** 0.428

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00040 | **NW t-stat:** 0.295 (not significant)
- **Avg Cross-sectional R²:** 0.0703

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 1.24%/yr (t=0.569)  | **Adj R²:** 0.3743

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1017 (lower = more diversified)
- **Avg Period Turnover:** 8.2%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 2, common>50%: 10)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.31 < -0.1 & 초과CAGR -5.3%p < 0 — KR에서 팩터 방향 역작동 의심
- [x] FMT-03: Ensemble Dilution — AUTO: 앙상블/블렌드 구성 + grade F — 결합 시 강점 희석 의심 (키워드 기반 heuristic)
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
