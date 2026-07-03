# Strategy Diagnostic Report: 3F Core v2 — Defense + Consensus + TPGap (검증된 3축 독립 alpha)
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0186 | **ICIR:** 0.079 | **IC > 0 rate:** 52.8%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.631 | **Positive rate:** 68.6%
- **3Y Rolling Sharpe (avg):** 0.444

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00076 | **NW t-stat:** 0.526 (not significant)
- **Avg Cross-sectional R²:** 0.1012

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -0.06%/yr (t=-0.029)  | **Adj R²:** 0.6136

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0945 (lower = more diversified)
- **Avg Period Turnover:** 13.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 7)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 54.6% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.16 < -0.1 & 초과CAGR -2.1%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 54.6% > 35% & BM상관 0.78 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
