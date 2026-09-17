# Strategy Diagnostic Report: RP_AUTO_180601743
Generated: 2026-09-17

## Factor Signal Quality
- **IC Mean:** -0.0150 | **ICIR:** -0.102 | **IC > 0 rate:** 44.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.327 | **Positive rate:** 55.4%
- **3Y Rolling Sharpe (avg):** 0.152

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00158 | **NW t-stat:** -1.487 (not significant)
- **Avg Cross-sectional R²:** 0.0600

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -3.18%/yr (t=-0.887)  | **Adj R²:** 0.5191

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 89.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5334, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
