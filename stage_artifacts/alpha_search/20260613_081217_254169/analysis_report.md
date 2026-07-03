# Strategy Diagnostic Report: Quantile Regression Forest — 수익률 분포 예측 → CVaR 최소화 종목 선정
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0351 | **ICIR:** 0.191 | **IC > 0 rate:** 58.6%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.686 | **Positive rate:** 71.2%
- **3Y Rolling Sharpe (avg):** 0.472

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** 0.00111 | **NW t-stat:** 0.851 (not significant)
- **Avg Cross-sectional R²:** 0.0683

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** 0.88%/yr (t=0.390)  | **Adj R²:** 0.5925

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1007 (lower = more diversified)
- **Avg Period Turnover:** 8.6%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 1, common>50%: 6)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 59.7% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.23 < -0.1 & 초과CAGR -3.1%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 59.7% > 35% & BM상관 0.76 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
