# Strategy Diagnostic Report: RF_PAR_B3_11_KOSDAQ150
Generated: 2026-09-03

## Factor Signal Quality
- **IC Mean:** 0.0214 | **ICIR:** 0.096 | **IC > 0 rate:** 55.3%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.602 | **Positive rate:** 67.3%
- **3Y Rolling Sharpe (avg):** 0.461

## Stress Periods
- **Outperform rate vs BM:** 67.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00000 | **NW t-stat:** 0.000 (not significant)
- **Avg Cross-sectional R²:** 0.0000

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 7.34%/yr (t=1.198)  | **Adj R²:** 0.4215

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 23.4%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 1)
- **Sample Aligned:** YES [ALIGNED] (overlap: 4082, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
