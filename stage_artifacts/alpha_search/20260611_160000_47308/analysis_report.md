# Strategy Diagnostic Report: DART Disclosure Earliness (KR-native)
Generated: 2026-06-11

## Factor Signal Quality
- **IC Mean:** -0.0006 | **ICIR:** -0.009 | **IC > 0 rate:** 46.7%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.350 | **Positive rate:** 49.6%
- **3Y Rolling Sharpe (avg):** 0.239

## Stress Periods
- **Outperform rate vs BM:** 100.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00065 | **NW t-stat:** 0.692 (not significant)
- **Avg Cross-sectional R²:** 0.0455

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -1.99%/yr (t=-0.509)  | **Adj R²:** 0.6150

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0979 (lower = more diversified)
- **Avg Period Turnover:** 25.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.8%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 4)
- **Sample Aligned:** NO (overlap: 2489, strat-only: 13, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
