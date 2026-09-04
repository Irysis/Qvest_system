# Strategy Diagnostic Report: RP_AUTO_combo200708115230
Generated: 2026-09-04

## Factor Signal Quality
- **IC Mean:** 0.0236 | **ICIR:** 0.175 | **IC > 0 rate:** 56.8%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.813 | **Positive rate:** 76.0%
- **3Y Rolling Sharpe (avg):** 0.577

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00237 | **NW t-stat:** 2.448 (significant)
- **Avg Cross-sectional R²:** 0.0628

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 6.28%/yr (t=1.845)  | **Adj R²:** 0.6089

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 28.7%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5325, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
