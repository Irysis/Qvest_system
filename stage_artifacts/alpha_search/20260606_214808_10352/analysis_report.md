# Strategy Diagnostic Report: DownsideBeta_ACX2006
Generated: 2026-06-06

## Factor Signal Quality
- **IC Mean:** -0.0022 | **ICIR:** -0.012 | **IC > 0 rate:** 48.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.509 | **Positive rate:** 61.9%
- **3Y Rolling Sharpe (avg):** 0.253

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00210 | **NW t-stat:** 1.365 (not significant)
- **Avg Cross-sectional R²:** 0.0694

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -1.02%/yr (t=-0.431)  | **Adj R²:** 0.7293

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0811 (lower = more diversified)
- **Avg Period Turnover:** 10.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.3%
- **Crowding Risk:** LOW (persistent>75%: 6, common>50%: 45)
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
