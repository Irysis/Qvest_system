# Strategy Diagnostic Report: STR_RESIDMOM_12_1
Generated: 2026-06-05

## Factor Signal Quality
- **IC Mean:** 0.0063 | **ICIR:** 0.054 | **IC > 0 rate:** 51.5%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.011 | **Positive rate:** 43.0%
- **3Y Rolling Sharpe (avg):** -0.146

## Stress Periods
- **Outperform rate vs BM:** 67.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00168 | **NW t-stat:** 1.343 (not significant)
- **Avg Cross-sectional R²:** 0.0450

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -7.11%/yr (t=-1.216)  | **Adj R²:** 0.2624

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1513 (lower = more diversified)
- **Avg Period Turnover:** 26.9%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** NO (overlap: 4014, strat-only: 13, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
