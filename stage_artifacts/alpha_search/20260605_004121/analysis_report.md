# Strategy Diagnostic Report: AS_mom3_1_ovn
Generated: 2026-06-05

## Factor Signal Quality
- **IC Mean:** 0.0004 | **ICIR:** 0.002 | **IC > 0 rate:** 46.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.292 | **Positive rate:** 32.5%
- **3Y Rolling Sharpe (avg):** -0.456

## Stress Periods
- **Outperform rate vs BM:** 40.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00002 | **NW t-stat:** 0.021 (not significant)
- **Avg Cross-sectional R²:** 0.0669

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -16.12%/yr (t=-2.572) (significant) | **Adj R²:** 0.1167

## Portfolio Characteristics
- **Avg Sector HHI:** 0.2057 (lower = more diversified)
- **Avg Period Turnover:** 58.7%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** NO (overlap: 8873, strat-only: 13, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
