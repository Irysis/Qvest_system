# Strategy Diagnostic Report: Sector Spillover (Hou2007) MOM21 follower=small
Generated: 2026-06-07

## Factor Signal Quality
- **IC Mean:** 0.0125 | **ICIR:** 0.042 | **IC > 0 rate:** 52.3%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 1.028 | **Positive rate:** 65.5%
- **3Y Rolling Sharpe (avg):** 0.804

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.01139 | **NW t-stat:** 2.699 (significant)
- **Avg Cross-sectional R²:** 0.1065

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 7.38%/yr (t=1.656)  | **Adj R²:** 0.5138

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1634 (lower = more diversified)
- **Avg Period Turnover:** 17.1%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.8%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 2)
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
