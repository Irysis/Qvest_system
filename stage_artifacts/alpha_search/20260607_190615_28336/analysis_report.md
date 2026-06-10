# Strategy Diagnostic Report: LeadLagNetMom
Generated: 2026-06-07

## Factor Signal Quality
- **IC Mean:** -0.0066 | **ICIR:** -0.067 | **IC > 0 rate:** 48.4%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.577 | **Positive rate:** 67.3%
- **3Y Rolling Sharpe (avg):** 0.348

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00023 | **NW t-stat:** 0.254 (not significant)
- **Avg Cross-sectional R²:** 0.0575

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -0.80%/yr (t=-0.216)  | **Adj R²:** 0.5732

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1125 (lower = more diversified)
- **Avg Period Turnover:** 80.9%

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
