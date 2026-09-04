# Strategy Diagnostic Report: RP_AUTO_150500328
Generated: 2026-09-04

## Factor Signal Quality
- **IC Mean:** 0.0168 | **ICIR:** 0.117 | **IC > 0 rate:** 51.7%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.478 | **Positive rate:** 26.8%
- **3Y Rolling Sharpe (avg):** -0.533

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00008 | **NW t-stat:** 0.077 (not significant)
- **Avg Cross-sectional R²:** 0.0664

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -12.02%/yr (t=-2.307) (significant) | **Adj R²:** 0.0193

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 74.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.4%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5325, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
