# Strategy Diagnostic Report: STR_valmom_AMP2013
Generated: 2026-06-05

## Factor Signal Quality
- **IC Mean:** 0.0280 | **ICIR:** 0.200 | **IC > 0 rate:** 59.4%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 1.084 | **Positive rate:** 74.7%
- **3Y Rolling Sharpe (avg):** 0.746

## Stress Periods
- **Outperform rate vs BM:** 100.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00391 | **NW t-stat:** 3.353 (significant)
- **Avg Cross-sectional R²:** 0.0573

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 8.09%/yr (t=2.174) (significant) | **Adj R²:** 0.6473

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1063 (lower = more diversified)
- **Avg Period Turnover:** 17.3%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 11.3%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 2)
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
