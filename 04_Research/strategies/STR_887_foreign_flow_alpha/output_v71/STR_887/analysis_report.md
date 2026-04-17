# Strategy Diagnostic Report: STR_887
Generated: 2026-03-26

## Factor Signal Quality
- **IC Mean:** 0.0599 | **ICIR:** 0.548 | **IC > 0 rate:** 69.5%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 1.149 | **Positive rate:** 79.5%
- **3Y Rolling Sharpe (avg):** 1.133

## Stress Periods
- **Outperform rate vs BM:** 100.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00583 | **NW t-stat:** 6.682 (significant)
- **Avg Cross-sectional R²:** 0.0547

## Multi-Factor Alpha
- **Best Model:** Fama-French 3-Factor | **Alpha:** 8.69%/yr (t=2.395) (significant) | **Adj R²:** 0.4197

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1460 (lower = more diversified)
- **Avg Period Turnover:** 22.1%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 1, common>50%: 2)
- **Sample Aligned:** YES (overlap: 5899, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
