# Strategy Diagnostic Report: RP_AUTO_220205702
Generated: 2026-09-24

## Factor Signal Quality
- **IC Mean:** 0.0085 | **ICIR:** 0.103 | **IC > 0 rate:** 51.8%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.764 | **Positive rate:** 68.1%
- **3Y Rolling Sharpe (avg):** 0.477

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00113 | **NW t-stat:** 0.677 (not significant)
- **Avg Cross-sectional R²:** 0.0451

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 2.99%/yr (t=1.179)  | **Adj R²:** 0.6792

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 66.0%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.5%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5300, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
