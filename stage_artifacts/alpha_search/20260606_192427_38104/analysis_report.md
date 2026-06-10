# Strategy Diagnostic Report: VarRatio_InfoSpeed
Generated: 2026-06-06

## Factor Signal Quality
- **IC Mean:** -0.0122 | **ICIR:** -0.142 | **IC > 0 rate:** 43.8%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.563 | **Positive rate:** 65.5%
- **3Y Rolling Sharpe (avg):** 0.327

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00093 | **NW t-stat:** -1.102 (not significant)
- **Avg Cross-sectional R²:** 0.0543

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -1.03%/yr (t=-0.491)  | **Adj R²:** 0.7314

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0687 (lower = more diversified)
- **Avg Period Turnover:** 18.1%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.3%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 33)
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
