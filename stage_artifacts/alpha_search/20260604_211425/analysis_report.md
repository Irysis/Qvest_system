# Strategy Diagnostic Report: AS_mom9_1_sp
Generated: 2026-06-04

## Factor Signal Quality
- **IC Mean:** 0.0022 | **ICIR:** 0.012 | **IC > 0 rate:** 51.8%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.359 | **Positive rate:** 33.7%
- **3Y Rolling Sharpe (avg):** -0.498

## Stress Periods
- **Outperform rate vs BM:** 20.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00158 | **NW t-stat:** 1.041 (not significant)
- **Avg Cross-sectional R²:** 0.0634

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -17.60%/yr (t=-2.964) (significant) | **Adj R²:** 0.1534

## Portfolio Characteristics
- **Avg Sector HHI:** 0.2036 (lower = more diversified)
- **Avg Period Turnover:** 26.3%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** NO (overlap: 8750, strat-only: 13, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
