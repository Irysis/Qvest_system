# Strategy Diagnostic Report: AS_ml_ensemble
Generated: 2026-06-05

## Factor Signal Quality
- **IC Mean:** 0.0245 | **ICIR:** 0.238 | **IC > 0 rate:** 61.1%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.369 | **Positive rate:** 48.5%
- **3Y Rolling Sharpe (avg):** 0.142

## Stress Periods
- **Outperform rate vs BM:** 33.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00237 | **NW t-stat:** 1.949 (not significant)
- **Avg Cross-sectional R²:** 0.0560

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -0.86%/yr (t=-0.104)  | **Adj R²:** 0.2599

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1764 (lower = more diversified)
- **Avg Period Turnover:** 53.3%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** NO (overlap: 3515, strat-only: 13, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
