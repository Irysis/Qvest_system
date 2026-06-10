# Strategy Diagnostic Report: STR_AS_value_bm
Generated: 2026-06-05

## Factor Signal Quality
- **IC Mean:** 0.0309 | **ICIR:** 0.205 | **IC > 0 rate:** 55.5%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.849 | **Positive rate:** 71.9%
- **3Y Rolling Sharpe (avg):** 0.593

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00305 | **NW t-stat:** 3.486 (significant)
- **Avg Cross-sectional R²:** 0.0565

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 2.79%/yr (t=0.950)  | **Adj R²:** 0.7032

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0954 (lower = more diversified)
- **Avg Period Turnover:** 4.6%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 11.3%
- **Crowding Risk:** LOW (persistent>75%: 1, common>50%: 9)
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
