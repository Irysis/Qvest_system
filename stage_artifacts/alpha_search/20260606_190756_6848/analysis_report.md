# Strategy Diagnostic Report: Piotroski_F9_HighBM
Generated: 2026-06-06

## Factor Signal Quality
- **IC Mean:** 0.0114 | **ICIR:** 0.091 | **IC > 0 rate:** 53.5%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.639 | **Positive rate:** 67.2%
- **3Y Rolling Sharpe (avg):** 0.429

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00067 | **NW t-stat:** 0.861 (not significant)
- **Avg Cross-sectional R²:** 0.0736

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 0.11%/yr (t=0.050)  | **Adj R²:** 0.6429

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1140 (lower = more diversified)
- **Avg Period Turnover:** 7.2%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 5)
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
