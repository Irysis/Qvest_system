# Strategy Diagnostic Report: RP_AUTO_260817481
Generated: 2026-08-31

## Factor Signal Quality
- **IC Mean:** 0.0189 | **ICIR:** 0.119 | **IC > 0 rate:** 55.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.338 | **Positive rate:** 64.4%
- **3Y Rolling Sharpe (avg):** 0.146

## Stress Periods
- **Outperform rate vs BM:** 100.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00068 | **NW t-stat:** 0.901 (not significant)
- **Avg Cross-sectional R²:** 0.0542

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -0.27%/yr (t=-0.113)  | **Adj R²:** 0.5114

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 43.3%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 2)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5321, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
