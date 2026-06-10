# Strategy Diagnostic Report: STR_AS_value_ep
Generated: 2026-06-05

## Factor Signal Quality
- **IC Mean:** 0.0407 | **ICIR:** 0.435 | **IC > 0 rate:** 67.2%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 1.126 | **Positive rate:** 69.5%
- **3Y Rolling Sharpe (avg):** 0.845

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00065 | **NW t-stat:** 0.793 (not significant)
- **Avg Cross-sectional R²:** 0.0600

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 6.48%/yr (t=2.110) (significant) | **Adj R²:** 0.6666

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1087 (lower = more diversified)
- **Avg Period Turnover:** 8.7%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 11.5%
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
