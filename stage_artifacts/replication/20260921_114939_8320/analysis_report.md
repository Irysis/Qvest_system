# Strategy Diagnostic Report: RF_PAR_B3_11_KQ150
Generated: 2026-09-21

## Factor Signal Quality
- **IC Mean:** 0.0421 | **ICIR:** 0.185 | **IC > 0 rate:** 56.3%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 1.017 | **Positive rate:** 73.4%
- **3Y Rolling Sharpe (avg):** 0.793

## Stress Periods
- **Outperform rate vs BM:** 33.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00000 | **NW t-stat:** 0.000 (not significant)
- **Avg Cross-sectional R²:** 0.0000

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 8.74%/yr (t=2.352) (significant) | **Adj R²:** 0.4910

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 60.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 4094, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
