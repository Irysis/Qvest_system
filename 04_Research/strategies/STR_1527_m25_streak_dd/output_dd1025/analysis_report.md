# Strategy Diagnostic Report: M25_DD1025
Generated: 2026-03-26

## Factor Signal Quality
- **IC Mean:** -0.0007 | **ICIR:** -0.012 | **IC > 0 rate:** 52.4%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.290 | **Positive rate:** 56.2%
- **3Y Rolling Sharpe (avg):** 0.142

## Stress Periods
- **Outperform rate vs BM:** 100.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00006 | **NW t-stat:** 0.130 (not significant)
- **Avg Cross-sectional R²:** 0.0443

## Multi-Factor Alpha
- **Best Model:** Fama-French 3-Factor | **Alpha:** -2.07%/yr (t=-0.737)  | **Adj R²:** 0.6101

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0845 (lower = more diversified)
- **Avg Period Turnover:** 4.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 4, common>50%: 9)
- **Sample Aligned:** YES (overlap: 5095, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
