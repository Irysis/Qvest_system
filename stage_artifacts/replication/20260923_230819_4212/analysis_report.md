# Strategy Diagnostic Report: RP_AUTO_251112129
Generated: 2026-09-23

## Factor Signal Quality
- **IC Mean:** 0.0338 | **ICIR:** 0.361 | **IC > 0 rate:** 60.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.930 | **Positive rate:** 69.5%
- **3Y Rolling Sharpe (avg):** 0.748

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00489 | **NW t-stat:** 2.697 (significant)
- **Avg Cross-sectional R²:** 0.0548

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 3.45%/yr (t=1.423)  | **Adj R²:** 0.5823

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 50.2%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 11.7%
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
