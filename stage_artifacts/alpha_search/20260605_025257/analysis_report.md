# Strategy Diagnostic Report: AS_momvol_ovn
Generated: 2026-06-05

## Factor Signal Quality
- **IC Mean:** 0.0018 | **ICIR:** 0.010 | **IC > 0 rate:** 50.5%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.096 | **Positive rate:** 38.3%
- **3Y Rolling Sharpe (avg):** -0.298

## Stress Periods
- **Outperform rate vs BM:** 20.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00278 | **NW t-stat:** 2.290 (significant)
- **Avg Cross-sectional R²:** 0.0651

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -11.41%/yr (t=-1.734)  | **Adj R²:** 0.1588

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1768 (lower = more diversified)
- **Avg Period Turnover:** 36.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** NO (overlap: 8810, strat-only: 13, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
