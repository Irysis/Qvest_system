# Strategy Diagnostic Report: STR_residmom_paper_2005
Generated: 2026-06-05

## Factor Signal Quality
- **IC Mean:** 0.0121 | **ICIR:** 0.093 | **IC > 0 rate:** 52.5%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.693 | **Positive rate:** 70.5%
- **3Y Rolling Sharpe (avg):** 0.463

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00090 | **NW t-stat:** 0.842 (not significant)
- **Avg Cross-sectional R²:** 0.0582

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 1.90%/yr (t=0.844)  | **Adj R²:** 0.7003

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0663 (lower = more diversified)
- **Avg Period Turnover:** 16.2%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.4%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 22)
- **Sample Aligned:** NO (overlap: 4884, strat-only: 13, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
