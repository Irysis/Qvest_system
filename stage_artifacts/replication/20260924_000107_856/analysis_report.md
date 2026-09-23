# Strategy Diagnostic Report: RF_PAR_B1_8_revmomflow
Generated: 2026-09-24

## Factor Signal Quality
- **IC Mean:** -0.0168 | **ICIR:** -0.088 | **IC > 0 rate:** 50.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.686 | **Positive rate:** 65.9%
- **3Y Rolling Sharpe (avg):** 0.439

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00000 | **NW t-stat:** 0.000 (not significant)
- **Avg Cross-sectional R²:** 0.0000

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 1.29%/yr (t=0.443)  | **Adj R²:** 0.6111

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 62.0%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** NO [MISALIGNED] (overlap: 5257, strat-only: 1, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
