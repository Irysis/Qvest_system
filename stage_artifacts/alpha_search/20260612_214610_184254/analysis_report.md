# Strategy Diagnostic Report: 조건부 팩터 — Dispersion 기반 Defense/Momentum 스위칭 + Quality Gate
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0381 | **ICIR:** 0.222 | **IC > 0 rate:** 63.4%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.973 | **Positive rate:** 74.7%
- **3Y Rolling Sharpe (avg):** 0.726

## Stress Periods
- **Outperform rate vs BM:** 100.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00293 | **NW t-stat:** 2.071 (significant)
- **Avg Cross-sectional R²:** 0.0666

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 8.65%/yr (t=2.613) (significant) | **Adj R²:** 0.4703

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1429 (lower = more diversified)
- **Avg Period Turnover:** 9.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 6)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 48.4% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 48.4% > 35% & BM상관 0.76 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.96 -> post-2017 -0.42 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
