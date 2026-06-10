# Strategy Diagnostic Report: Mohanram G-Score robust (저BM, 가용신호)
Generated: 2026-06-06

## Factor Signal Quality
- **IC Mean:** 0.0296 | **ICIR:** 0.252 | **IC > 0 rate:** 59.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.672 | **Positive rate:** 68.6%
- **3Y Rolling Sharpe (avg):** 0.486

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00068 | **NW t-stat:** 0.592 (not significant)
- **Avg Cross-sectional R²:** 0.0677

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 3.14%/yr (t=1.126)  | **Adj R²:** 0.5696

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1071 (lower = more diversified)
- **Avg Period Turnover:** 6.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 3)
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
