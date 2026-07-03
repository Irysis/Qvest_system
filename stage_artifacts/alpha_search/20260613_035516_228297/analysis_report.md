# Strategy Diagnostic Report: 잔차 Alpha 추출 — FF5 잔차에서 팩터 프리미엄 제거 후 순수 종목 alpha
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0367 | **ICIR:** 0.180 | **IC > 0 rate:** 60.9%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.848 | **Positive rate:** 72.6%
- **3Y Rolling Sharpe (avg):** 0.556

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00359 | **NW t-stat:** 2.279 (significant)
- **Avg Cross-sectional R²:** 0.0953

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 4.40%/yr (t=1.635)  | **Adj R²:** 0.6231

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1116 (lower = more diversified)
- **Avg Period Turnover:** 18.2%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 3)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 59.5% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 59.5% > 35% & BM상관 0.83 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.71 -> post-2017 -0.27 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
