# Strategy Diagnostic Report: Tail Risk Budget — CVaR 기여도 균등화 가중 (꼬리 위험 관리)
Generated: 2026-06-13

## Factor Signal Quality
- **IC Mean:** 0.0090 | **ICIR:** 0.040 | **IC > 0 rate:** 50.4%

## Rolling Sharpe
- **1Y Rolling Sharpe (avg):** 0.571 | **Positive rate:** 64.5%
- **3Y Rolling Sharpe (avg):** 0.363

## Stress Periods
- **Outperform rate vs BM:** 75.0%
(See analysis_stress.csv for details)

## Fama-MacBeth Regression
- **Score lambda:** -0.00047 | **NW t-stat:** -0.305 (not significant)
- **Avg Cross-sectional R²:** 0.1003

## Multi-Factor Alpha
- **Best Model:** FF3 | **Alpha:** -0.65%/yr (t=-0.270)  | **Adj R²:** 0.5734

## Portfolio Characteristics
- **Avg Sector HHI:** 0.1006 (lower = more diversified)
- **Avg Period Turnover:** 13.4%

## Risk Audit (Ch.07 D/F/G)
- **Avg Illiquid Holdings:** 10.0%
- **Crowding Risk:** LOW (persistent>75%: 0, common>50%: 7)
- **Sample Aligned:** YES (overlap: 5266, strat-only: 0, bm-only: 0)

## Failure Mode Diagnosis (for SPMR)
- [x] FMT-01: Structural MDD — AUTO: MDD 56.8% > 45% — 선택 종목군의 위기 동반급락(구조적 꼬리위험)
- [x] FMT-02: Factor Degeneration — AUTO: IR -0.29 < -0.1 & 초과CAGR -3.8%p < 0 — KR에서 팩터 방향 역작동 의심
- [ ] FMT-03: Ensemble Dilution
- [x] FMT-04: Regime Blindness — AUTO: MDD 56.8% > 35% & BM상관 0.77 >= 0.7 — 위기국면 동조 낙폭(국면필터 부재)
- [ ] FMT-05: Turnover Toxicity
- [ ] FMT-06: Korea-Specific Signal Inversion
- [ ] FMT-07: Publication Decay
- [ ] FMT-08: Regime Overfit

(FMT 자동판정: run_alpha_search.R::.judge_fmt rule 기반 — FMT-06은 수동 진단 전용)
