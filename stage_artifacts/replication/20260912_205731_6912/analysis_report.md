# Strategy Diagnostic Report: RP_AUTO_200302515
Generated: 2026-09-12

## Factor Signal Quality
- **IC Mean:** 0.0202 | **ICIR:** 0.120 | **IC > 0 rate:** 54.4%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.392 | **Positive rate:** 58.1%
- **3Y Rolling Sharpe (avg):** 0.339

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00306 | **NW t-stat:** 2.529 (significant)
- **Avg Cross-sectional R²:** 0.0650

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 10.01%/yr (t=1.715)  | **Adj R²:** -0.0070

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 67.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.3%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5331, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
