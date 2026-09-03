# Strategy Diagnostic Report: RF_PAR_B1_5_5momentumaccrualconsensusdefensequality
Generated: 2026-09-03

## Factor Signal Quality
- **IC Mean:** -0.0143 | **ICIR:** -0.067 | **IC > 0 rate:** 47.9%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.457 | **Positive rate:** 55.4%
- **3Y Rolling Sharpe (avg):** 0.154

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00000 | **NW t-stat:** 0.000 (not significant)
- **Avg Cross-sectional R²:** 0.0000

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -1.87%/yr (t=-0.760)  | **Adj R²:** 0.7597

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 20.7%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 1, common>50%: 10)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5324, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
