# Strategy Diagnostic Report: RP_AUTO_250818592
Generated: 2026-10-05

## Factor Signal Quality
- **IC Mean:** 0.0171 | **ICIR:** 0.152 | **IC > 0 rate:** 58.4%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.909 | **Positive rate:** 65.4%
- **3Y Rolling Sharpe (avg):** 0.632

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00156 | **NW t-stat:** 1.525 (not significant)
- **Avg Cross-sectional R²:** 0.0608

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 5.58%/yr (t=1.306)  | **Adj R²:** 0.5233

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 71.4%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5343, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
