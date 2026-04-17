# Strategy Diagnostic Report: STR_1502_DD620
Generated: 2026-03-26

## Factor Signal Quality
- **IC Mean:** 0.0406 | **ICIR:** 0.339 | **IC > 0 rate:** 66.7%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.553 | **Positive rate:** 61.5%
- **3Y Rolling Sharpe (avg):** 0.495

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00172 | **NW t-stat:** 1.895 (not significant)
- **Avg Cross-sectional R²:** 0.0524

## Multi-Factor Alpha
- **Best Model:** Fama-French 3-Factor | **Alpha:** -1.16%/yr (t=-0.456)  | **Adj R²:** 0.4509

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1358 (lower = more diversified)
- **Avg Period Turnover:** 10.3%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 2, common>50%: 4)
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
