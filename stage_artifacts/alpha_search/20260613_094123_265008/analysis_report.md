# Strategy Diagnostic Report: KNN Regression — 유사 과거 국면 k개 평균으로 팩터 수익률 예측
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0324 | **ICIR:** 0.201 | **IC > 0 rate:** 58.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.782 | **Positive rate:** 66.6%
- **3Y Rolling Sharpe (avg):** 0.501

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00235 | **NW t-stat:** 1.704 (not significant)
- **Avg Cross-sectional R²:** 0.0572

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 3.11%/yr (t=0.853)  | **Adj R²:** 0.5667

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1228 (lower = more diversified)
- **Avg Period Turnover:** 9.4%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 4)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 63.1% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 63.1% > 35% & BM상관 0.76 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.72 -> post-2017 -0.71 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
