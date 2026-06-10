# Strategy Diagnostic Report: valmom_AMP2013_winz_smoke
Generated: 2026-06-10

## Factor Signal Quality
- **IC Mean:** 0.0284 | **ICIR:** 0.203 | **IC > 0 rate:** 59.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 1.073 | **Positive rate:** 74.6%
- **3Y Rolling Sharpe (avg):** 0.741

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00366 | **NW t-stat:** 3.347 (significant)
- **Avg Cross-sectional R²:** 0.0571

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 7.79%/yr (t=2.235) (significant) | **Adj R²:** 0.6567

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1056 (lower = more diversified)
- **Avg Period Turnover:** 16.9%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 11.3%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 2)
- **Sample Aligned:** NO (overlap: 5257, strat-only: 13, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 60.7% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [x] FMT-03: Ensemble Dilution — AUTO: 앙상블/블렌드 구성 + grade F — 결합 시 강점 희석 의심 (키워드 기반 heuristic)
- [x] FMT-04: Regime Blindness — AUTO: MDD 60.7% > 35% & BM상관 0.80 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 1.15 -> post-2017 -0.11 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
