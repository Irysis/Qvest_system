# Strategy Diagnostic Report: AS_mom12_1
Generated: 2026-06-04

## Factor Signal Quality
- **IC Mean:** 0.0071 | **ICIR:** 0.038 | **IC > 0 rate:** 54.7%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.009 | **Positive rate:** 42.0%
- **3Y Rolling Sharpe (avg):** -0.203

## Stress Periods
- **Outperform rate vs BM:** 40.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00426 | **NW t-stat:** 1.525 (not significant)
- **Avg Cross-sectional R²:** 0.0671

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -9.23%/yr (t=-1.674)  | **Adj R²:** 0.3659

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1476 (lower = more diversified)
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
