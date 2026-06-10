# Strategy Diagnostic Report: Sector Spillover (Hou2007) MOM63 follower=all
Generated: 2026-06-07

## Factor Signal Quality
- **IC Mean:** 0.0043 | **ICIR:** 0.028 | **IC > 0 rate:** 52.3%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.590 | **Positive rate:** 67.3%
- **3Y Rolling Sharpe (avg):** 0.363

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00309 | **NW t-stat:** 2.283 (significant)
- **Avg Cross-sectional R²:** 0.0629

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 3.88%/yr (t=0.908)  | **Adj R²:** 0.4999

## Portfolio Characteristics
- **Avg Sector HHI:** 0.3431 (lower = more diversified)
- **Avg Period Turnover:** 41.1%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** NO (overlap: 5256, strat-only: 13, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
