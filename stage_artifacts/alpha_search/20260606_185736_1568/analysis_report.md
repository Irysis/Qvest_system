# Strategy Diagnostic Report: Piotroski_F9_ALL
Generated: 2026-06-06

## Factor Signal Quality
- **IC Mean:** 0.0218 | **ICIR:** 0.221 | **IC > 0 rate:** 60.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.594 | **Positive rate:** 65.1%
- **3Y Rolling Sharpe (avg):** 0.322

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00126 | **NW t-stat:** 1.872 (not significant)
- **Avg Cross-sectional R²:** 0.0569

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 0.04%/yr (t=0.017)  | **Adj R²:** 0.6136

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1045 (lower = more diversified)
- **Avg Period Turnover:** 6.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 6)
- **Sample Aligned:** NO (overlap: 5256, strat-only: 13, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
