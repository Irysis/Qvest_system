# Strategy Diagnostic Report: RP_AUTO_200302515
Generated: 2026-09-12

## Factor Signal Quality
- **IC Mean:** 0.0469 | **ICIR:** 0.309 | **IC > 0 rate:** 64.5%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 1.069 | **Positive rate:** 83.5%
- **3Y Rolling Sharpe (avg):** 0.953

## Stress Periods
- **Outperform rate vs BM:** 100.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00539 | **NW t-stat:** 4.972 (significant)
- **Avg Cross-sectional R²:** 0.0620

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 22.03%/yr (t=4.165) (significant) | **Adj R²:** 0.0040

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 59.7%

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
