# Strategy Diagnostic Report: Alpha 분해 전략 — 팩터별 alpha를 국면별로 분해하여 최적 배분
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0243 | **ICIR:** 0.162 | **IC > 0 rate:** 57.0%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.698 | **Positive rate:** 69.2%
- **3Y Rolling Sharpe (avg):** 0.450

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00108 | **NW t-stat:** 1.276 (not significant)
- **Avg Cross-sectional R²:** 0.0798

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 0.54%/yr (t=0.239)  | **Adj R²:** 0.6758

## Portfolio Characteristics
- **Avg Sector HHI:** 0.0865 (lower = more diversified)
- **Avg Period Turnover:** 13.3%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 6)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 57.3% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 57.3% > 35% & BM상관 0.83 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
