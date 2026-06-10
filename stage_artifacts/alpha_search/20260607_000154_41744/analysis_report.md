# Strategy Diagnostic Report: RealizedSkew_low
Generated: 2026-06-07

## Factor Signal Quality
- **IC Mean:** 0.0305 | **ICIR:** 0.305 | **IC > 0 rate:** 61.7%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.590 | **Positive rate:** 68.1%
- **3Y Rolling Sharpe (avg):** 0.306

## Stress Periods
- **Outperform rate vs BM:** 100.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00192 | **NW t-stat:** 2.987 (significant)
- **Avg Cross-sectional R²:** 0.0539

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 0.03%/yr (t=0.015)  | **Adj R²:** 0.7464

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0626 (lower = more diversified)
- **Avg Period Turnover:** 12.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.3%
- **Crowding Risk:** LOW (persistent>75%: 4, common>50%: 60)
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
