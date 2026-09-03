# Strategy Diagnostic Report: RP_AUTO_260827076
Generated: 2026-08-31

## Factor Signal Quality
- **IC Mean:** -0.0108 | **ICIR:** -0.062 | **IC > 0 rate:** 50.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.788 | **Positive rate:** 61.9%
- **3Y Rolling Sharpe (avg):** 0.589

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00217 | **NW t-stat:** 1.530 (not significant)
- **Avg Cross-sectional R²:** 0.0650

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 5.13%/yr (t=0.945)  | **Adj R²:** 0.4788

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 41.0%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 11.3%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 4824, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
