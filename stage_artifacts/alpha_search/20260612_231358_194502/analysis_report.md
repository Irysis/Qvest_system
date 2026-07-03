# Strategy Diagnostic Report: 5F EW + MRS12/25 — 5팩터 EW + STR_1071 MDD 최적 overlay
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0413 | **ICIR:** 0.277 | **IC > 0 rate:** 61.8%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.807 | **Positive rate:** 68.9%
- **3Y Rolling Sharpe (avg):** 0.641

## Stress Periods
- **Outperform rate vs BM:** 100.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00190 | **NW t-stat:** 1.620 (not significant)
- **Avg Cross-sectional R²:** 0.0647

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 3.88%/yr (t=1.621)  | **Adj R²:** 0.4805

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1451 (lower = more diversified)
- **Avg Period Turnover:** 9.1%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 1, common>50%: 8)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 46.1% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 46.1% > 35% & BM상관 0.72 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [x] FMT-07: Publication Decay — AUTO: 활성SR pre-2017 0.54 -> post-2017 -0.95 — 논문발표 후 알파 소진 패턴
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
