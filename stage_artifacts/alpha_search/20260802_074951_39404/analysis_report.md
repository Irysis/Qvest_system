# Strategy Diagnostic Report: T_RetAutoCorr_12M
Generated: 2026-08-02

## Factor Signal Quality
- **IC Mean:** 0.0137 | **ICIR:** 0.181 | **IC > 0 rate:** 57.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.576 | **Positive rate:** 68.5%
- **3Y Rolling Sharpe (avg):** 0.351

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00178 | **NW t-stat:** 2.738 (significant)
- **Avg Cross-sectional R²:** 0.0530

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 1.35%/yr (t=0.481)  | **Adj R²:** 0.5867

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1134 (lower = more diversified)
- **Avg Period Turnover:** 23.7%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 0)
- **Sample Aligned:** YES (overlap: 5300, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 61.2% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [ ] FMT-02: Factor Degeneration
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 61.2% > 35% & BM상관 0.75 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
