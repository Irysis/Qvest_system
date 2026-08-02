# Strategy Diagnostic Report: CTR_MAG12_SIZE_equal
Generated: 2026-08-02

## Factor Signal Quality
- **IC Mean:** 0.0770 | **ICIR:** 0.380 | **IC > 0 rate:** 52.2%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 3.510 | **Positive rate:** 100.0%
- **3Y Rolling Sharpe (avg):** 0.000

## Stress Periods
- **Outperform rate vs BM:** 0.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00083 | **NW t-stat:** 0.129 (not significant)
- **Avg Cross-sectional R²:** 0.1021

## Multi-Factor Alpha
- **Best Model:** N/A | **Alpha:** 0.00%/yr (t=0.000)  | **Adj R²:** 0.0000

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1765 (lower = more diversified)
- **Avg Period Turnover:** 2.4%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** MEDIUM (persistent>75%: 13, common>50%: 17)
- **Sample Aligned:** YES (overlap: 481, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.59 < -0.1 & 초과CAGR -20.8%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
