# Strategy Diagnostic Report: RF_PAR_B3_11_KOSDAQ150
Generated: 2026-09-01

## Factor Signal Quality
- **IC Mean:** 0.0087 | **ICIR:** 0.046 | **IC > 0 rate:** 51.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.552 | **Positive rate:** 61.7%
- **3Y Rolling Sharpe (avg):** 0.383

## Stress Periods
- **Outperform rate vs BM:** 67.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00000 | **NW t-stat:** 0.000 (not significant)
- **Avg Cross-sectional R²:** 0.0000

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 9.59%/yr (t=1.254)  | **Adj R²:** 0.1663

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 40.4%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 33.3%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 4080, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
