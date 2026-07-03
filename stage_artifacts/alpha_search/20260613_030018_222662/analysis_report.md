# Strategy Diagnostic Report: 팩터 추세추종 — 팩터 수익률의 이동평균 돌파로 on/off
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0310 | **ICIR:** 0.159 | **IC > 0 rate:** 63.7%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.870 | **Positive rate:** 70.2%
- **3Y Rolling Sharpe (avg):** 0.563

## Stress Periods
- **Outperform rate vs BM:** 100.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00189 | **NW t-stat:** 1.021 (not significant)
- **Avg Cross-sectional R²:** 0.0700

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 8.32%/yr (t=2.138) (significant) | **Adj R²:** 0.4355

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1732 (lower = more diversified)
- **Avg Period Turnover:** 12.7%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 55.6% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 55.6% > 35% & BM상관 0.74 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.65 -> post-2017 -0.04 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
