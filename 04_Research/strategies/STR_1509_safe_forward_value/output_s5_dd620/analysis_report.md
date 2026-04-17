# Strategy Diagnostic Report: STR_1509_DD620
Generated: 2026-03-26

## Factor Signal Quality
- **IC Mean:** 0.0190 | **ICIR:** 0.258 | **IC > 0 rate:** 59.4%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.551 | **Positive rate:** 65.3%
- **3Y Rolling Sharpe (avg):** 0.564

## Stress Periods
- **Outperform rate vs BM:** 100.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00057 | **NW t-stat:** 0.919 (not significant)
- **Avg Cross-sectional R²:** 0.0443

## Multi-Factor Alpha
- **Best Model:** Fama-French 3-Factor | **Alpha:** 3.11%/yr (t=0.901)  | **Adj R²:** 0.3272

## Portfolio Characteristics
- **Avg Sector HHI:** 0.2576 (lower = more diversified)
- **Avg Period Turnover:** 17.2%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 5)
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
