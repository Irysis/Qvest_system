# Strategy Diagnostic Report: RP_AUTO_200104185
Generated: 2026-09-12

## Factor Signal Quality
- **IC Mean:** 0.0089 | **ICIR:** 0.052 | **IC > 0 rate:** 57.1%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.283 | **Positive rate:** 58.9%
- **3Y Rolling Sharpe (avg):** 0.074

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00077 | **NW t-stat:** 0.549 (not significant)
- **Avg Cross-sectional R²:** 0.0608

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 3.90%/yr (t=1.448)  | **Adj R²:** 0.0439

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 0.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.1%
- **Crowding Risk:** HIGH (persistent>75%: 128, common>50%: 241)
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
