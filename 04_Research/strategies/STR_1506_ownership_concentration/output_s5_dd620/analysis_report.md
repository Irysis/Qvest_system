# Strategy Diagnostic Report: STR_1506_DD620
Generated: 2026-03-26

## Factor Signal Quality
- **IC Mean:** 0.0385 | **ICIR:** 0.435 | **IC > 0 rate:** 69.5%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.539 | **Positive rate:** 63.3%
- **3Y Rolling Sharpe (avg):** 0.465

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00327 | **NW t-stat:** 3.042 (significant)
- **Avg Cross-sectional R²:** 0.0520

## Multi-Factor Alpha
- **Best Model:** Fama-French 3-Factor | **Alpha:** 0.10%/yr (t=0.033)  | **Adj R²:** 0.5555

## Portfolio Characteristics
- **Avg Sector HHI:** 0.2073 (lower = more diversified)
- **Avg Period Turnover:** 33.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 1, common>50%: 3)
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
