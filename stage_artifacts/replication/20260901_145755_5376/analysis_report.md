# Strategy Diagnostic Report: RP_AUTO_condmat0410079
Generated: 2026-09-01

## Factor Signal Quality
- **IC Mean:** -0.0022 | **ICIR:** -0.021 | **IC > 0 rate:** 51.2%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.626 | **Positive rate:** 69.1%
- **3Y Rolling Sharpe (avg):** 0.394

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00054 | **NW t-stat:** -0.758 (not significant)
- **Avg Cross-sectional R²:** 0.0653

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 2.07%/yr (t=0.948)  | **Adj R²:** 0.6753

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 22.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5322, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
