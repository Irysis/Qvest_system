# Strategy Diagnostic Report: RP_AUTO_251112129
Generated: 2026-09-23

## Factor Signal Quality
- **IC Mean:** 0.0281 | **ICIR:** 0.346 | **IC > 0 rate:** 70.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.676 | **Positive rate:** 68.5%
- **3Y Rolling Sharpe (avg):** 0.507

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00345 | **NW t-stat:** 2.077 (significant)
- **Avg Cross-sectional R²:** 0.0554

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 0.48%/yr (t=0.203)  | **Adj R²:** 0.6259

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 55.6%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 11.8%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** NO [MISALIGNED] (overlap: 5257, strat-only: 1, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
