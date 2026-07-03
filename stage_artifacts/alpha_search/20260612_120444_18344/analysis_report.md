# Strategy Diagnostic Report: Quality GP Decile Smoke
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0139 | **ICIR:** 0.106 | **IC > 0 rate:** 55.1%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.636 | **Positive rate:** 64.9%
- **3Y Rolling Sharpe (avg):** 0.449

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00042 | **NW t-stat:** 0.439 (not significant)
- **Avg Cross-sectional R²:** 0.0596

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 2.80%/yr (t=0.985)  | **Adj R²:** 0.4693

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1635 (lower = more diversified)
- **Avg Period Turnover:** 3.2%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 11.4%
- **Crowding Risk:** LOW (persistent>75%: 3, common>50%: 16)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 55.7% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 55.7% > 35% & BM상관 0.72 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
