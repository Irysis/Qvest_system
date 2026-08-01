# Strategy Diagnostic Report: RESID_INFO_VOL_M60
Generated: 2026-08-02

## Factor Signal Quality
- **IC Mean:** 0.0021 | **ICIR:** 0.020 | **IC > 0 rate:** 48.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.669 | **Positive rate:** 63.0%
- **3Y Rolling Sharpe (avg):** 0.512

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00154 | **NW t-stat:** 1.824 (not significant)
- **Avg Cross-sectional R²:** 0.0573

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 4.00%/yr (t=0.974)  | **Adj R²:** 0.4891

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1272 (lower = more diversified)
- **Avg Period Turnover:** 55.0%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES (overlap: 5300, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 59.9% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
