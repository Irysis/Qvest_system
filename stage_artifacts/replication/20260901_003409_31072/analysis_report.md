# Strategy Diagnostic Report: RP_AUTO_250520608
Generated: 2026-09-01

## Factor Signal Quality
- **IC Mean:** 0.0030 | **ICIR:** 0.039 | **IC > 0 rate:** 52.7%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.247 | **Positive rate:** 38.5%
- **3Y Rolling Sharpe (avg):** -0.303

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00015 | **NW t-stat:** 0.277 (not significant)
- **Avg Cross-sectional R²:** 0.0546

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -5.21%/yr (t=-1.275)  | **Adj R²:** 0.0047

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 39.2%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.7%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5322, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
