# Strategy Diagnostic Report: AS_momsharpe_sp
Generated: 2026-06-04

## Factor Signal Quality
- **IC Mean:** 0.0065 | **ICIR:** 0.036 | **IC > 0 rate:** 54.9%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.121 | **Positive rate:** 41.5%
- **3Y Rolling Sharpe (avg):** -0.343

## Stress Periods
- **Outperform rate vs BM:** 40.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00895 | **NW t-stat:** 3.970 (significant)
- **Avg Cross-sectional R²:** 0.0657

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -13.83%/yr (t=-2.242) (significant) | **Adj R²:** 0.2174

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1885 (lower = more diversified)
- **Avg Period Turnover:** 23.0%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** NO (overlap: 8690, strat-only: 13, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
