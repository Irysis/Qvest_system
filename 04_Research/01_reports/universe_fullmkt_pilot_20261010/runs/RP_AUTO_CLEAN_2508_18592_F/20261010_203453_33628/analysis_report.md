# Strategy Diagnostic Report: UNIV_CLEAN_2508_18592_F
Generated: 2026-10-10

## Factor Signal Quality
- **IC Mean:** 0.0105 | **ICIR:** 0.110 | **IC > 0 rate:** 56.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.845 | **Positive rate:** 65.7%
- **3Y Rolling Sharpe (avg):** 0.605

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00178 | **NW t-stat:** 1.898 (not significant)
- **Avg Cross-sectional R²:** 0.0576

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 3.54%/yr (t=0.900)  | **Adj R²:** 0.5767

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 78.2%

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
