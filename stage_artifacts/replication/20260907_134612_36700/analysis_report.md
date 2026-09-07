# Strategy Diagnostic Report: RP_AUTO_08062606
Generated: 2026-09-07

## Factor Signal Quality
- **IC Mean:** -0.0032 | **ICIR:** -0.023 | **IC > 0 rate:** 51.3%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.271 | **Positive rate:** 40.8%
- **3Y Rolling Sharpe (avg):** -0.455

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00006 | **NW t-stat:** 0.066 (not significant)
- **Avg Cross-sectional R²:** 0.0604

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -1.88%/yr (t=-0.962)  | **Adj R²:** 0.0437

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 14.1%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.2%
- **Crowding Risk:** HIGH (persistent>75%: 78, common>50%: 185)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5326, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
