# Strategy Diagnostic Report: Chen-Welch 2026 Financing Survivors
Generated: 2026-07-09

## Factor Signal Quality
- **IC Mean:** 0.0134 | **ICIR:** 0.103 | **IC > 0 rate:** 50.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.392 | **Positive rate:** 63.2%
- **3Y Rolling Sharpe (avg):** 0.252

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00134 | **NW t-stat:** 1.747 (not significant)
- **Avg Cross-sectional R²:** 0.0555

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -2.07%/yr (t=-0.883)  | **Adj R²:** 0.6505

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1053 (lower = more diversified)
- **Avg Period Turnover:** 26.9%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 12.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES (overlap: 5261, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 58.1% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.19 < -0.1 & 초과CAGR -3.2%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 58.1% > 35% & BM상관 0.75 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
