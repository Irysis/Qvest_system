# Strategy Diagnostic Report: STR_1465_DD_VT
Generated: 2026-03-26

## Factor Signal Quality
- **IC Mean:** 0.0507 | **ICIR:** 0.454 | **IC > 0 rate:** 69.5%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.510 | **Positive rate:** 66.5%
- **3Y Rolling Sharpe (avg):** 0.441

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00281 | **NW t-stat:** 3.011 (significant)
- **Avg Cross-sectional R²:** 0.0510

## Multi-Factor Alpha
- **Best Model:** Fama-French 3-Factor | **Alpha:** -0.20%/yr (t=-0.088)  | **Adj R²:** 0.4488

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1361 (lower = more diversified)
- **Avg Period Turnover:** 10.7%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 2, common>50%: 6)
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
