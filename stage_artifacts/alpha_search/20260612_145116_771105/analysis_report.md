# Strategy Diagnostic Report: Short-Term Reversal Base Signal
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0350 | **ICIR:** 0.364 | **IC > 0 rate:** 62.5%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** -0.626 | **Positive rate:** 16.0%
- **3Y Rolling Sharpe (avg):** -0.759

## Stress Periods
- **Outperform rate vs BM:** 0.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00363 | **NW t-stat:** 3.975 (significant)
- **Avg Cross-sectional R²:** 0.0237

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -38.10%/yr (t=-4.646) (significant) | **Adj R²:** 0.2215

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1349 (lower = more diversified)
- **Avg Period Turnover:** 88.1%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 100.0% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.51 < -0.1 & 초과CAGR -34.9%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
