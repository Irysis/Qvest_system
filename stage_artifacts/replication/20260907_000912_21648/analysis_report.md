# Strategy Diagnostic Report: RP_AUTO_combo140381252007
Generated: 2026-09-07

## Factor Signal Quality
- **IC Mean:** 0.0054 | **ICIR:** 0.032 | **IC > 0 rate:** 54.8%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.725 | **Positive rate:** 64.5%
- **3Y Rolling Sharpe (avg):** 0.506

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00047 | **NW t-stat:** -0.333 (not significant)
- **Avg Cross-sectional R²:** 0.0692

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 6.06%/yr (t=1.316)  | **Adj R²:** 0.4785

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 43.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
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
