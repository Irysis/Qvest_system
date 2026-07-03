# Strategy Diagnostic Report: Evolution: STR_1048 v2 + vol_target + DD start 0.08 → MDD 32%→25%
Generated: 2026-06-12

## Factor Signal Quality
- **IC Mean:** 0.0289 | **ICIR:** 0.141 | **IC > 0 rate:** 60.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.754 | **Positive rate:** 71.8%
- **3Y Rolling Sharpe (avg):** 0.559

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00181 | **NW t-stat:** 1.529 (not significant)
- **Avg Cross-sectional R²:** 0.0945

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 1.90%/yr (t=0.787)  | **Adj R²:** 0.6008

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0997 (lower = more diversified)
- **Avg Period Turnover:** 15.1%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 5)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 55.1% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 55.1% > 35% & BM상관 0.78 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
