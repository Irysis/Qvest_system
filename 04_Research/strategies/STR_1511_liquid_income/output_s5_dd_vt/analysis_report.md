# Strategy Diagnostic Report: STR_1511_DD_VT
Generated: 2026-03-26

## Factor Signal Quality
- **IC Mean:** 0.0176 | **ICIR:** 0.223 | **IC > 0 rate:** 61.4%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.484 | **Positive rate:** 59.6%
- **3Y Rolling Sharpe (avg):** 0.477

## Stress Periods
- **Outperform rate vs BM:** 100.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00012 | **NW t-stat:** -0.189 (not significant)
- **Avg Cross-sectional R²:** 0.0440

## Multi-Factor Alpha
- **Best Model:** Fama-French 3-Factor | **Alpha:** -1.08%/yr (t=-0.414)  | **Adj R²:** 0.4441

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0956 (lower = more diversified)
- **Avg Period Turnover:** 17.9%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 1, common>50%: 3)
- **Sample Aligned:** YES (overlap: 5095, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
