# Strategy Diagnostic Report: UNIV_1505_00328_F
Generated: 2026-10-10

## Factor Signal Quality
- **IC Mean:** 0.0169 | **ICIR:** 0.117 | **IC > 0 rate:** 51.7%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.462 | **Positive rate:** 27.3%
- **3Y Rolling Sharpe (avg):** -0.514

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00004 | **NW t-stat:** 0.039 (not significant)
- **Avg Cross-sectional R²:** 0.0665

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -11.70%/yr (t=-2.276) (significant) | **Adj R²:** 0.0119

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 74.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.4%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5341, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
