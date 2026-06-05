# Strategy Diagnostic Report: AS_mom52w_sp
Generated: 2026-06-04

## Factor Signal Quality
- **IC Mean:** 0.0209 | **ICIR:** 0.103 | **IC > 0 rate:** 58.5%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.306 | **Positive rate:** 60.0%
- **3Y Rolling Sharpe (avg):** 0.144

## Stress Periods
- **Outperform rate vs BM:** 60.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00278 | **NW t-stat:** 2.029 (significant)
- **Avg Cross-sectional R²:** 0.0750

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 6.78%/yr (t=1.154)  | **Adj R²:** 0.1994

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1411 (lower = more diversified)
- **Avg Period Turnover:** 65.0%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** NO (overlap: 8690, strat-only: 13, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit
