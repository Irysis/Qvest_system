# Strategy Diagnostic Report: STR_valmomqual_3way
Generated: 2026-06-05

## Factor Signal Quality
- **IC Mean:** 0.0273 | **ICIR:** 0.210 | **IC > 0 rate:** 60.2%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.913 | **Positive rate:** 70.4%
- **3Y Rolling Sharpe (avg):** 0.643

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00290 | **NW t-stat:** 3.266 (significant)
- **Avg Cross-sectional R²:** 0.0558

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 5.72%/yr (t=1.792)  | **Adj R²:** 0.5503

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1177 (lower = more diversified)
- **Avg Period Turnover:** 12.6%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 11.5%
- **Crowding Risk:** LOW (persistent>75%: 1, common>50%: 3)
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
