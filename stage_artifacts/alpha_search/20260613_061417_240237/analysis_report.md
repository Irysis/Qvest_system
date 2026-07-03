# Strategy Diagnostic Report: LightGBM 팩터 배분 — XGBoost 대비 속도 우위, leaf-wise 학습
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0324 | **ICIR:** 0.201 | **IC > 0 rate:** 58.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.677 | **Positive rate:** 66.8%
- **3Y Rolling Sharpe (avg):** 0.538

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00235 | **NW t-stat:** 1.704 (not significant)
- **Avg Cross-sectional R²:** 0.0572

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 1.26%/yr (t=0.632)  | **Adj R²:** 0.4845

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1228 (lower = more diversified)
- **Avg Period Turnover:** 9.4%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 4)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.26 < -0.1 & 초과CAGR -3.9%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 38.8% > 35% & BM상관 0.71 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
