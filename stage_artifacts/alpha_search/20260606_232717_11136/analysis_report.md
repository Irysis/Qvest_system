# Strategy Diagnostic Report: Coskewness_HS2000
Generated: 2026-06-06

## Factor Signal Quality
- **IC Mean:** 0.0174 | **ICIR:** 0.156 | **IC > 0 rate:** 55.9%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.581 | **Positive rate:** 66.5%
- **3Y Rolling Sharpe (avg):** 0.334

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00172 | **NW t-stat:** 2.164 (significant)
- **Avg Cross-sectional R²:** 0.0561

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -0.32%/yr (t=-0.145)  | **Adj R²:** 0.7256

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0727 (lower = more diversified)
- **Avg Period Turnover:** 14.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.3%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 24)
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
