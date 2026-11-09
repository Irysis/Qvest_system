# Strategy Diagnostic Report: Piotroski2000_FSCORE_HighBM
Generated: 2026-11-09

## Factor Signal Quality
- **IC Mean:** 0.0994 | **ICIR:** 1.379 | **IC > 0 rate:** 90.9%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.508 | **Positive rate:** 64.9%
- **3Y Rolling Sharpe (avg):** 0.334

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.04355 | **NW t-stat:** 3.702 (significant)
- **Avg Cross-sectional R²:** 0.0424

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 17.84%/yr (t=2.850) (significant) | **Adj R²:** -0.0090

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 91.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 11.4%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5308, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
