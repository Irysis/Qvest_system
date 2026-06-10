# Strategy Diagnostic Report: Sector Spillover (Hou2007) MOM21 follower=all
Generated: 2026-06-07

## Factor Signal Quality
- **IC Mean:** 0.0089 | **ICIR:** 0.063 | **IC > 0 rate:** 54.7%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.663 | **Positive rate:** 71.2%
- **3Y Rolling Sharpe (avg):** 0.421

## Stress Periods
- **Outperform rate vs BM:** 25.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00268 | **NW t-stat:** 2.255 (significant)
- **Avg Cross-sectional R²:** 0.0624

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 3.95%/yr (t=0.903)  | **Adj R²:** 0.5025

## Portfolio Characteristics
- **Avg Sector HHI:** 0.3368 (lower = more diversified)
- **Avg Period Turnover:** 75.1%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
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
