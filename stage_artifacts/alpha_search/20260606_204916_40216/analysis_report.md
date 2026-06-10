# Strategy Diagnostic Report: Mohanram G-Score (전체 universe 비교)
Generated: 2026-06-06

## Factor Signal Quality
- **IC Mean:** 0.0193 | **ICIR:** 0.099 | **IC > 0 rate:** 56.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.571 | **Positive rate:** 65.7%
- **3Y Rolling Sharpe (avg):** 0.349

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00124 | **NW t-stat:** 1.005 (not significant)
- **Avg Cross-sectional R²:** 0.0828

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 1.06%/yr (t=0.443)  | **Adj R²:** 0.6023

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1234 (lower = more diversified)
- **Avg Period Turnover:** 3.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.5%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 4)
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
