# Strategy Diagnostic Report: Mohanram G-Score (저BM growth)
Generated: 2026-06-06

## Factor Signal Quality
- **IC Mean:** 0.0366 | **ICIR:** 0.189 | **IC > 0 rate:** 61.9%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.555 | **Positive rate:** 66.5%
- **3Y Rolling Sharpe (avg):** 0.356

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00323 | **NW t-stat:** 2.310 (significant)
- **Avg Cross-sectional R²:** 0.0877

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 2.99%/yr (t=0.960)  | **Adj R²:** 0.4941

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1521 (lower = more diversified)
- **Avg Period Turnover:** 4.6%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 13.4%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 3)
- **Sample Aligned:** NO (overlap: 5256, strat-only: 13, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
