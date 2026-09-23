# Strategy Diagnostic Report: RP_AUTO_220205702
Generated: 2026-09-24

## Factor Signal Quality
- **IC Mean:** 0.0040 | **ICIR:** 0.042 | **IC > 0 rate:** 55.3%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.699 | **Positive rate:** 65.3%
- **3Y Rolling Sharpe (avg):** 0.359

## Stress Periods
- **Outperform rate vs BM:** 25.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00110 | **NW t-stat:** 0.470 (not significant)
- **Avg Cross-sectional R²:** 0.0541

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 2.12%/yr (t=0.740)  | **Adj R²:** 0.6853

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 55.7%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.7%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 4)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5300, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
