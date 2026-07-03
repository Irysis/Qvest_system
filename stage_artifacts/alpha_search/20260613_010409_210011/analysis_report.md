# Strategy Diagnostic Report: Momentum×Quality 바벨 — 고모멘텀+고품질 교집합 종목 선정
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0356 | **ICIR:** 0.206 | **IC > 0 rate:** 62.1%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.964 | **Positive rate:** 74.3%
- **3Y Rolling Sharpe (avg):** 0.708

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00264 | **NW t-stat:** 1.906 (not significant)
- **Avg Cross-sectional R²:** 0.0665

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 8.21%/yr (t=2.568) (significant) | **Adj R²:** 0.4864

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1453 (lower = more diversified)
- **Avg Period Turnover:** 9.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 1, common>50%: 4)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 46.8% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 46.8% > 35% & BM상관 0.76 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.93 -> post-2017 -0.36 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
