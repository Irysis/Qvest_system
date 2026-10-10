# Strategy Diagnostic Report: UNIV_2505_20608_W
Generated: 2026-10-10

## Factor Signal Quality
- **IC Mean:** -0.0040 | **ICIR:** -0.092 | **IC > 0 rate:** 46.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.173 | **Positive rate:** 41.5%
- **3Y Rolling Sharpe (avg):** -0.246

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00040 | **NW t-stat:** 0.895 (not significant)
- **Avg Cross-sectional R²:** 0.0227

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -3.36%/yr (t=-1.168)  | **Adj R²:** 0.0443

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 44.7%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.2%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 1)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5341, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
