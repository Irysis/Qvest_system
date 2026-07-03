# Strategy Diagnostic Report: Anti-Herding — 기관/외국인 과매수 종목 회피 + 소외 종목 선호
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** -0.0026 | **ICIR:** -0.024 | **IC > 0 rate:** 48.4%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.244 | **Positive rate:** 56.6%
- **3Y Rolling Sharpe (avg):** 0.027

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00168 | **NW t-stat:** -1.637 (not significant)
- **Avg Cross-sectional R²:** 0.0612

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -5.37%/yr (t=-2.233) (significant) | **Adj R²:** 0.6665

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1015 (lower = more diversified)
- **Avg Period Turnover:** 53.2%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 62.7% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.55 < -0.1 & 초과CAGR -7.1%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 62.7% > 35% & BM상관 0.82 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
