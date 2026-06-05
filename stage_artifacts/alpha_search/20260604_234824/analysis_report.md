# Strategy Diagnostic Report: AS_momrev2w_ovn
Generated: 2026-06-05

## Factor Signal Quality
- **IC Mean:** 0.0332 | **ICIR:** 0.210 | **IC > 0 rate:** 58.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.411 | **Positive rate:** 28.4%
- **3Y Rolling Sharpe (avg):** -0.493

## Stress Periods
- **Outperform rate vs BM:** 80.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00149 | **NW t-stat:** 1.403 (not significant)
- **Avg Cross-sectional R²:** 0.0703

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -13.15%/yr (t=-2.695) (significant) | **Adj R²:** 0.0494

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1920 (lower = more diversified)
- **Avg Period Turnover:** 86.6%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** NO (overlap: 8914, strat-only: 13, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
