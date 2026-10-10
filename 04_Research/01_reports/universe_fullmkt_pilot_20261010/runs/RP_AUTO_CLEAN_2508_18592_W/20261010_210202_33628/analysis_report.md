# Strategy Diagnostic Report: UNIV_CLEAN_2508_18592_W
Generated: 2026-10-10

## Factor Signal Quality
- **IC Mean:** 0.0631 | **ICIR:** 0.865 | **IC > 0 rate:** 80.9%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.822 | **Positive rate:** 66.1%
- **3Y Rolling Sharpe (avg):** 0.643

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00640 | **NW t-stat:** 7.499 (significant)
- **Avg Cross-sectional R²:** 0.0239

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 5.65%/yr (t=1.281)  | **Adj R²:** 0.5697

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 92.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5341, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
