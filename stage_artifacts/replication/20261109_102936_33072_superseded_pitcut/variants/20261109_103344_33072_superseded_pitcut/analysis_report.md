# Strategy Diagnostic Report: Piotroski2000_FSCORE_HighBM_v_ha
Generated: 2026-11-09

## Factor Signal Quality
- **IC Mean:** 0.1001 | **ICIR:** 1.394 | **IC > 0 rate:** 90.9%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.625 | **Positive rate:** 76.3%
- **3Y Rolling Sharpe (avg):** 0.589

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.04376 | **NW t-stat:** 3.700 (significant)
- **Avg Cross-sectional R²:** 0.0424

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 6.96%/yr (t=3.710) (significant) | **Adj R²:** 0.0004

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 50.0%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.3%
- **Crowding Risk:** MEDIUM (persistent>75%: 9, common>50%: 88)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5557, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
