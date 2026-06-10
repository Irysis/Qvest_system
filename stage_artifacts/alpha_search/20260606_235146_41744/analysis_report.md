# Strategy Diagnostic Report: VolPremium_GKM2001
Generated: 2026-06-07

## Factor Signal Quality
- **IC Mean:** 0.0126 | **ICIR:** 0.133 | **IC > 0 rate:** 54.7%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.660 | **Positive rate:** 70.5%
- **3Y Rolling Sharpe (avg):** 0.399

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00124 | **NW t-stat:** 1.890 (not significant)
- **Avg Cross-sectional R²:** 0.0563

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 1.06%/yr (t=0.525)  | **Adj R²:** 0.6956

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0666 (lower = more diversified)
- **Avg Period Turnover:** 52.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.3%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 55)
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
