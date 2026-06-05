# Strategy Diagnostic Report: AS_mom12_1_sp
Generated: 2026-06-04

## Factor Signal Quality
- **IC Mean:** 0.0071 | **ICIR:** 0.038 | **IC > 0 rate:** 54.7%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.395 | **Positive rate:** 34.6%
- **3Y Rolling Sharpe (avg):** -0.549

## Stress Periods
- **Outperform rate vs BM:** 40.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00426 | **NW t-stat:** 1.525 (not significant)
- **Avg Cross-sectional R²:** 0.0671

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -18.33%/yr (t=-3.251) (significant) | **Adj R²:** 0.1938

## Portfolio Characteristics
- **Avg Sector HHI:** 0.2051 (lower = more diversified)
- **Avg Period Turnover:** 22.4%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** NO (overlap: 8690, strat-only: 13, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
