# Strategy Diagnostic Report: RP_AUTO_250818592
Generated: 2026-10-05

## Factor Signal Quality
- **IC Mean:** 0.0278 | **ICIR:** 0.185 | **IC > 0 rate:** 60.3%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.930 | **Positive rate:** 63.5%
- **3Y Rolling Sharpe (avg):** 0.597

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00308 | **NW t-stat:** 2.463 (significant)
- **Avg Cross-sectional R²:** 0.0667

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 6.18%/yr (t=1.292)  | **Adj R²:** 0.5018

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0000 (lower = more diversified)
- **Avg Period Turnover:** 66.0%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES [ALIGNED] (overlap: 5342, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
