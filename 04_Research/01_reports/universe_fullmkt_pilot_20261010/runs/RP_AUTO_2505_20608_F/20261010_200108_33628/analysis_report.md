# Strategy Diagnostic Report: UNIV_2505_20608_F
Generated: 2026-10-10

## Factor Signal Quality
- **IC Mean:** 0.0026 | **ICIR:** 0.034 | **IC > 0 rate:** 52.5%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.248 | **Positive rate:** 36.0%
- **3Y Rolling Sharpe (avg):** -0.305

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00009 | **NW t-stat:** 0.168 (not significant)
- **Avg Cross-sectional R²:** 0.0547

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -5.04%/yr (t=-1.275)  | **Adj R²:** 0.0033

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 39.1%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.7%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
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
