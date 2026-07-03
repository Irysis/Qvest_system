# Strategy Diagnostic Report: Balanced multi-factor base signal
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0437 | **ICIR:** 0.262 | **IC > 0 rate:** 63.8%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 1.103 | **Positive rate:** 73.8%
- **3Y Rolling Sharpe (avg):** 0.786

## Stress Periods
- **Outperform rate vs BM:** 100.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00345 | **NW t-stat:** 2.763 (significant)
- **Avg Cross-sectional R²:** 0.0707

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 9.56%/yr (t=2.745) (significant) | **Adj R²:** 0.5487

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1359 (lower = more diversified)
- **Avg Period Turnover:** 21.8%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 54.1% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 54.1% > 35% & BM상관 0.80 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 1.10 -> post-2017 -0.18 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
