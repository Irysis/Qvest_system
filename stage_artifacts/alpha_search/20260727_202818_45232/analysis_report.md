# Strategy Diagnostic Report: VOL_ADJ_VOL_SURP_v1
Generated: 2026-07-27

## Factor Signal Quality
- **IC Mean:** -0.0040 | **ICIR:** -0.042 | **IC > 0 rate:** 51.4%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.433 | **Positive rate:** 58.0%
- **3Y Rolling Sharpe (avg):** 0.272

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00021 | **NW t-stat:** -0.234 (not significant)
- **Avg Cross-sectional R²:** 0.0559

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -2.45%/yr (t=-0.646)  | **Adj R²:** 0.5290

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1265 (lower = more diversified)
- **Avg Period Turnover:** 82.9%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES (overlap: 5296, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 67.2% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.38 < -0.1 & 초과CAGR -7.0%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [ ] FMT-04: Regime Blindness
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
