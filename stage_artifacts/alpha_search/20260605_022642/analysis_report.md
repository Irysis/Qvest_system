# Strategy Diagnostic Report: AS_momaccel_ovn
Generated: 2026-06-05

## Factor Signal Quality
- **IC Mean:** -0.0078 | **ICIR:** -0.053 | **IC > 0 rate:** 46.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.138 | **Positive rate:** 40.7%
- **3Y Rolling Sharpe (avg):** -0.332

## Stress Periods
- **Outperform rate vs BM:** 40.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00020 | **NW t-stat:** -0.177 (not significant)
- **Avg Cross-sectional R²:** 0.0645

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -12.55%/yr (t=-1.727)  | **Adj R²:** 0.0879

## Portfolio Characteristics
- **Avg Sector HHI:** 0.2055 (lower = more diversified)
- **Avg Period Turnover:** 42.1%

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
