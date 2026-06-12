# Strategy Diagnostic Report: Transfer-Entropy Info-Sink (KR-native)
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** -0.0066 | **ICIR:** -0.101 | **IC > 0 rate:** 47.7%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.372 | **Positive rate:** 58.5%
- **3Y Rolling Sharpe (avg):** 0.182

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00072 | **NW t-stat:** -1.451 (not significant)
- **Avg Cross-sectional R²:** 0.0522

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -2.62%/yr (t=-1.102)  | **Adj R²:** 0.6359

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0994 (lower = more diversified)
- **Avg Period Turnover:** 55.2%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 11.4%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** NO (overlap: 5258, strat-only: 14, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
