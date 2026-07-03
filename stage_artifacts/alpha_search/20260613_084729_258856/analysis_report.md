# Strategy Diagnostic Report: Isolation Forest — 이상 종목 감지 후 제거 (anomaly gate)
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0484 | **ICIR:** 0.373 | **IC > 0 rate:** 62.1%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.864 | **Positive rate:** 67.9%
- **3Y Rolling Sharpe (avg):** 0.621

## Stress Periods
- **Outperform rate vs BM:** 50.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00232 | **NW t-stat:** 2.144 (significant)
- **Avg Cross-sectional R²:** 0.0621

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 2.76%/yr (t=1.063)  | **Adj R²:** 0.6867

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0962 (lower = more diversified)
- **Avg Period Turnover:** 12.5%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 2, common>50%: 5)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 54.6% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 54.6% > 35% & BM상관 0.80 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.87 -> post-2017 -1.01 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
