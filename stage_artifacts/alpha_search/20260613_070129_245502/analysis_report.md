# Strategy Diagnostic Report: CatBoost 팩터 배분 — Ordered Boosting으로 시계열 overfitting 방지
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0486 | **ICIR:** 0.378 | **IC > 0 rate:** 63.3%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.774 | **Positive rate:** 69.1%
- **3Y Rolling Sharpe (avg):** 0.636

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00239 | **NW t-stat:** 2.205 (significant)
- **Avg Cross-sectional R²:** 0.0620

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 1.94%/yr (t=1.223)  | **Adj R²:** 0.6080

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0974 (lower = more diversified)
- **Avg Period Turnover:** 12.4%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 2, common>50%: 5)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.24 < -0.1 & 초과CAGR -3.6%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 35.9% > 35% & BM상관 0.75 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
