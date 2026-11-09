# Strategy Diagnostic Report: Piotroski2000_FSCORE_HighBM_v_rank
Generated: 2026-11-09

## Factor Signal Quality
- **IC Mean:** 0.0865 | **ICIR:** 0.922 | **IC > 0 rate:** 77.3%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.638 | **Positive rate:** 66.4%
- **3Y Rolling Sharpe (avg):** 0.625

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.04388 | **NW t-stat:** 3.910 (significant)
- **Avg Cross-sectional R²:** 0.0446

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 8.79%/yr (t=2.789) (significant) | **Adj R²:** 0.0603

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 78.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.5%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 1)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5308, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
