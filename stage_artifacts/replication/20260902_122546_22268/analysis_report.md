# Strategy Diagnostic Report: CID_beta_LS_Pinchuk2023
Generated: 2026-09-02

## Factor Signal Quality
- **IC Mean:** 0.0246 | **ICIR:** 0.194 | **IC > 0 rate:** 57.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.393 | **Positive rate:** 66.8%
- **3Y Rolling Sharpe (avg):** 0.364

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00168 | **NW t-stat:** 1.867 (not significant)
- **Avg Cross-sectional R²:** 0.0596

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 8.94%/yr (t=1.926)  | **Adj R²:** 0.1114

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 14.0%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.2%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 9)
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
