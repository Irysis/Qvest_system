# Strategy Diagnostic Report: Realized Skewness 국면 — 시장 수익률 비대칭도로 꼬리 위험 감지
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0308 | **ICIR:** 0.177 | **IC > 0 rate:** 58.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.889 | **Positive rate:** 69.9%
- **3Y Rolling Sharpe (avg):** 0.711

## Stress Periods
- **Outperform rate vs BM:** 100.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00072 | **NW t-stat:** 0.541 (not significant)
- **Avg Cross-sectional R²:** 0.0696

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 3.76%/yr (t=1.539)  | **Adj R²:** 0.4997

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1226 (lower = more diversified)
- **Avg Period Turnover:** 7.7%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 4, common>50%: 9)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [ ] FMT-01: Structural MDD
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 44.8% > 35% & BM상관 0.72 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.63 -> post-2017 -0.91 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
