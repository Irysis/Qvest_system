# Strategy Diagnostic Report: Max Return Concentration — 상위 10종목 집중 + 나머지 20종목 분산
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0070 | **ICIR:** 0.057 | **IC > 0 rate:** 54.3%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.177 | **Positive rate:** 50.5%
- **3Y Rolling Sharpe (avg):** -0.021

## Stress Periods
- **Outperform rate vs BM:** 25.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00102 | **NW t-stat:** -0.848 (not significant)
- **Avg Cross-sectional R²:** 0.0634

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -7.56%/yr (t=-3.601) (significant) | **Adj R²:** 0.6574

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1196 (lower = more diversified)
- **Avg Period Turnover:** 44.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 61.1% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.75 < -0.1 & 초과CAGR -10.2%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 61.1% > 35% & BM상관 0.78 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
